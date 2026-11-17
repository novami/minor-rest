// Package httpclient odesílá připravené requesty (kap. 4 plánu).
package httpclient

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/novami/minor-rest/internal/model"
)

// HTTP verze v nastavení.
const (
	VersionAuto  = "auto"
	VersionHTTP1 = "http1"
	VersionHTTP2 = "http2"
)

// Request je request s vyhodnocenými proměnnými a sestavenou URL.
type Request struct {
	Method  string
	URL     string
	Headers []model.KV // odešlou se jen zapnuté, pořadí se zachová
	Body    model.Body
	BaseDir string   // kořen projektu pro relativní cesty souborů
	NoAuto  []string // automatické hlavičky, které uživatel vypnul (User-Agent, Accept, Content-Type)
}

// Options jsou výsledná (zděděná) nastavení odeslání.
type Options struct {
	HTTPVersion     string
	FollowRedirects bool
	MaxRedirects    int
	Timeout         time.Duration // 0 = bez limitu
	VerifyTLS       bool
	UserAgent       string
}

// OptionsFrom převede složená nastavení na Options (nil položky = nulové hodnoty).
func OptionsFrom(s model.HTTPSettings, userAgent string) Options {
	o := Options{HTTPVersion: VersionAuto, UserAgent: userAgent}
	if s.HTTPVersion != nil {
		o.HTTPVersion = *s.HTTPVersion
	}
	if s.FollowRedirects != nil {
		o.FollowRedirects = *s.FollowRedirects
	}
	if s.MaxRedirects != nil {
		o.MaxRedirects = *s.MaxRedirects
	}
	if s.TimeoutMs != nil {
		o.Timeout = time.Duration(*s.TimeoutMs) * time.Millisecond
	}
	if s.VerifyTLS != nil {
		o.VerifyTLS = *s.VerifyTLS
	}
	return o
}

// Redirect je jeden skok přesměrování.
type Redirect struct {
	Status   int    `json:"status" yaml:"status"`
	Method   string `json:"method" yaml:"method"`
	URL      string `json:"url" yaml:"url"`
	Location string `json:"location" yaml:"location"`
}

// TLSInfo popisuje TLS spojení posledního skoku.
type TLSInfo struct {
	Version    string `json:"version" yaml:"version"`
	Cipher     string `json:"cipher" yaml:"cipher"`
	ServerName string `json:"serverName" yaml:"serverName"`
	Subject    string `json:"subject,omitempty" yaml:"subject,omitempty"`
	Issuer     string `json:"issuer,omitempty" yaml:"issuer,omitempty"`
	NotAfter   string `json:"notAfter,omitempty" yaml:"notAfter,omitempty"` // RFC 3339
}

// Result je výsledek odeslání.
type Result struct {
	Status     int
	StatusText string
	Proto      string
	Headers    []model.KV // pořadí dle abecedy názvů (net/http pořadí ze serveru nedrží), opakované jako samostatné řádky
	Body       []byte
	Redirects  []Redirect
	TLS        *TLSInfo
}

// Engine odesílá requesty a umožňuje je rušit podle runID.
type Engine struct {
	mu   sync.Mutex
	runs map[string]context.CancelCauseFunc
}

func New() *Engine { return &Engine{runs: map[string]context.CancelCauseFunc{}} }

// Cancel zruší běžící odeslání; neznámé runID ignoruje.
func (e *Engine) Cancel(runID string) {
	e.mu.Lock()
	cancel := e.runs[runID]
	e.mu.Unlock()
	if cancel != nil {
		cancel(errCanceled)
	}
}

// Do odešle request a přečte celé tělo odpovědi; chyby jsou *Error.
func (e *Engine) Do(ctx context.Context, runID string, r Request, o Options) (*Result, error) {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	if o.Timeout > 0 {
		var stop context.CancelFunc
		ctx, stop = context.WithTimeoutCause(ctx, o.Timeout, errTimeout)
		defer stop()
	}
	e.mu.Lock()
	e.runs[runID] = cancel
	e.mu.Unlock()
	defer func() {
		e.mu.Lock()
		delete(e.runs, runID)
		e.mu.Unlock()
	}()

	req, err := newRequest(ctx, r, o)
	if err != nil {
		return nil, err
	}
	tr := newTransport(req.URL.Scheme, o)
	defer tr.CloseIdleConnections()
	res := &Result{}
	client := &http.Client{Transport: tr, CheckRedirect: checkRedirect(o, res)}
	http2Only := o.HTTPVersion == VersionHTTP2

	resp, err := client.Do(req)
	if err != nil {
		return nil, classify(ctx, err, http2Only)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, classify(ctx, err, http2Only)
	}
	res.Status = resp.StatusCode
	res.StatusText = strings.TrimSpace(strings.TrimPrefix(resp.Status, fmt.Sprint(resp.StatusCode)))
	res.Proto = resp.Proto
	res.Headers = headerRows(resp.Header)
	res.Body = body
	res.TLS = tlsInfo(resp.TLS)
	return res, nil
}

