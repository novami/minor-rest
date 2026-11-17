package httpclient

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/novami/minor-rest/internal/model"
)

var defOpts = Options{HTTPVersion: VersionAuto, FollowRedirects: true, MaxRedirects: 10, Timeout: 5 * time.Second, VerifyTLS: true, UserAgent: "MinorREST/test"}

// echo vrátí metodu, hlavičky a tělo requestu.
func echo(w http.ResponseWriter, r *http.Request) {
	b, _ := io.ReadAll(r.Body)
	w.Header().Set("X-Method", r.Method)
	w.Header().Set("X-Host", r.Host)
	w.Header().Set("X-Proto", r.Proto)
	for k, v := range r.Header {
		w.Header()["Echo-"+k] = v
	}
	w.Write(b)
}

func code(err error) string {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	if err != nil {
		return "?" + err.Error()
	}
	return ""
}

func hdr(res *Result, name string) []string {
	var v []string
	for _, h := range res.Headers {
		if h.Name == name {
			v = append(v, h.Value)
		}
	}
	return v
}

func bodyStr(res *Result) string {
	b, _ := res.Body.Bytes()
	return string(b)
}

func TestMethods(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(echo))
	defer srv.Close()
	e := New()
	for _, m := range []string{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"} {
		res, err := e.Do(context.Background(), "r", Request{Method: m, URL: srv.URL, Body: model.Body{Type: model.BodyText, Raw: "x"}}, defOpts)
		if err != nil || res.Status != 200 || hdr(res, "X-Method")[0] != m {
			t.Fatalf("%s: %v %+v", m, err, res)
		}
		if want := map[bool]string{true: "", false: "x"}[m == "HEAD"]; bodyStr(res) != want {
			t.Errorf("%s: body %q", m, bodyStr(res))
		}
	}
}

func TestHeaders(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(echo))
	defer srv.Close()
	e := New()
	h := []model.KV{
		{Name: "X-A", Value: "1", Enabled: true},
		{Name: "x-a", Value: "2", Enabled: true},
		{Name: "X-Off", Value: "1"},
		{Name: "Host", Value: "example.test", Enabled: true},
		{Name: "Content-Length", Value: "999", Enabled: true},
		{Name: "Accept", Value: "application/json", Enabled: true},
	}
	res, err := e.Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL, Headers: h}, defOpts)
	if err != nil {
		t.Fatal(err)
	}
	checks := map[string]string{
		"Echo-X-A": "1,2", "Echo-X-Off": "", "X-Host": "example.test",
		"Echo-Accept": "application/json", "Echo-User-Agent": "MinorREST/test", "Echo-Content-Length": "",
	}
	for k, want := range checks {
		if got := strings.Join(hdr(res, k), ","); got != want {
			t.Errorf("%s = %q, chci %q", k, got, want)
		}
	}
	// Vypnuté automatické hlavičky: Go nesmí doplnit vlastní User-Agent.
	res, _ = e.Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL, NoAuto: []string{"user-agent", "Accept"}}, defOpts)
	if len(hdr(res, "Echo-User-Agent")) != 0 || len(hdr(res, "Echo-Accept")) != 0 {
		t.Errorf("vypnuté auto hlavičky odeslány: %v", res.Headers)
	}
}

