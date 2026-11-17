package httpclient

import (
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/andybalholm/brotli"
	"github.com/klauspost/compress/zstd"
	"github.com/novami/minor-rest/internal/model"
	"golang.org/x/text/encoding/charmap"
)

const plain = "Příliš žluťoučký kůň úpěl ďábelské ódy. Příliš žluťoučký kůň úpěl ďábelské ódy."

func compress(enc string) []byte {
	var b bytes.Buffer
	var w io.WriteCloser
	switch enc {
	case "gzip":
		w = gzip.NewWriter(&b)
	case "deflate":
		w = zlib.NewWriter(&b)
	case "deflate-raw":
		w, _ = flate.NewWriter(&b, 5)
	case "br":
		w = brotli.NewWriter(&b)
	case "zstd":
		w, _ = zstd.NewWriter(&b)
	default:
		return []byte(plain)
	}
	io.WriteString(w, plain)
	w.Close()
	return b.Bytes()
}

func TestCompression(t *testing.T) {
	var gotAE string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAE = r.Header.Get("Accept-Encoding")
		enc := r.URL.Query().Get("e")
		w.Header().Set("Content-Encoding", strings.TrimSuffix(enc, "-raw"))
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(compress(enc))
	}))
	defer srv.Close()
	for _, enc := range []string{"gzip", "deflate", "deflate-raw", "br", "zstd", "unknown"} {
		t.Run(enc, func(t *testing.T) {
			res, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL + "?e=" + enc}, defOpts)
			if err != nil {
				t.Fatal(err)
			}
			wire := int64(len(compress(enc)))
			if bodyStr(res) != plain && enc != "unknown" || res.Sizes.BodyWire != wire || res.Sizes.BodyDecoded != res.Body.Size() {
				t.Errorf("tělo %q, wire %d (chci %d), decoded %d", bodyStr(res), res.Sizes.BodyWire, wire, res.Sizes.BodyDecoded)
			}
			if enc != "unknown" && res.Sizes.BodyDecoded != int64(len(plain)) {
				t.Errorf("decoded %d", res.Sizes.BodyDecoded)
			}
		})
	}
	if gotAE != "gzip, deflate, br, zstd" {
		t.Errorf("Accept-Encoding %q", gotAE)
	}
	// Poškozené tělo → DECODE_ERROR.
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Encoding", "gzip")
		w.Write([]byte("tohle není gzip"))
	}))
	defer bad.Close()
	if _, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: bad.URL}, defOpts); code(err) != ErrDecode {
		t.Errorf("poškozený gzip: %q", code(err))
	}
}

func TestCharsetAndBinary(t *testing.T) {
	cp1250, _ := charmap.Windows1250.NewEncoder().String(plain)
	tests := []struct {
		name, ct, body, mt, cs string
		binary                 bool
	}{
		{"windows-1250", "text/plain; charset=windows-1250", cp1250, "text/plain", "windows-1250", false},
		{"iso-8859-2", "text/html; charset=ISO-8859-2", "<p>x</p>", "text/html", "iso-8859-2", false},
		{"html meta", "text/html", `<meta charset="windows-1250"><p>` + cp1250, "text/html", "windows-1250", false},
		{"json bez charsetu", "application/json", `{"a":"ž"}`, "application/json", "utf-8", false},
		{"ascii text", "text/plain", "abc", "text/plain", "utf-8", false},
		{"bez content-type, text", "", "ahoj ž", "", "utf-8", false},
		{"png", "image/png", "\x89PNG\r\n\x1a\n\x00\x00", "image/png", "", true},
		{"bez content-type, binární", "", "\x00\x01\x02", "", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header()["Content-Type"] = []string{tt.ct}
				io.WriteString(w, tt.body)
			}))
			defer srv.Close()
			res, err := New().Do(context.Background(), "r", Request{Method: "GET", URL: srv.URL}, defOpts)
			if err != nil {
				t.Fatal(err)
			}
			if res.ContentType != tt.mt || res.Charset != tt.cs || res.IsBinary != tt.binary {
				t.Errorf("ct %q cs %q bin %v", res.ContentType, res.Charset, res.IsBinary)
			}
		})
	}
	b, _ := charmap.Windows1250.NewEncoder().Bytes([]byte(plain))
	if got := ToUTF8(b, "windows-1250"); got != plain {
		t.Errorf("ToUTF8: %q", got)
	}
	if got := ToUTF8([]byte("\xef\xbb\xbfok\xff"), "utf-8"); got != "ok�" {
		t.Errorf("ToUTF8 utf-8: %q", got)
	}
}

