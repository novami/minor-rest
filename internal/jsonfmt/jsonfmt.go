// Package jsonfmt formátuje JSON tělo requestu se zachováním {{proměnných}}.
package jsonfmt

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

const ErrJSONInvalid = "JSON_INVALID" // detail: řádek + popis

var varRe = regexp.MustCompile(`\\?\{\{[^{}]*\}\}`)

// Format odsadí JSON 2 mezerami (json.Indent – čísla ani pořadí klíčů se nemění).
// Proměnné mimo řetězce ({"id": {{id}}}) se dočasně nahradí řetězcem, uvnitř řetězců
// textovým zástupcem, a po formátování se vrátí.
func Format(text string) (string, error) {
	var vars []string
	var quoted []bool // zástupce mimo řetězec = vložený i s uvozovkami
	var b strings.Builder
	last := 0
	var st strState
	// I escape `\{{…}}` jde přes zástupce – v JSON řetězci by `\{` bylo neplatné.
	for _, m := range varRe.FindAllStringIndex(text, -1) {
		st.scan(text[last:m[0]])
		tok := fmt.Sprintf("__mrvar_%d__", len(vars))
		vars = append(vars, text[m[0]:m[1]])
		b.WriteString(text[last:m[0]])
		q := !st.in
		quoted = append(quoted, q)
		if q {
			tok = `"` + tok + `"`
		}
		b.WriteString(tok)
		last = m[1]
	}
	b.WriteString(text[last:])
	src := b.String()

	var out bytes.Buffer
	if err := json.Indent(&out, []byte(src), "", "  "); err != nil {
		return "", fmt.Errorf("%s: %s", ErrJSONInvalid, describe(src, err))
	}
	res := out.String()
	for i := len(vars) - 1; i >= 0; i-- { // od konce, aby __mrvar_1__ nezasáhl __mrvar_10__
		tok := fmt.Sprintf("__mrvar_%d__", i)
		if quoted[i] {
			tok = `"` + tok + `"`
		}
		res = strings.Replace(res, tok, vars[i], 1)
	}
	return res, nil
}

// strState sleduje, zda je čtení uvnitř JSON řetězce.
type strState struct{ in, esc bool }

func (s *strState) scan(chunk string) {
	for i := 0; i < len(chunk); i++ {
		c := chunk[i]
		switch {
		case s.esc:
			s.esc = false
		case s.in && c == '\\':
			s.esc = true
		case c == '"':
			s.in = !s.in
		}
	}
}

func describe(src string, err error) string {
	var se *json.SyntaxError
	if !errors.As(err, &se) {
		return err.Error()
	}
	off := int(se.Offset)
	if off > len(src) {
		off = len(src)
	}
	// Sloupec by kvůli zástupcům neseděl, řádek ano.
	return fmt.Sprintf("%d: %s", strings.Count(src[:off], "\n")+1, se.Error())
}
