package httpclient

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net"
	"strings"
	"syscall"
)

// Kódy chyb odeslání (texty jsou v i18n frontendu).
const (
	ErrCanceled         = "CANCELED"
	ErrTimeout          = "NET_TIMEOUT"
	ErrDNS              = "NET_DNS"
	ErrRefused          = "NET_REFUSED"
	ErrNet              = "NET_ERROR"
	ErrTLSVerify        = "TLS_VERIFY"
	ErrTLS              = "TLS_ERROR"
	ErrHTTP2Unsupported = "HTTP2_UNSUPPORTED"
	ErrRedirectLimit    = "REDIRECT_LIMIT"
	ErrFileNotFound     = "FILE_NOT_FOUND"
	ErrURLInvalid       = "URL_INVALID"
	ErrMethodInvalid    = "METHOD_INVALID"
)

// Error je chyba odeslání s kódem pro UI a původním textem jako detailem.
type Error struct {
	Code   string `json:"code" yaml:"code"`
	Detail string `json:"detail,omitempty" yaml:"detail,omitempty"`
}

func (e *Error) Error() string {
	if e.Detail == "" {
		return e.Code
	}
	return e.Code + ": " + e.Detail
}

func newErr(code string, err error) *Error {
	d := ""
	if err != nil {
		d = err.Error()
	}
	return &Error{Code: code, Detail: d}
}

var (
	errCanceled = errors.New("canceled")
	errTimeout  = errors.New("timeout")
)

// classify převede chybu transportu na kód; ctx rozliší zrušení od timeoutu.
func classify(ctx context.Context, err error, http2Only bool) *Error {
	var ce *Error
	if errors.As(err, &ce) {
		return ce
	}
	switch context.Cause(ctx) {
	case errCanceled:
		return newErr(ErrCanceled, nil)
	case errTimeout:
		return newErr(ErrTimeout, err)
	}
	var dnsErr *net.DNSError
	var netErr net.Error
	var verr *tls.CertificateVerificationError
	var uaErr x509.UnknownAuthorityError
	var hErr x509.HostnameError
	var ciErr x509.CertificateInvalidError
	var alert tls.AlertError
	var rh tls.RecordHeaderError
	msg := err.Error()
	switch {
	case errors.As(err, &dnsErr):
		return newErr(ErrDNS, err)
	case errors.Is(err, syscall.ECONNREFUSED):
		return newErr(ErrRefused, err)
	case errors.As(err, &verr), errors.As(err, &uaErr), errors.As(err, &hErr), errors.As(err, &ciErr):
		return newErr(ErrTLSVerify, err)
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout():
		return newErr(ErrTimeout, err)
	case http2Only && isHTTP2Mismatch(msg):
		return newErr(ErrHTTP2Unsupported, err)
	case errors.As(err, &alert), errors.As(err, &rh), strings.Contains(msg, "tls:"):
		return newErr(ErrTLS, err)
	}
	return newErr(ErrNet, err)
}

// isHTTP2Mismatch pozná, že server s vynuceným HTTP/2 nemluví h2 (chybí ALPN, h2c na HTTP/1 serveru).
func isHTTP2Mismatch(msg string) bool {
	for _, s := range []string{"no application protocol", "looked like an HTTP/1.1 header"} {
		if strings.Contains(msg, s) {
			return true
		}
	}
	return false
}
