package vars

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/novami/minor-rest/internal/model"
)

// Kódy chyb sestavení URL.
const (
	ErrURLInvalid = "URL_INVALID" // výsledná URL nejde rozparsovat nebo nemá host
	// ErrHostUnresolved – host obsahuje nevyhodnocenou proměnnou (typicky nevybrané prostředí);
	// detail = názvy proměnných oddělené čárkou.
	ErrHostUnresolved = "VAR_UNRESOLVED_HOST"
)

// EncodeQueryComponent percent-enkóduje název/hodnotu query parametru (UTF-8, mezera = %20).
// Platné sekvence %XX zachová; znaky s významem v query (& = + #) enkóduje.
func EncodeQueryComponent(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '%' && i+2 < len(s) && isHex(s[i+1]) && isHex(s[i+2]):
			b.WriteString(s[i : i+3])
			i += 2
		case keepInQuery(c):
			b.WriteByte(c)
		default:
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&15])
		}
	}
	return b.String()
}

// EncodeQuery sestaví query string ze zapnutých parametrů (řádky bez názvu vynechá;
// prázdná hodnota → `name=`, s Bare jen `name`).
func EncodeQuery(params []model.KV) string {
	var parts []string
	for _, p := range params {
		if !p.Enabled || p.Name == "" {
			continue
		}
		part := EncodeQueryComponent(p.Name)
		if p.Value != "" || !p.Bare {
			part += "=" + EncodeQueryComponent(p.Value)
		}
		parts = append(parts, part)
	}
	return strings.Join(parts, "&")
}

// BuildURL sestaví URL pro odeslání: proměnné v URL → `:param` v cestě → doplnění
// `http://` → připojení zapnutých query parametrů. Nevyhodnocené proměnné hlásí r.Unresolved().
func BuildURL(raw string, path []model.PathParam, query []model.KV, r *Resolver) (string, error) {
	u, unresolved, err := r.Resolve(strings.TrimSpace(raw))
	if err != nil {
		return "", err
	}
	if !strings.Contains(u, "://") {
		u = "http://" + u
	}
	if u, err = replacePathParams(u, path, r); err != nil {
		return "", err
	}
	resolved := make([]model.KV, 0, len(query))
	for _, q := range query {
		if !q.Enabled {
			continue
		}
		if q.Name, _, err = r.Resolve(q.Name); err != nil {
			return "", err
		}
		if q.Value, _, err = r.Resolve(q.Value); err != nil {
			return "", err
		}
		resolved = append(resolved, q)
	}
	if qs := EncodeQuery(resolved); qs != "" {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		u += sep + qs
	}
	parsed, err := url.Parse(u)
	if err == nil && parsed.Host == "" {
		err = fmt.Errorf("missing host")
	}
	if err != nil {
		if len(unresolved) > 0 && strings.Contains(hostPart(u), "{{") {
			return "", fmt.Errorf("%s: %s", ErrHostUnresolved, strings.Join(unresolved, ", "))
		}
		return "", fmt.Errorf("%s: %w", ErrURLInvalid, err)
	}
	return u, nil
}

// hostPart vrátí část URL mezi `://` a první `/`, `?` nebo `#`.
func hostPart(u string) string {
	if i := strings.Index(u, "://"); i >= 0 {
		u = u[i+3:]
	}
	if i := strings.IndexAny(u, "/?#"); i >= 0 {
		u = u[:i]
	}
	return u
}

// replacePathParams nahradí segmenty cesty `:nazev` hodnotou (url.PathEscape).
// Port v hostu se nebere jako parametr; segment bez řádku v path zůstane beze změny.
func replacePathParams(u string, params []model.PathParam, r *Resolver) (string, error) {
	if len(params) == 0 {
		return u, nil
	}
	schemeEnd := strings.Index(u, "://") + 3
	slash := strings.IndexByte(u[schemeEnd:], '/')
	if slash < 0 {
		return u, nil
	}
	pathStart := schemeEnd + slash
	pathEnd := len(u)
	if i := strings.IndexAny(u[pathStart:], "?#"); i >= 0 {
		pathEnd = pathStart + i
	}
	values := map[string]string{}
	for _, p := range params {
		v, _, err := r.Resolve(p.Value)
		if err != nil {
			return "", err
		}
		values[p.Name] = v
	}
	segs := strings.Split(u[pathStart:pathEnd], "/")
	for i, s := range segs {
		if len(s) < 2 || s[0] != ':' {
			continue
		}
		n := 1
		for n < len(s) && isNameChar(s[n]) {
			n++
		}
		if v, ok := values[s[1:n]]; ok {
			segs[i] = url.PathEscape(v) + s[n:]
		}
	}
	return u[:pathStart] + strings.Join(segs, "/") + u[pathEnd:], nil
}

func isHex(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
}

func isNameChar(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-'
}

// keepInQuery: unreserved + sub-delims a `:@/?` bez `& = + #`.
func keepInQuery(c byte) bool {
	if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' {
		return true
	}
	return strings.IndexByte("-._~!$'()*,;:@/?", c) >= 0
}
