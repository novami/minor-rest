package settings

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestWorkspaceRoundtrip(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "sub")
	w, err := LoadWorkspace(dir)
	if err != nil || w.SidebarWidth != DefaultSidebarWidth || w.Projects == nil {
		t.Fatalf("defaults: %+v %v", w, err)
	}
	w.Projects = []string{"/a/Projekt č. 1"}
	w.ActiveProject = "01X"
	w.Expanded["01X"] = []string{"users", "users/admin"}
	w.SidebarHidden = true
	if err := SaveWorkspace(dir, w); err != nil {
		t.Fatal(err)
	}
	got, err := LoadWorkspace(dir)
	if err != nil || !reflect.DeepEqual(got, w) {
		t.Fatalf("got %+v, %v; want %+v", got, err, w)
	}
}

func TestWorkspaceInvalid(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, WorkspaceFile), []byte("projects: [\n"), 0o644)
	w, err := LoadWorkspace(dir)
	if err == nil || w.ResponseHeight != DefaultResponseHeight {
		t.Fatalf("got %+v, %v", w, err)
	}
}
