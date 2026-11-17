package watch

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestRelOf(t *testing.T) {
	tests := []struct {
		path, want string
		ok         bool
	}{
		{"/p/a/b.req.yaml", "a/b.req.yaml", true},
		{"/p/a", "a", true},
		{"/p", "", false},
		{"/other/x", "", false},
		{"/p/.git/HEAD", "", false},
		{"/p/.responses/x/1.yaml", "", false},
		{"/p/a/.tmp-123", "", false},
	}
	for _, tt := range tests {
		got, ok := relOf("/p", tt.path)
		if got != tt.want || ok != tt.ok {
			t.Errorf("%s: %q %v", tt.path, got, ok)
		}
	}
}

func watchDir(t *testing.T, ignoreSelf bool) (string, chan []string) {
	if runtime.GOOS != "darwin" {
		t.Skip("FSEvents jen na macOS")
	}
	dir := t.TempDir()
	ch := make(chan []string, 10)
	w := New(func(id string, rels []string) { ch <- rels }, ignoreSelf)
	if err := w.Add("p", dir); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(w.Close)
	time.Sleep(200 * time.Millisecond) // stream se rozbíhá
	return dir, ch
}

func TestWatcherReportsChanges(t *testing.T) {
	dir, ch := watchDir(t, false)
	os.WriteFile(filepath.Join(dir, ".tmp-1"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(dir, "a.req.yaml"), []byte("x"), 0o644)
	select {
	case rels := <-ch:
		if len(rels) != 1 || rels[0] != "a.req.yaml" {
			t.Errorf("rels: %v", rels)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("žádná změna")
	}
}

func TestWatcherIgnoresSelf(t *testing.T) {
	dir, ch := watchDir(t, true)
	os.WriteFile(filepath.Join(dir, "a.req.yaml"), []byte("x"), 0o644)
	select {
	case rels := <-ch:
		t.Errorf("vlastní zápis nahlášen: %v", rels)
	case <-time.After(1 * time.Second):
	}
}
