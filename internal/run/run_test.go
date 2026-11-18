package run

import (
	"errors"
	"testing"

	"github.com/novami/minor-rest/internal/httpclient"
)

func TestErrorOf(t *testing.T) {
	for _, tc := range []struct {
		err          error
		code, detail string
	}{
		{&httpclient.Error{Code: "NET_DNS", Detail: "x"}, "NET_DNS", "x"},
		{errors.New("VAR_UNRESOLVED_HOST: host"), "VAR_UNRESOLVED_HOST", "host"},
		{errors.New("something: broke"), ErrInternal, "something: broke"},
	} {
		e := ErrorOf(tc.err)
		if e.Code != tc.code || e.Detail != tc.detail {
			t.Errorf("%v → %+v", tc.err, e)
		}
	}
}

func TestFromResultEmptySlices(t *testing.T) {
	r := FromResult("r1", nil, errors.New("CANCELED"), nil)
	if r.Error.Code != "CANCELED" || r.Headers == nil || r.Unresolved == nil || r.Sent.Headers == nil {
		t.Errorf("%+v", r)
	}
}