func newRequest(ctx context.Context, r Request, o Options) (*http.Request, error) {
	u, err := url.Parse(r.URL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		if err == nil {
			err = errors.New(r.URL)
		}
		return nil, newErr(ErrURLInvalid, err)
	}
	pl, err := buildBody(r.Body, r.BaseDir)
	if err != nil {
		return nil, err
	}
	var body io.ReadCloser
	if pl.open != nil {
		if body, err = pl.open(); err != nil {
			return nil, err
		}
	}
	req, err := http.NewRequestWithContext(ctx, strings.ToUpper(r.Method), u.String(), body)
	if err != nil {
		if body != nil {
			body.Close()
		}
		return nil, newErr(ErrMethodInvalid, err)
	}
	if pl.open != nil {
		req.ContentLength = pl.size
		req.GetBody = pl.open
		if pl.size == 0 {
			req.Body, req.GetBody = http.NoBody, nil
		}
	}

	has := map[string]bool{}
	for _, h := range r.Headers {
		name := strings.TrimSpace(h.Name)
		if !h.Enabled || name == "" {
			continue
		}
		key := http.CanonicalHeaderKey(name)
		has[key] = true
		switch key {
		case "Host":
			req.Host = h.Value
		case "Content-Length": // určuje délka těla
		default:
			req.Header.Add(key, h.Value)
		}
	}
	off := map[string]bool{}
	for _, n := range r.NoAuto {
		off[http.CanonicalHeaderKey(n)] = true
	}
	auto := func(key, val string) {
		if !has[key] && !off[key] && val != "" {
			req.Header.Set(key, val)
		}
	}
	auto("User-Agent", o.UserAgent)
	auto("Accept", "*/*")
	if pl.open != nil {
		auto("Content-Type", pl.contentType)
		fixBoundary(req.Header, pl.contentType)
	}
	if !has["User-Agent"] && (off["User-Agent"] || o.UserAgent == "") {
		req.Header.Set("User-Agent", "") // jinak by Go doplnilo vlastní
	}
	return req, nil
}

// fixBoundary doplní boundary do uživatelského multipart Content-Type bez něj.
func fixBoundary(h http.Header, autoCT string) {
	ct := h.Get("Content-Type")
	i := strings.Index(autoCT, "boundary=")
	if i < 0 || !strings.HasPrefix(strings.ToLower(ct), "multipart/") || strings.Contains(strings.ToLower(ct), "boundary=") {
		return
	}
	h.Set("Content-Type", ct+"; "+autoCT[i:])
}

func newTransport(scheme string, o Options) *http.Transport {
	tr := http.DefaultTransport.(*http.Transport).Clone()
	tr.DisableCompression = true
	tr.TLSClientConfig = &tls.Config{InsecureSkipVerify: !o.VerifyTLS}
	var p http.Protocols
	switch o.HTTPVersion {
	case VersionHTTP1:
		p.SetHTTP1(true)
	case VersionHTTP2:
		if scheme == "http" {
			p.SetUnencryptedHTTP2(true) // h2c prior knowledge
		} else {
			p.SetHTTP2(true)
		}
	default:
		p.SetHTTP1(true)
		p.SetHTTP2(true)
	}
	tr.Protocols = &p
	return tr
}

func checkRedirect(o Options, res *Result) func(*http.Request, []*http.Request) error {
	return func(req *http.Request, via []*http.Request) error {
		if !o.FollowRedirects {
			return http.ErrUseLastResponse
		}
		prev := via[len(via)-1]
		rd := Redirect{Method: prev.Method, URL: prev.URL.String(), Location: req.URL.String()}
		if req.Response != nil {
			rd.Status = req.Response.StatusCode
			if loc := req.Response.Header.Get("Location"); loc != "" {
				rd.Location = loc
			}
		}
		res.Redirects = append(res.Redirects, rd)
		if len(via) > o.MaxRedirects {
			return &Error{Code: ErrRedirectLimit, Detail: fmt.Sprint(o.MaxRedirects)}
		}
		return nil
	}
}

func headerRows(h http.Header) []model.KV {
	keys := make([]string, 0, len(h))
	for k := range h {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	var rows []model.KV
	for _, k := range keys {
		for _, v := range h[k] {
			rows = append(rows, model.KV{Name: k, Value: v, Enabled: true})
		}
	}
	return rows
}

func tlsInfo(cs *tls.ConnectionState) *TLSInfo {
	if cs == nil {
		return nil
	}
	ti := &TLSInfo{Version: tls.VersionName(cs.Version), Cipher: tls.CipherSuiteName(cs.CipherSuite), ServerName: cs.ServerName}
	if len(cs.PeerCertificates) > 0 {
		c := cs.PeerCertificates[0]
		ti.Subject, ti.Issuer = certName(c.Subject.String(), c), c.Issuer.String()
		ti.NotAfter = c.NotAfter.UTC().Format(time.RFC3339)
	}
	return ti
}

func certName(s string, c *x509.Certificate) string {
	if s == "" && len(c.DNSNames) > 0 {
		return strings.Join(c.DNSNames, ", ")
	}
	return s
}
