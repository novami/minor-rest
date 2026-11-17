package httpclient

import (
	"bufio"
	"bytes"
	"compress/flate"
	"compress/gzip"
	"compress/zlib"
	"errors"
	"io"
	"mime"
	"os"
	"strings"
	"unicode/utf8"

	"github.com/andybalholm/brotli"
	"github.com/klauspost/compress/zstd"
	"golang.org/x/net/html/charset"
)

const (
	memLimit        = 10 << 20  // větší tělo jde do temp souboru
	DefaultMaxBody  = 100 << 20 // výchozí MaxBodyBytes
	sniffLen        = 4096
	sentPreviewSize = 64 << 10
)

// Body je tělo odpovědi (dekomprimované, v původním kódování znaků) v paměti nebo v temp souboru.
type Body struct {
	data []byte
	path string
	size int64
}

func (b *Body) Size() int64 { return b.size }

// Bytes vrátí celé tělo (u temp souboru ho načte).
func (b *Body) Bytes() ([]byte, error) {
	if b.path == "" {
		return b.data, nil
	}
	return os.ReadFile(b.path)
}

// Open otevře tělo ke čtení.
func (b *Body) Open() (io.ReadCloser, error) {
	if b.path == "" {
		return io.NopCloser(bytes.NewReader(b.data)), nil
	}
	return os.Open(b.path)
}

func (b *Body) remove() {
	if b != nil && b.path != "" {
		os.Remove(b.path)
	}
}

// sink drží data v paměti a po překročení memLimit přejde na temp soubor.
type sink struct {
	buf  bytes.Buffer
	f    *os.File
	size int64
}

func (s *sink) Write(p []byte) (int, error) {
	if s.f == nil && s.buf.Len()+len(p) > memLimit {
		f, err := os.CreateTemp("", "minorrest-body-*")
		if err != nil {
			return 0, err
		}
		s.f = f
		if _, err := f.Write(s.buf.Bytes()); err != nil {
			return 0, err
		}
		s.buf = bytes.Buffer{}
	}
	var n int
	var err error
	if s.f != nil {
		n, err = s.f.Write(p)
	} else {
		n, err = s.buf.Write(p)
	}
	s.size += int64(n)
	return n, err
}

func (s *sink) body() (*Body, error) {
	if s.f == nil {
		return &Body{data: s.buf.Bytes(), size: s.size}, nil
	}
	path := s.f.Name()
	if err := s.f.Close(); err != nil {
		os.Remove(path)
		return nil, err
	}
	return &Body{path: path, size: s.size}, nil
}

func (s *sink) discard() {
	if s.f != nil {
		s.f.Close()
		os.Remove(s.f.Name())
	}
}

type counter struct {
	r io.Reader
	n int64
}

func (c *counter) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}

// decoder obalí r dekodéry podle Content-Encoding (u více kódování v opačném pořadí).
// Neznámé kódování → bajty beze změny (ok = false).
func decoder(r io.Reader, contentEncoding string, closers *[]func()) (io.Reader, bool, error) {
	var encs []string
	for _, e := range strings.Split(contentEncoding, ",") {
		if e = strings.ToLower(strings.TrimSpace(e)); e != "" && e != "identity" {
			encs = append(encs, e)
		}
	}
	for _, e := range encs {
		switch e {
		case "gzip", "x-gzip", "deflate", "br", "zstd":
		default:
			return r, false, nil
		}
	}
	for i := len(encs) - 1; i >= 0; i-- {
		br := bufio.NewReader(r)
		head, _ := br.Peek(4)
		if len(head) == 0 { // prázdné tělo (HEAD, 204)
			return br, true, nil
		}
		var err error
		switch encs[i] {
		case "gzip", "x-gzip":
			r, err = gzip.NewReader(br)
		case "deflate": // správně zlib, některé servery posílají raw deflate
			if len(head) >= 2 && head[0]&0x0f == 8 && (uint16(head[0])<<8|uint16(head[1]))%31 == 0 {
				r, err = zlib.NewReader(br)
			} else {
				r = flate.NewReader(br)
			}
		case "br":
			r = brotli.NewReader(br)
		case "zstd":
			var d *zstd.Decoder
			if d, err = zstd.NewReader(br, zstd.WithDecoderConcurrency(1)); err == nil {
				r = d
				*closers = append(*closers, d.Close)
			}
		}
		if err != nil {
			return nil, false, err
		}
	}
	return r, len(encs) > 0, nil
}

