package settings

import "github.com/novami/minor-rest/internal/model"

// DefaultHTTP vrátí vestavěné výchozí HTTP nastavení (globální nastavení přibude v F11).
func DefaultHTTP() model.HTTPSettings {
	ver, yes, maxRedirects, timeout := "auto", true, 10, 30000
	return model.HTTPSettings{
		HTTPVersion:     &ver,
		FollowRedirects: &yes,
		MaxRedirects:    &maxRedirects,
		TimeoutMs:       &timeout,
		VerifyTLS:       &yes,
		CookieJar:       &yes,
	}
}
