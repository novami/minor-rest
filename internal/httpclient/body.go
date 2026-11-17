package httpclient

import (
	"bytes"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/textproto"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/novami/minor-rest/internal/model"
)

// payload je připravené tělo requestu.
type payload struct {
	contentType string // automatický Content-Type ("" = žádný)
	size        int64
	open        func() (io.ReadCloser, error) // nil = bez těla; volá se znovu při redirectu 307/308
}

var rawTypes = map[string]string{
	model.BodyJSON: "application/json; charset=utf-8",
	model.BodyXML:  "application/xml; charset=utf-8",
	model.BodyText: "text/plain; charset=utf-8",
	model.BodyHTML: "text/html; charset=utf-8",
}

func bytesPayload(b []byte, ct string) payload {
	return payload{contentType: ct, size: int64(len(b)), open: func() (io.ReadCloser, error) {
		return io.NopCloser(bytes.NewReader(b)), nil
	}}
}

// buildBody sestaví tělo; relativní cesty souborů se berou vůči baseDir (kořen projektu).
func buildBody(b model.Body, baseDir string) (payload, error) {
	if ct, ok := rawTypes[b.Type]; ok {
		return bytesPayload([]byte(b.Raw), ct), nil
	}
	switch b.Type {
	case model.BodyForm:
		return bytesPayload([]byte(encodeForm(b.Form)), "application/x-www-form-urlencoded"), nil
	case model.BodyMultipart:
		return buildMultipart(b.Multipart, baseDir)
	case model.BodyBinary:
		if b.BinaryPath == "" {
			return payload{}, nil
		}
		p := absPath(b.BinaryPath, baseDir)
		st, err := os.Stat(p)
		if err != nil || st.IsDir() {
			return payload{}, &Error{Code: ErrFileNotFound, Detail: b.BinaryPath}
		}
		return payload{contentType: typeByExt(p), size: st.Size(), open: func() (io.ReadCloser, error) {
			f, err := os.Open(p)
			if err != nil {
				return nil, &Error{Code: ErrFileNotFound, Detail: b.BinaryPath}
			}
			return f, nil
		}}, nil
	}
	return payload{}, nil
}

// encodeForm zakóduje zapnuté řádky v zadaném pořadí.
func encodeForm(rows []model.KV) string {
	var sb strings.Builder
	for _, r := range rows {
		if !r.Enabled || r.Name == "" {
			continue
		}
		if sb.Len() > 0 {
			sb.WriteByte('&')
		}
		sb.WriteString(url.QueryEscape(r.Name))
		sb.WriteByte('=')
		sb.WriteString(url.QueryEscape(r.Value))
	}
	return sb.String()
}

// buildMultipart sestaví multipart do paměti (známá délka, opakovatelné při redirectu).
func buildMultipart(parts []model.MultipartPart, baseDir string) (payload, error) {
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	for _, p := range parts {
		if !p.Enabled || p.Name == "" {
			continue
		}
		h := textproto.MIMEHeader{}
		if p.Kind == "file" {
			fp := absPath(p.Path, baseDir)
			data, err := os.ReadFile(fp)
			if p.Path == "" || err != nil {
				return payload{}, &Error{Code: ErrFileNotFound, Detail: p.Path}
			}
			h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, quoteEscape(p.Name), quoteEscape(filepath.Base(fp))))
			h.Set("Content-Type", or(p.ContentType, typeByExt(fp)))
			pw, _ := w.CreatePart(h)
			pw.Write(data)
			continue
		}
		h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"`, quoteEscape(p.Name)))
		if p.ContentType != "" {
			h.Set("Content-Type", p.ContentType)
		}
		pw, _ := w.CreatePart(h)
		io.WriteString(pw, p.Value)
	}
	w.Close()
	pl := bytesPayload(buf.Bytes(), w.FormDataContentType())
	return pl, nil
}

var quoteEscaper = strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\r", "%0D", "\n", "%0A")

func quoteEscape(s string) string { return quoteEscaper.Replace(s) }

func absPath(p, baseDir string) string {
	if filepath.IsAbs(p) || baseDir == "" {
		return p
	}
	return filepath.Join(baseDir, filepath.FromSlash(p))
}

func typeByExt(p string) string {
	if t := mime.TypeByExtension(filepath.Ext(p)); t != "" {
		return t
	}
	return "application/octet-stream"
}

func or(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
