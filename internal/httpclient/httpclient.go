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
	"net/http/httptrace"
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
	NoAuto  []string // automatické hlavičky, které uživatel vypnul (User-Agent, Accept, Accept-Encoding, Content-Type)
}

// Options jsou výsledná (zděděná) nastavení odeslání.
type Options struct {
	HTTPVersion     string
	FollowRedirects bool
	MaxRedirects    int
	Timeout         time.Duration // 0 = bez limitu
	VerifyTLS       bool
	UserAgent       string
	MaxBodyBytes    int64 // 0 = DefaultMaxBody
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

// Sizes jsou velikosti v bajtech (u HTTP/2 nekomprimované hlavičky).
type Sizes struct {
	ReqHeaders  int64 `json:"reqHeaders" yaml:"reqHeaders"`
	ReqBody     int64 `json:"reqBody" yaml:"reqBody"`
	Headers     int64 `json:"headers" yaml:"headers"`
	BodyWire    int64 `json:"bodyWire" yaml:"bodyWire"`
	BodyDecoded int64 `json:"bodyDecoded" yaml:"bodyDecoded"`
}

// Sent je skutečně odeslaný request posledního skoku.
type Sent struct {
	Method      string     `json:"method" yaml:"method"`
	URL         string     `json:"url" yaml:"url"`
	Headers     []model.KV `json:"headers" yaml:"headers"` // v pořadí odeslání, u HTTP/2 i pseudo-hlavičky
	BodyPreview string     `json:"bodyPreview,omitempty" yaml:"bodyPreview,omitempty"`
	BodySize    int64      `json:"bodySize" yaml:"bodySize"`
}

// Result je výsledek odeslání. Při chybě Do vrací i částečný Result (Sent, Timing, Redirects).
type Result struct {
	Status        int
	StatusText    string
	Proto         string
	Headers       []model.KV // pořadí dle abecedy názvů (net/http pořadí ze serveru nedrží), opakované jako samostatné řádky
	Body          *Body
	Redirects     []Redirect
	TLS           *TLSInfo
	RemoteAddr    string
	LocalAddr     string
	ResolvedAddrs []string
	Timing        Timing
	Sizes         Sizes
	Sent          Sent
	ContentType   string // media type bez parametrů
	Charset       string // "" u binárního obsahu
	IsBinary      bool
	Truncated     bool
}

const keepResults = 20

// Engine odesílá requesty, umožňuje je rušit a drží posledních 20 výsledků.
type Engine struct {
	mu      sync.Mutex
	runs    map[string]context.CancelCauseFunc
	results map[string]*Result
	order   []string // nejstarší první
}

func New() *Engine {
	return &Engine{runs: map[string]context.CancelCauseFunc{}, results: map[string]*Result{}}
}

// Cancel zruší běžící odeslání; neznámé runID ignoruje.
func (e *Engine) Cancel(runID string) {
	e.mu.Lock()
	cancel := e.runs[runID]
	e.mu.Unlock()
	if cancel != nil {
		cancel(errCanceled)
	}
}

// Get vrátí uložený výsledek (posledních 20 úspěšných odeslání).
func (e *Engine) Get(runID string) (*Result, bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	r, ok := e.results[runID]
	return r, ok
}

// Close smaže temp soubory všech držených výsledků.
func (e *Engine) Close() {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, r := range e.results {
		r.Body.remove()
	}
	e.results, e.order = map[string]*Result{}, nil
}

func (e *Engine) keep(runID string, r *Result) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if old, ok := e.results[runID]; ok {
		old.Body.remove()
		e.order = slices.DeleteFunc(e.order, func(s string) bool { return s == runID })
	}
	e.results[runID] = r
	e.order = append(e.order, runID)
	for len(e.order) > keepResults {
		e.results[e.order[0]].Body.remove()
		delete(e.results, e.order[0])
		e.order = e.order[1:]
	}
}

