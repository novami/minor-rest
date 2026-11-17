// Package settings čte a zapisuje globální soubory aplikace (workspace, později nastavení).
package settings

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/novami/minor-rest/internal/model"
	"github.com/novami/minor-rest/internal/storage"
)

const (
	AppDirName    = "MinorREST"
	WorkspaceFile = "workspace.yaml"

	DefaultSidebarWidth   = 260
	DefaultResponseHeight = 320
)

// Workspace je stav UI mezi spuštěními.
type Workspace struct {
	Projects       []string            `json:"projects" yaml:"projects"`             // cesty otevřených projektů v pořadí
	ActiveProject  string              `json:"activeProject" yaml:"activeProject"`   // ID
	Expanded       map[string][]string `json:"expanded" yaml:"expanded"`             // ID projektu → rozbalené složky (Rel)
	SidebarHidden  bool                `json:"sidebarHidden" yaml:"sidebarHidden"`
	SidebarWidth   int                 `json:"sidebarWidth" yaml:"sidebarWidth"`
	ResponseHeight int                 `json:"responseHeight" yaml:"responseHeight"`
}

// AppDir vrátí `~/Library/Application Support/MinorREST`.
func AppDir() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, AppDirName), nil
}

// DefaultProjectsDir vrátí `~/Documents/MinorREST`.
func DefaultProjectsDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Documents", AppDirName), nil
}

// LoadWorkspace načte workspace z adresáře; chybějící soubor = výchozí hodnoty.
// Při nečitelném souboru vrátí výchozí hodnoty i chybu.
func LoadWorkspace(dir string) (Workspace, error) {
	var w Workspace
	data, err := os.ReadFile(filepath.Join(dir, WorkspaceFile))
	if err == nil {
		err = model.UnmarshalYAML(data, &w)
	} else if errors.Is(err, fs.ErrNotExist) {
		err = nil
	}
	if err != nil {
		w = Workspace{}
	}
	return w.normalized(), err
}

// SaveWorkspace atomicky zapíše workspace.
func SaveWorkspace(dir string, w Workspace) error {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	data, err := model.MarshalYAML(w.normalized())
	if err != nil {
		return err
	}
	return storage.WriteFileAtomic(filepath.Join(dir, WorkspaceFile), data)
}

func (w Workspace) normalized() Workspace {
	if w.Projects == nil {
		w.Projects = []string{}
	}
	if w.Expanded == nil {
		w.Expanded = map[string][]string{}
	}
	if w.SidebarWidth <= 0 {
		w.SidebarWidth = DefaultSidebarWidth
	}
	if w.ResponseHeight <= 0 {
		w.ResponseHeight = DefaultResponseHeight
	}
	return w
}
