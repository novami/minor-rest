// Package model obsahuje datové typy projektu, složek, requestů a prostředí
// (formát na disku i DTO pro frontend).
package model

import "github.com/oklog/ulid/v2"

// FormatVersion je nejvyšší verze formátu projektu, kterou aplikace zná.
const FormatVersion = 1

// Názvy souborů v projektu.
const (
	ProjectFile    = "minorrest.yaml"
	FolderFile     = "_folder.yaml"
	RequestSuffix  = ".req.yaml"
	EnvironmentDir = "environments"
	ResponsesDir   = ".responses"
)

// HTTP metody.
const (
	MethodGet     = "GET"
	MethodPost    = "POST"
	MethodPut     = "PUT"
	MethodPatch   = "PATCH"
	MethodDelete  = "DELETE"
	MethodHead    = "HEAD"
	MethodOptions = "OPTIONS"
)

// Typy těla requestu.
const (
	BodyNone      = "none"
	BodyJSON      = "json"
	BodyXML       = "xml"
	BodyText      = "text"
	BodyHTML      = "html"
	BodyForm      = "form-urlencoded"
	BodyMultipart = "multipart"
	BodyBinary    = "binary"
)

// Typy autorizace.
const (
	AuthInherit = "inherit"
	AuthNone    = "none"
	AuthBasic   = "basic"
	AuthBearer  = "bearer"
	AuthAPIKey  = "apikey"
	AuthOAuth2  = "oauth2"
)

// KV je řádek hlavičky, query parametru nebo formuláře.
type KV struct {
	Name        string `json:"name" yaml:"name"`
	Value       string `json:"value" yaml:"value"`
	Enabled     bool   `json:"enabled" yaml:"enabled"`
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
	// Bare: jen query – při prázdné hodnotě poslat `?name` místo `?name=` (uživatel tak napsal URL).
	Bare bool `json:"bare,omitempty" yaml:"bare,omitempty"`
}

// UnmarshalYAML: chybějící `enabled` znamená zapnuto.
func (k *KV) UnmarshalYAML(unmarshal func(any) error) error {
	type raw KV
	r := raw{Enabled: true}
	if err := unmarshal(&r); err != nil {
		return err
	}
	*k = KV(r)
	return nil
}

// PathParam je hodnota pro `:nazev` v cestě URL.
type PathParam struct {
	Name        string `json:"name" yaml:"name"`
	Value       string `json:"value" yaml:"value"`
	Description string `json:"description,omitempty" yaml:"description,omitempty"`
}

// Var je proměnná (projekt, složka, request, prostředí, globální).
// U `Secret` je hodnota v Keychain a do YAML se nezapisuje.
type Var struct {
	Name    string `json:"name" yaml:"name"`
	Value   string `json:"value,omitempty" yaml:"value,omitempty"`
	Secret  bool   `json:"secret,omitempty" yaml:"secret,omitempty"`
	Enabled bool   `json:"enabled" yaml:"enabled"`
}

// UnmarshalYAML: chybějící `enabled` znamená zapnuto.
func (v *Var) UnmarshalYAML(unmarshal func(any) error) error {
	type raw Var
	r := raw{Enabled: true}
	if err := unmarshal(&r); err != nil {
		return err
	}
	*v = Var(r)
	return nil
}

// HTTPSettings jsou dědičná nastavení odeslání; nil = zděděno.
type HTTPSettings struct {
	HTTPVersion     *string `json:"httpVersion,omitempty" yaml:"httpVersion,omitempty"` // auto | http1 | http2
	FollowRedirects *bool   `json:"followRedirects,omitempty" yaml:"followRedirects,omitempty"`
	MaxRedirects    *int    `json:"maxRedirects,omitempty" yaml:"maxRedirects,omitempty"`
	TimeoutMs       *int    `json:"timeoutMs,omitempty" yaml:"timeoutMs,omitempty"`
	VerifyTLS       *bool   `json:"verifyTls,omitempty" yaml:"verifyTls,omitempty"`
	CookieJar       *bool   `json:"cookieJar,omitempty" yaml:"cookieJar,omitempty"`
}