// readBody přečte (a dekóduje) tělo do sinku, nejvýš maxBytes dekódovaných bajtů.
func readBody(r io.Reader, contentEncoding string, maxBytes int64) (body *Body, wire int64, truncated bool, err error) {
	c := &counter{r: r}
	var closers []func()
	defer func() {
		for _, f := range closers {
			f()
		}
	}()
	dec, _, err := decoder(c, contentEncoding, &closers)
	if err != nil {
		return nil, c.n, false, &Error{Code: ErrDecode, Detail: err.Error()}
	}
	s := &sink{}
	if _, err = io.CopyN(s, dec, maxBytes); err != nil && !errors.Is(err, io.EOF) {
		s.discard()
		if isDecodeErr(err) {
			return nil, c.n, false, &Error{Code: ErrDecode, Detail: err.Error()}
		}
		return nil, c.n, false, err
	}
	if err == nil { // limit vyčerpán – je ještě něco?
		var one [1]byte
		n, _ := dec.Read(one[:])
		truncated = n > 0
	}
	body, err = s.body()
	return body, c.n, truncated, err
}

func isDecodeErr(err error) bool {
	var ce flate.CorruptInputError
	return errors.Is(err, gzip.ErrChecksum) || errors.Is(err, gzip.ErrHeader) || errors.Is(err, zlib.ErrChecksum) ||
		errors.As(err, &ce) || strings.Contains(err.Error(), "brotli") || strings.Contains(err.Error(), "zstd")
}

var textTypes = []string{"text/", "json", "xml", "javascript", "ecmascript", "yaml", "csv", "graphql", "x-www-form-urlencoded", "html"}

func isTextType(mt string) bool {
	for _, t := range textTypes {
		if strings.Contains(mt, t) {
			return true
		}
	}
	return false
}

func isJSONType(mt string) bool { return strings.Contains(mt, "json") }

// sniff z Content-Type a začátku těla určí media type, charset a zda jde o binární obsah.
func sniff(contentType string, sample []byte) (mediaType, cs string, binary bool) {
	mt, params, _ := mime.ParseMediaType(contentType)
	mt = strings.ToLower(mt)
	if len(sample) == 0 {
		return mt, "", false
	}
	if !isTextType(mt) && !looksText(sample) {
		return mt, "", true
	}
	if isJSONType(mt) && params["charset"] == "" {
		return mt, "utf-8", false
	}
	_, name, certain := charset.DetermineEncoding(sample, contentType)
	if !certain && name == "windows-1252" && validUTF8(sample, len(sample) == sniffLen) {
		name = "utf-8" // výchozí odhad knihovny; ASCII a platné UTF-8 bereme jako UTF-8
	}
	return mt, name, false
}

// looksText: validní UTF-8 bez řídicích znaků (kromě běžných bílých).
func looksText(b []byte) bool {
	for len(b) > 0 {
		r, n := utf8.DecodeRune(b)
		if r == utf8.RuneError && n == 1 && len(b) >= utf8.UTFMax {
			return false
		}
		if r < 0x20 && r != '\t' && r != '\n' && r != '\r' && r != '\f' {
			return false
		}
		b = b[n:]
	}
	return true
}

// validUTF8; cut = vzorek je useknutý, neúplný znak na konci nevadí.
func validUTF8(b []byte, cut bool) bool {
	if cut {
		for i := len(b) - 1; i >= 0 && i > len(b)-utf8.UTFMax; i-- {
			if utf8.RuneStart(b[i]) {
				if !utf8.FullRune(b[i:]) {
					b = b[:i]
				}
				break
			}
		}
	}
	return utf8.Valid(b)
}

// ToUTF8 převede text v kódování cs do UTF-8 (pro zobrazení); neplatné sekvence nahradí.
func ToUTF8(b []byte, cs string) string {
	if e, name := charset.Lookup(cs); e != nil && name != "utf-8" {
		if out, err := e.NewDecoder().Bytes(b); err == nil {
			return string(out)
		}
	}
	return strings.ToValidUTF8(string(bytes.TrimPrefix(b, []byte("\xef\xbb\xbf"))), "�")
}

func preview(b []byte) string {
	if len(b) > sentPreviewSize {
		b = b[:sentPreviewSize]
	}
	return strings.ToValidUTF8(string(b), "�")
}