func TestSentTimingSizes(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(echo))
	defer srv.Close()
	url := strings.Replace(srv.URL, "127.0.0.1", "localhost", 1) // projde DNS
	res, err := New().Do(context.Background(), "r", Request{Method: "POST", URL: url + "/a?b=1",
		Headers: []model.KV{{Name: "X-Z", Value: "1", Enabled: true}}, Body: model.Body{Type: model.BodyJSON, Raw: `{"a":1}`}}, defOpts)
	if err != nil {
		t.Fatal(err)
	}
	s := res.Sent
	if s.Method != "POST" || !strings.HasSuffix(s.URL, "/a?b=1") || s.BodyPreview != `{"a":1}` || s.BodySize != 7 {
		t.Errorf("sent %+v", s)
	}
	var names []string
	want := int64(len("POST /a?b=1 HTTP/1.1\r\n") + 2)
	for _, h := range s.Headers {
		names = append(names, h.Name)
		want += lineSize(h.Name, h.Value)
	}
	if got := strings.Join(names, ","); !strings.HasPrefix(got, "Host,User-Agent,Content-Length,") || !strings.Contains(got, "X-Z") {
		t.Errorf("odeslané hlavičky %s", got)
	}
	if res.Sizes.ReqHeaders != want || res.Sizes.ReqBody != 7 || res.Sizes.Headers <= int64(len("HTTP/1.1 200 OK\r\n")) {
		t.Errorf("sizes %+v (reqHeaders chci %d)", res.Sizes, want)
	}
	if res.RemoteAddr == "" || res.LocalAddr == "" || len(res.ResolvedAddrs) == 0 {
		t.Errorf("adresy %q %q %v", res.RemoteAddr, res.LocalAddr, res.ResolvedAddrs)
	}
	tm := res.Timing
	if tm.TotalMs <= 0 || tm.TTFBMs <= 0 || tm.ConnectMs <= 0 || tm.TotalMs < tm.TTFBMs {
		t.Errorf("timing %+v", tm)
	}

	// HTTP/2: pseudo-hlavičky, bez request line.
	h2 := httptest.NewUnstartedServer(http.HandlerFunc(echo))
	h2.EnableHTTP2 = true
	h2.StartTLS()
	defer h2.Close()
	o := defOpts
	o.VerifyTLS = false
	res, err = New().Do(context.Background(), "r", Request{Method: "GET", URL: h2.URL}, o)
	if err != nil || len(res.Sent.Headers) == 0 || res.Sent.Headers[0].Name != ":authority" && res.Sent.Headers[0].Name != ":method" {
		t.Errorf("h2 sent: %v %+v", err, res.Sent.Headers)
	}
	if res.Timing.TLSMs <= 0 {
		t.Errorf("h2 timing %+v", res.Timing)
	}
}

func TestBodyLimits(t *testing.T) {
	big := bytes.Repeat([]byte("a"), memLimit+100)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(big) }))
	defer srv.Close()

	e := New()
	res, err := e.Do(context.Background(), "big", Request{Method: "GET", URL: srv.URL}, defOpts)
	if err != nil || res.Body.path == "" || res.Body.Size() != int64(len(big)) || res.Truncated {
		t.Fatalf("temp soubor: %v %+v", err, res.Body)
	}
	if b, _ := res.Body.Bytes(); !bytes.Equal(b, big) {
		t.Error("obsah temp souboru")
	}
	o := defOpts
	o.MaxBodyBytes = 5
	res, err = e.Do(context.Background(), "small", Request{Method: "GET", URL: srv.URL}, o)
	if err != nil || bodyStr(res) != "aaaaa" || !res.Truncated {
		t.Errorf("oříznutí: %v %q %v", err, bodyStr(res), res.Truncated)
	}

	// LRU: po 20 dalších výsledcích je první vyřazen a jeho temp soubor smazán.
	path := ""
	if r, ok := e.Get("big"); ok {
		path = r.Body.path
	}
	for i := range keepResults {
		e.keep(fmt.Sprint(i), &Result{Body: &Body{}})
	}
	if _, ok := e.Get("big"); ok {
		t.Error("big nebyl vyřazen")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Errorf("temp soubor zůstal: %v", err)
	}
	e.Close()
	if _, ok := e.Get("0"); ok {
		t.Error("Close nevyprázdnil výsledky")
	}
}