func TestBodies(t *testing.T) {
	var got *http.Request
	var gotBody []byte
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r
		gotBody, _ = io.ReadAll(r.Body)
	}))
	defer srv.Close()
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "žluťoučký.png"), []byte("PNG"), 0o644)

	tests := []struct {
		name   string
		body   model.Body
		header []model.KV
		check  func(t *testing.T)
		err    string
	}{
		{name: "json", body: model.Body{Type: model.BodyJSON, Raw: `{"a":1}`}, check: func(t *testing.T) {
			if got.Header.Get("Content-Type") != "application/json; charset=utf-8" || string(gotBody) != `{"a":1}` || got.ContentLength != 7 {
				t.Errorf("%v %q", got.Header, gotBody)
			}
		}},
		{name: "json s vlastním content-type", body: model.Body{Type: model.BodyJSON, Raw: `{}`}, header: []model.KV{{Name: "content-type", Value: "application/vnd.api+json", Enabled: true}}, check: func(t *testing.T) {
			if got.Header.Get("Content-Type") != "application/vnd.api+json" {
				t.Error(got.Header)
			}
		}},
		{name: "form v pořadí", body: model.Body{Type: model.BodyForm, Form: []model.KV{{Name: "z", Value: "a b&c", Enabled: true}, {Name: "off", Value: "x"}, {Name: "a", Value: "ř", Enabled: true}}}, check: func(t *testing.T) {
			if string(gotBody) != "z=a+b%26c&a=%C5%99" || got.Header.Get("Content-Type") != "application/x-www-form-urlencoded" {
				t.Errorf("%q", gotBody)
			}
		}},
		{name: "multipart", body: model.Body{Type: model.BodyMultipart, Multipart: []model.MultipartPart{
			{Name: "t", Kind: "text", Value: "hodnota", Enabled: true},
			{Name: "f", Kind: "file", Path: "žluťoučký.png", Enabled: true},
		}}, header: []model.KV{{Name: "Content-Type", Value: "multipart/form-data", Enabled: true}}, check: func(t *testing.T) {
			_, params, err := mime.ParseMediaType(got.Header.Get("Content-Type"))
			if err != nil || params["boundary"] == "" {
				t.Fatalf("boundary: %v %v", got.Header, err)
			}
			mr := multipart.NewReader(strings.NewReader(string(gotBody)), params["boundary"])
			p, _ := mr.NextPart()
			v, _ := io.ReadAll(p)
			if p.FormName() != "t" || string(v) != "hodnota" {
				t.Errorf("text část: %s %q", p.FormName(), v)
			}
			p, _ = mr.NextPart()
			v, _ = io.ReadAll(p)
			if p.FileName() != "žluťoučký.png" || p.Header.Get("Content-Type") != "image/png" || string(v) != "PNG" {
				t.Errorf("souborová část: %q %v %q", p.FileName(), p.Header, v)
			}
		}},
		{name: "binary", body: model.Body{Type: model.BodyBinary, BinaryPath: "žluťoučký.png"}, check: func(t *testing.T) {
			if string(gotBody) != "PNG" || got.Header.Get("Content-Type") != "image/png" || got.ContentLength != 3 {
				t.Errorf("%v %q", got.Header, gotBody)
			}
		}},
		{name: "chybějící soubor", body: model.Body{Type: model.BodyBinary, BinaryPath: "nic.bin"}, err: ErrFileNotFound},
		{name: "chybějící soubor v multipart", body: model.Body{Type: model.BodyMultipart, Multipart: []model.MultipartPart{{Name: "f", Kind: "file", Path: "nic", Enabled: true}}}, err: ErrFileNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := New().Do(context.Background(), "r", Request{Method: "POST", URL: srv.URL, Headers: tt.header, Body: tt.body, BaseDir: dir}, defOpts)
			if code(err) != tt.err {
				t.Fatalf("chyba %q, chci %q", code(err), tt.err)
			}
			if tt.check != nil {
				tt.check(t)
			}
		})
	}
}

func TestHTTPVersions(t *testing.T) {
	h2 := httptest.NewUnstartedServer(http.HandlerFunc(echo))
	h2.EnableHTTP2 = true
	h2.StartTLS()
	defer h2.Close()
	h1 := httptest.NewTLSServer(http.HandlerFunc(echo))
	defer h1.Close()
	plain := httptest.NewServer(http.HandlerFunc(echo))
	defer plain.Close()
	h2c := httptest.NewUnstartedServer(http.HandlerFunc(echo))
	h2c.Config.Protocols = new(http.Protocols)
	h2c.Config.Protocols.SetHTTP1(true)
	h2c.Config.Protocols.SetUnencryptedHTTP2(true)
	h2c.Start()
	defer h2c.Close()

	tests := []struct {
		url, ver, proto, err string
	}{
		{h2.URL, VersionAuto, "HTTP/2.0", ""},
		{h2.URL, VersionHTTP1, "HTTP/1.1", ""},
		{h2.URL, VersionHTTP2, "HTTP/2.0", ""},
		{h1.URL, VersionAuto, "HTTP/1.1", ""},
		{h1.URL, VersionHTTP2, "", ErrHTTP2Unsupported},
		{plain.URL, VersionAuto, "HTTP/1.1", ""},
		{h2c.URL, VersionHTTP2, "HTTP/2.0", ""},
		{plain.URL, VersionHTTP2, "", ErrHTTP2Unsupported},
	}
	for _, tt := range tests {
		t.Run(tt.url+" "+tt.ver, func(t *testing.T) {
			o := defOpts
			o.HTTPVersion, o.VerifyTLS = tt.ver, false
			res, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: tt.url}, o)
			if code(err) != tt.err {
				t.Fatalf("chyba %q, chci %q", code(err), tt.err)
			}
			if err == nil && (res.Proto != tt.proto || hdr(res, "X-Proto")[0] != tt.proto) {
				t.Errorf("proto %s / server %v, chci %s", res.Proto, hdr(res, "X-Proto"), tt.proto)
			}
		})
	}
}

