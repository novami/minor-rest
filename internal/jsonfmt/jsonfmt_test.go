package jsonfmt

import (
	"strings"
	"testing"
)

func TestFormat(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{`{"a":1,"b":[true,null]}`, "{\n  \"a\": 1,\n  \"b\": [\n    true,\n    null\n  ]\n}"},
		{`{"big":12345678901234567890.10}`, "{\n  \"big\": 12345678901234567890.10\n}"},
		{`{"id":{{id}},"s":"{{name}}","t":"x {{a}} y","e":"\{{no}}"}`,
			"{\n  \"id\": {{id}},\n  \"s\": \"{{name}}\",\n  \"t\": \"x {{a}} y\",\n  \"e\": \"\\{{no}}\"\n}"},
		{`{"q":"a\"{{v}}"}`, "{\n  \"q\": \"a\\\"{{v}}\"\n}"},
	} {
		got, err := Format(c.in)
		if err != nil || got != c.want {
			t.Errorf("Format(%s) = %q, %v; want %q", c.in, got, err, c.want)
		}
	}
	if _, err := Format("{\n\"a\": }"); err == nil || !strings.HasPrefix(err.Error(), ErrJSONInvalid+": 2:") {
		t.Errorf("invalid: %v", err)
	}
}
