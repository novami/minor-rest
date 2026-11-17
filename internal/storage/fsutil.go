// Package storage čte a zapisuje projekt na disku (YAML soubory, strom, slugy, pořadí, koš).
package storage

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/novami/minor-rest/internal/model"
)

// Kódy chyb.
const (
	ErrNotFound       = "NOT_FOUND"
	ErrPathInvalid    = "PATH_INVALID"
	ErrNameEmpty      = "NAME_EMPTY"
	ErrReadOnly       = "PROJECT_READONLY"
	ErrProjectInvalid = "PROJECT_INVALID"
	ErrMoveIntoSelf   = "MOVE_INTO_SELF"
	ErrFS             = "FS_ERROR"
	ErrTrash          = "TRASH_FAILED"
)

func errf(code string, err error) error { return fmt.Errorf("%s: %w", code, err) }

func errCode(code, detail string) error { return fmt.Errorf("%s: %s", code, detail) }

func fsErr(err error) error {
	if errors.Is(err, fs.ErrNotExist) {
		return errf(ErrNotFound, err)
	}
	return errf(ErrFS, err)
}

// codeOf vrátí kód chyby (text před první `:`).
func codeOf(err error) string {
	s := err.Error()
	if i := strings.Index(s, ":"); i > 0 {
		return s[:i]
	}
	return ErrFS
}

// WriteFileAtomic zapíše soubor přes dočasný soubor ve stejném adresáři a rename.
func WriteFileAtomic(name string, data []byte) error {
	f, err := os.CreateTemp(filepath.Dir(name), ".tmp-*")
	if err != nil {
		return fsErr(err)
	}
	tmp := f.Name()
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Chmod(tmp, 0o644)
	}
	if err == nil {
		err = os.Rename(tmp, name)
	}
	if err != nil {
		os.Remove(tmp)
		return fsErr(err)
	}
	return nil
}

func writeYAML(name string, v any) error {
	data, err := model.MarshalYAML(v)
	if err != nil {
		return errf(ErrFS, err)
	}
	return WriteFileAtomic(name, data)
}

func readYAML(name string, v any) error {
	data, err := os.ReadFile(name)
	if err != nil {
		return fsErr(err)
	}
	return model.UnmarshalYAML(data, v)
}

func exists(name string) bool {
	_, err := os.Stat(name)
	return err == nil
}

// joinRel spojí relativní cesty s `/` (kořen = "").
func joinRel(parent, name string) string {
	if parent == "" {
		return name
	}
	return parent + "/" + name
}

func parentRel(rel string) string {
	if d := path.Dir(rel); d != "." {
		return d
	}
	return ""
}

func kindOf(rel string) string {
	if strings.HasSuffix(rel, model.RequestSuffix) {
		return model.KindRequest
	}
	return model.KindFolder
}

// slugOf vrátí slug uzlu (název souboru/adresáře bez přípony).
func slugOf(rel string) string {
	return strings.TrimSuffix(path.Base(rel), model.RequestSuffix)
}

func suffixFor(kind string) string {
	if kind == model.KindRequest {
		return model.RequestSuffix
	}
	return ""
}
