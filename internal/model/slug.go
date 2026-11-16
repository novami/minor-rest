package model

import (
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

const (
	slugMaxLen   = 60
	slugFallback = "polozka"
)

// Nerozložitelné znaky (NFD je nerozloží na základ + diakritiku).
var slugMap = map[rune]string{
	'ł': "l", 'Ł': "l", 'đ': "d", 'Đ': "d", 'ß': "ss",
	'ø': "o", 'Ø': "o", 'æ': "ae", 'Æ': "ae", 'œ': "oe", 'Œ': "oe",
}

// Slugify převede název na ASCII slug: `Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`.
// Prázdný výsledek → `polozka`.
func Slugify(name string) string {
	var b strings.Builder
	dash := false
	for _, r := range norm.NFD.String(norm.NFC.String(name)) {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		s, ok := slugMap[r]
		if !ok {
			s = string(unicode.ToLower(r))
		}
		for _, c := range s {
			if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
				if dash && b.Len() > 0 {
					b.WriteByte('-')
				}
				dash = false
				b.WriteRune(c)
			} else {
				dash = true
			}
		}
	}
	return trimSlug(b.String(), slugMaxLen)
}

// UniqueSlug vrátí slug, který (bez ohledu na velikost písmen) není v taken:
// `slug`, `slug-2`, `slug-3`… Celková délka nepřekročí 60 znaků.
func UniqueSlug(slug string, taken func(string) bool) string {
	if slug == "" {
		slug = slugFallback
	}
	if !taken(strings.ToLower(slug)) {
		return slug
	}
	for n := 2; ; n++ {
		suffix := "-" + strconv.Itoa(n)
		cand := trimSlug(slug, slugMaxLen-len(suffix)) + suffix
		if !taken(strings.ToLower(cand)) {
			return cand
		}
	}
}

func trimSlug(s string, max int) string {
	if len(s) > max {
		s = s[:max]
	}
	s = strings.Trim(s, "-")
	if s == "" {
		return slugFallback
	}
	return s
}