func TestTLS(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(echo))
	defer srv.Close()
	_, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL}, defOpts)
	if code(err) != ErrTLSVerify {
		t.Errorf("ověření: %q", code(err))
	}
	o := defOpts
	o.VerifyTLS = false
	res, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL}, o)
	if err != nil || res.TLS == nil || res.TLS.Version == "" || res.TLS.Cipher == "" || res.TLS.NotAfter == "" {
		t.Errorf("%v %+v", err, res)
	}
}

func TestRedirects(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/r/{n}", func(w http.ResponseWriter, r *http.Request) {
		var n int
		fmt.Sscan(r.PathValue("n"), &n)
		if n == 0 {
			echo(w, r)
			return
		}
		http.Redirect(w, r, fmt.Sprintf("/r/%d", n-1), map[bool]int{true: 307, false: 302}[r.Method == "POST"])
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	tests := []struct {
		name            string
		follow          bool
		max, status, nr int
		err             string
	}{
		{"vypnuto", false, 10, 302, 0, ""},
		{"zapnuto", true, 10, 200, 3, ""},
		{"přesně limit", true, 3, 200, 3, ""},
		{"nad limit", true, 2, 0, 0, ErrRedirectLimit},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			o := defOpts
			o.FollowRedirects, o.MaxRedirects = tt.follow, tt.max
			res, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL + "/r/3"}, o)
			if code(err) != tt.err {
				t.Fatalf("chyba %q, chci %q", code(err), tt.err)
			}
			if err == nil && (res.Status != tt.status || len(res.Redirects) != tt.nr) {
				t.Errorf("status %d, skoků %d", res.Status, len(res.Redirects))
			}
		})
	}
	// 307 pošle tělo znovu.
	res, err := New().Do(context.Background(), "r", Request{Method: "POST", URL: srv.URL + "/r/2", Body: model.Body{Type: model.BodyText, Raw: "data"}}, defOpts)
	if err != nil || bodyStr(res) != "data" || res.Redirects[0].Status != 307 || res.Redirects[0].Location != "/r/1" {
		t.Errorf("307: %v %+v", err, res)
	}
}

func TestTimeoutCancel(t *testing.T) {
	started := make(chan struct{}, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started <- struct{}{}
		select {
		case <-r.Context().Done():
		case <-time.After(5 * time.Second):
		}
	}))
	defer srv.Close()
	o := defOpts
	o.Timeout = 50 * time.Millisecond
	if _, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL}, o); code(err) != ErrTimeout {
		t.Errorf("timeout: %q", code(err))
	}
	<-started

	e := New()
	go func() {
		<-started
		e.Cancel("run1")
	}()
	if _, err := e.Do(context.Background(), "run1", Request{Method: "GET", URL: srv.URL}, defOpts); code(err) != ErrCanceled {
		t.Errorf("cancel: %q", code(err))
	}
	if len(e.runs) != 0 {
		t.Error("run zůstal v mapě")
	}
}

func TestNetErrors(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	closed := "http://" + ln.Addr().String()
	ln.Close()
	tests := []struct{ url, err string }{
		{closed, ErrRefused},
		{"http://neexistuje.invalid", ErrDNS},
		{"ftp://example.com", ErrURLInvalid},
		{"/jen/cesta", ErrURLInvalid},
	}
	for _, tt := range tests {
		if _, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: tt.url}, defOpts); code(err) != tt.err {
			t.Errorf("%s: %q, chci %q", tt.url, code(err), tt.err)
		}
	}
	if _, err := New().Do(context.Background(), "r", Request{Method: "BAD METHOD", URL: "http://x.test"}, defOpts); code(err) != ErrMethodInvalid {
		t.Errorf("metoda: %q", code(err))
	}
}
