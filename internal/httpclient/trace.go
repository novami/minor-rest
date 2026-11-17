package httpclient

import (
	"crypto/tls"
	"net/http/httptrace"
	"sync"
	"time"

	"github.com/novami/minor-rest/internal/model"
)

// Timing jsou časy posledního skoku v ms; TotalMs = od začátku prvního skoku do konce čtení těla.
type Timing struct {
	DNSMs      float64 `json:"dnsMs" yaml:"dnsMs"`
	ConnectMs  float64 `json:"connectMs" yaml:"connectMs"`
	TLSMs      float64 `json:"tlsMs" yaml:"tlsMs"`
	TTFBMs     float64 `json:"ttfbMs" yaml:"ttfbMs"`
	DownloadMs float64 `json:"downloadMs" yaml:"downloadMs"`
	TotalMs    float64 `json:"totalMs" yaml:"totalMs"`
	Reused     bool    `json:"reused,omitempty" yaml:"reused,omitempty"` // spojení použito znovu (bez DNS/connect/TLS)
}

// hop je stav jednoho skoku; hooky httptrace se volají pro každý skok (redirect) znovu.
type hop struct {
	dnsStart, dnsDone, connStart, connDone, tlsStart, tlsDone time.Time
	wrote, firstByte                                          time.Time
	reused                                                    bool
	addrs                                                     []string
	remote, local                                             string
	headers                                                   []model.KV
}

type tracer struct {
	mu    sync.Mutex
	start time.Time
	cur   hop
}

func ms(a, b time.Time) float64 {
	if a.IsZero() || b.IsZero() || b.Before(a) {
		return 0
	}
	return float64(b.Sub(a).Microseconds()) / 1000
}

func (t *tracer) trace() *httptrace.ClientTrace {
	lock := func(f func(h *hop)) {
		t.mu.Lock()
		f(&t.cur)
		t.mu.Unlock()
	}
	return &httptrace.ClientTrace{
		GetConn: func(string) { lock(func(h *hop) { *h = hop{} }) },
		GotConn: func(i httptrace.GotConnInfo) {
			lock(func(h *hop) {
				h.reused = i.Reused
				h.remote, h.local = i.Conn.RemoteAddr().String(), i.Conn.LocalAddr().String()
			})
		},
		DNSStart: func(httptrace.DNSStartInfo) { lock(func(h *hop) { h.dnsStart = time.Now() }) },
		DNSDone: func(i httptrace.DNSDoneInfo) {
			lock(func(h *hop) {
				h.dnsDone = time.Now()
				for _, a := range i.Addrs {
					h.addrs = append(h.addrs, a.String())
				}
			})
		},
		ConnectStart: func(_, _ string) {
			lock(func(h *hop) {
				if h.connStart.IsZero() { // u více adres (happy eyeballs) první pokus
					h.connStart = time.Now()
				}
			})
		},
		ConnectDone: func(_, _ string, err error) {
			lock(func(h *hop) {
				if err == nil {
					h.connDone = time.Now()
				}
			})
		},
		TLSHandshakeStart: func() { lock(func(h *hop) { h.tlsStart = time.Now() }) },
		TLSHandshakeDone:  func(tls.ConnectionState, error) { lock(func(h *hop) { h.tlsDone = time.Now() }) },
		WroteHeaderField: func(k string, v []string) {
			lock(func(h *hop) {
				for _, s := range v {
					h.headers = append(h.headers, model.KV{Name: k, Value: s, Enabled: true})
				}
			})
		},
		WroteRequest:         func(httptrace.WroteRequestInfo) { lock(func(h *hop) { h.wrote = time.Now() }) },
		GotFirstResponseByte: func() { lock(func(h *hop) { h.firstByte = time.Now() }) },
	}
}

// last vrátí kopii stavu posledního skoku.
func (t *tracer) last() hop {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.cur
}

func (h hop) timing(start, end time.Time) Timing {
	return Timing{
		DNSMs:      ms(h.dnsStart, h.dnsDone),
		ConnectMs:  ms(h.connStart, h.connDone),
		TLSMs:      ms(h.tlsStart, h.tlsDone),
		TTFBMs:     ms(h.wrote, h.firstByte),
		DownloadMs: ms(h.firstByte, end),
		TotalMs:    ms(start, end),
		Reused:     h.reused,
	}
}