// Do odešle request a přečte tělo odpovědi; chyby jsou *Error.
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

	tr := &tracer{start: time.Now()}
	ctx = httptrace.WithClientTrace(ctx, tr.trace())
	req, pl, err := newRequest(ctx, r, o)
	if err != nil {
		return nil, err
	}
	transport := newTransport(req.URL.Scheme, o)
	defer transport.CloseIdleConnections()
	res := &Result{Sent: Sent{Method: req.Method, URL: req.URL.String(), BodyPreview: pl.preview, BodySize: pl.size}}
	client := &http.Client{Transport: transport, CheckRedirect: checkRedirect(o, res)}
	http2Only := o.HTTPVersion == VersionHTTP2
	fail := func(err error) (*Result, error) {
		h := tr.last()
		res.Timing = h.timing(tr.start, time.Now())
		res.Sent.Headers = h.headers
		return res, classify(ctx, err, http2Only)
	}

	resp, err := client.Do(req)
	if err != nil {
		return fail(err)
	}
	defer resp.Body.Close()
	maxBody := o.MaxBodyBytes
	if maxBody <= 0 {
		maxBody = DefaultMaxBody
	}
	body, wire, truncated, err := readBody(resp.Body, resp.Header.Get("Content-Encoding"), maxBody)
	end := time.Now()
	if err != nil {
		return fail(err)
	}
	h := tr.last()
	res.Status = resp.StatusCode
	res.StatusText = strings.TrimSpace(strings.TrimPrefix(resp.Status, fmt.Sprint(resp.StatusCode)))
	res.Proto = resp.Proto
	res.Headers = headerRows(resp.Header)
	res.Body, res.Truncated = body, truncated
	res.TLS = tlsInfo(resp.TLS)
	res.RemoteAddr, res.LocalAddr, res.ResolvedAddrs = h.remote, h.local, h.addrs
	res.Timing = h.timing(tr.start, end)

	last := resp.Request
	res.Sent.Method, res.Sent.URL, res.Sent.Headers = last.Method, last.URL.String(), h.headers
	if last != req { // po redirectu: 301–303 tělo zahodí
		res.Sent.BodySize = max(last.ContentLength, 0)
		if res.Sent.BodySize == 0 {
			res.Sent.BodyPreview = ""
		}
	}
	res.Sizes = Sizes{
		ReqHeaders:  reqHeadersSize(last, resp.ProtoMajor, h.headers),
		ReqBody:     res.Sent.BodySize,
		Headers:     respHeadersSize(resp, res.Headers),
		BodyWire:    wire,
		BodyDecoded: body.Size(),
	}

	var sample []byte
	if rc, err := body.Open(); err == nil {
		sample, _ = io.ReadAll(io.LimitReader(rc, sniffLen))
		rc.Close()
	}
	res.ContentType, res.Charset, res.IsBinary = sniff(resp.Header.Get("Content-Type"), sample)
	e.keep(runID, res)
	return res, nil
}

func lineSize(name, value string) int64 { return int64(len(name) + 2 + len(value) + 2) }

// reqHeadersSize: request line (jen HTTP/1) + hlavičky + prázdný řádek.
func reqHeadersSize(r *http.Request, protoMajor int, headers []model.KV) int64 {
	var n int64 = 2
	if protoMajor < 2 {
		n += int64(len(r.Method) + 1 + len(r.URL.RequestURI()) + 1 + len("HTTP/1.1") + 2)
	}
	for _, h := range headers {
		n += lineSize(h.Name, h.Value)
	}
	return n
}

// respHeadersSize: status line + hlavičky + prázdný řádek.
func respHeadersSize(resp *http.Response, rows []model.KV) int64 {
	n := int64(len(resp.Proto)+1+len(resp.Status)+2) + 2
	for _, h := range rows {
		n += lineSize(h.Name, h.Value)
	}
	return n
}

func newRequest(ctx context.Context, r Request, o Options) (*http.Request, payload, error) {
	u, err := url.Parse(r.URL)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		if err == nil {
			err = errors.New(r.URL)
		}
		return nil, payload{}, newErr(ErrURLInvalid, err)
	}
	pl, err := buildBody(r.Body, r.BaseDir)
	if err != nil {
		return nil, payload{}, err
	}
	var body io.ReadCloser
	if pl.open != nil {
		if body, err = pl.open(); err != nil {
			return nil, payload{}, err
		}
	}
	req, err := http.NewRequestWithContext(ctx, strings.ToUpper(r.Method), u.String(), body)
	if err != nil {
		if body != nil {
			body.Close()
		}
		return nil, payload{}, newErr(ErrMethodInvalid, err)
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
	auto("Accept-Encoding", "gzip, deflate, br, zstd")
	if pl.open != nil {
		auto("Content-Type", pl.contentType)
		fixBoundary(req.Header, pl.contentType)
	}
	if !has["User-Agent"] && (off["User-Agent"] || o.UserAgent == "") {
		req.Header.Set("User-Agent", "") // jinak by Go doplnilo vlastní
	}
	return req, pl, nil
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