// Auth je konfigurace autorizace; vyplněný je blok odpovídající Type.
type Auth struct {
	Type   string      `json:"type" yaml:"type"`
	Basic  *BasicAuth  `json:"basic,omitempty" yaml:"basic,omitempty"`
	Bearer *BearerAuth `json:"bearer,omitempty" yaml:"bearer,omitempty"`
	APIKey *APIKeyAuth `json:"apikey,omitempty" yaml:"apikey,omitempty"`
	OAuth2 *OAuth2Auth `json:"oauth2,omitempty" yaml:"oauth2,omitempty"`
}

type BasicAuth struct {
	Username string `json:"username" yaml:"username"`
	Password string `json:"password" yaml:"password"`
}

type BearerAuth struct {
	Token  string `json:"token" yaml:"token"`
	Prefix string `json:"prefix" yaml:"prefix"`
}

type APIKeyAuth struct {
	Key   string `json:"key" yaml:"key"`
	Value string `json:"value" yaml:"value"`
	In    string `json:"in" yaml:"in"` // header | query
}

type OAuth2Auth struct {
	GrantType      string `json:"grantType" yaml:"grantType"` // client_credentials | authorization_code | password
	AuthURL        string `json:"authUrl" yaml:"authUrl"`
	TokenURL       string `json:"tokenUrl" yaml:"tokenUrl"`
	ClientID       string `json:"clientId" yaml:"clientId"`
	ClientSecret   string `json:"clientSecret" yaml:"clientSecret"`
	Scope          string `json:"scope" yaml:"scope"`
	UsePKCE        bool   `json:"usePkce" yaml:"usePkce"`
	RedirectPort   int    `json:"redirectPort" yaml:"redirectPort"`
	Username       string `json:"username" yaml:"username"`
	Password       string `json:"password" yaml:"password"`
	ClientAuth     string `json:"clientAuth" yaml:"clientAuth"`         // header | body
	TokenPlacement string `json:"tokenPlacement" yaml:"tokenPlacement"` // header | query
	HeaderPrefix   string `json:"headerPrefix" yaml:"headerPrefix"`
	AutoRefresh    bool   `json:"autoRefresh" yaml:"autoRefresh"`
}

// Params jsou query a path parametry requestu. Query je zdroj pravdy (URL je bez query).
type Params struct {
	Query []KV        `json:"query,omitempty" yaml:"query,omitempty"`
	Path  []PathParam `json:"path,omitempty" yaml:"path,omitempty"`
}

// MultipartPart je jedna část multipart těla.
type MultipartPart struct {
	Name        string `json:"name" yaml:"name"`
	Kind        string `json:"kind" yaml:"kind"` // text | file
	Value       string `json:"value,omitempty" yaml:"value,omitempty"`
	Path        string `json:"path,omitempty" yaml:"path,omitempty"`
	ContentType string `json:"contentType,omitempty" yaml:"contentType,omitempty"`
	Enabled     bool   `json:"enabled" yaml:"enabled"`
}

// UnmarshalYAML: chybějící `enabled` znamená zapnuto.
func (m *MultipartPart) UnmarshalYAML(unmarshal func(any) error) error {
	type raw MultipartPart
	r := raw{Enabled: true}
	if err := unmarshal(&r); err != nil {
		return err
	}
	*m = MultipartPart(r)
	return nil
}

// Body je tělo requestu.
type Body struct {
	Type       string          `json:"type" yaml:"type"`
	Raw        string          `json:"raw,omitempty" yaml:"raw,omitempty"`
	Form       []KV            `json:"form,omitempty" yaml:"form,omitempty"`
	Multipart  []MultipartPart `json:"multipart,omitempty" yaml:"multipart,omitempty"`
	BinaryPath string          `json:"binaryPath,omitempty" yaml:"binaryPath,omitempty"`
}

// Extract nastaví po odpovědi runtime proměnnou.
type Extract struct {
	Name    string `json:"name" yaml:"name"`
	From    string `json:"from" yaml:"from"` // body (JSONPath) | header (název)
	Path    string `json:"path" yaml:"path"`
	Enabled bool   `json:"enabled" yaml:"enabled"`
}

// UnmarshalYAML: chybějící `enabled` znamená zapnuto.
func (e *Extract) UnmarshalYAML(unmarshal func(any) error) error {
	type raw Extract
	r := raw{Enabled: true}
	if err := unmarshal(&r); err != nil {
		return err
	}
	*e = Extract(r)
	return nil
}

// Request je obsah souboru `*.req.yaml`.
type Request struct {
	ID       string       `json:"id" yaml:"id"`
	Name     string       `json:"name" yaml:"name"`
	Seq      int          `json:"seq" yaml:"seq"`
	Method   string       `json:"method" yaml:"method"`
	URL      string       `json:"url" yaml:"url"`
	Params   Params       `json:"params" yaml:"params,omitempty"`
	Headers  []KV         `json:"headers,omitempty" yaml:"headers,omitempty"`
	Auth     Auth         `json:"auth" yaml:"auth"`
	Body     Body         `json:"body" yaml:"body"`
	Vars     []Var        `json:"vars,omitempty" yaml:"vars,omitempty"`
	Extract  []Extract    `json:"extract,omitempty" yaml:"extract,omitempty"`
	Settings HTTPSettings `json:"settings" yaml:"settings,omitempty"`
	Docs     string       `json:"docs,omitempty" yaml:"docs,omitempty"`
}

// NewRequest vrátí request s výchozími hodnotami.
func NewRequest(id, name string) Request {
	return Request{
		ID:     id,
		Name:   name,
		Method: MethodGet,
		Auth:   Auth{Type: AuthInherit},
		Body:   Body{Type: BodyNone},
	}
}

// FolderConfig je obsah `_folder.yaml`.
type FolderConfig struct {
	Name    string `json:"name" yaml:"name"`
	Seq     int    `json:"seq" yaml:"seq"`
	Vars    []Var  `json:"vars,omitempty" yaml:"vars,omitempty"`
	Headers []KV   `json:"headers,omitempty" yaml:"headers,omitempty"`
	Auth    Auth   `json:"auth" yaml:"auth"`
}

// ProjectConfig je obsah `minorrest.yaml`.
type ProjectConfig struct {
	FormatVersion        int          `json:"formatVersion" yaml:"formatVersion"`
	ID                   string       `json:"id" yaml:"id"`
	Name                 string       `json:"name" yaml:"name"`
	Description          string       `json:"description,omitempty" yaml:"description,omitempty"`
	Vars                 []Var        `json:"vars,omitempty" yaml:"vars,omitempty"`
	Headers              []KV         `json:"headers,omitempty" yaml:"headers,omitempty"`
	Auth                 Auth         `json:"auth" yaml:"auth"`
	Settings             HTTPSettings `json:"settings" yaml:"settings,omitempty"`
	IgnoreResponsesInGit bool         `json:"ignoreResponsesInGit" yaml:"ignoreResponsesInGit"`
}

// Environment je obsah `environments/<slug>.yaml`.
type Environment struct {
	ID   string `json:"id" yaml:"id"`
	Name string `json:"name" yaml:"name"`
	Vars []Var  `json:"vars,omitempty" yaml:"vars,omitempty"`
}

// Druhy uzlů stromu.
const (
	KindFolder  = "folder"
	KindRequest = "request"
)

// TreeNode je uzel stromu projektu. Kořen má Kind folder a Rel "".
type TreeNode struct {
	Kind     string     `json:"kind" yaml:"kind"`
	Rel      string     `json:"rel" yaml:"rel"`
	Name     string     `json:"name" yaml:"name"`
	Seq      int        `json:"seq" yaml:"seq"`
	ID       string     `json:"id,omitempty" yaml:"id,omitempty"`
	Method   string     `json:"method,omitempty" yaml:"method,omitempty"`
	URL      string     `json:"url,omitempty" yaml:"url,omitempty"`     // kvůli hledání ve stromu
	Error    string     `json:"error,omitempty" yaml:"error,omitempty"` // soubor nejde načíst (kód chyby)
	Children []TreeNode `json:"children,omitempty" yaml:"children,omitempty"`
}

// ProjectInfo je základní informace o otevřeném projektu.
type ProjectInfo struct {
	ID       string `json:"id" yaml:"id"`
	Name     string `json:"name" yaml:"name"`
	Path     string `json:"path" yaml:"path"`
	ReadOnly bool   `json:"readOnly" yaml:"readOnly"`
}

// NewID vrátí nové ULID.
func NewID() string { return ulid.Make().String() }
