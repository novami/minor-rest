package main

import (
	"log"
	"os/exec"
	"slices"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/novami/minor-rest/internal/model"
	"github.com/novami/minor-rest/internal/settings"
	"github.com/novami/minor-rest/internal/storage"
)

// loadWorkspace načte workspace a znovu otevře projekty z minulého spuštění.
func (a *App) loadWorkspace() {
	dir, err := settings.AppDir()
	if err != nil {
		log.Printf("app dir: %v", err)
		return
	}
	a.appDir = dir
	ws, err := settings.LoadWorkspace(dir)
	if err != nil {
		log.Printf("workspace: %v", err)
	}
	for _, root := range ws.Projects {
		if _, err := a.projects.Open(root); err != nil {
			log.Printf("reopen %s: %v", root, err)
		}
	}
	a.wsMu.Lock()
	a.ws = ws
	a.wsMu.Unlock()
	a.updateWorkspace(func(w *settings.Workspace) {})
}

// updateWorkspace upraví workspace, doplní seznam projektů a uloží ho.
func (a *App) updateWorkspace(fn func(w *settings.Workspace)) error {
	a.wsMu.Lock()
	defer a.wsMu.Unlock()
	fn(&a.ws)
	a.ws.Projects = a.projects.Paths()
	open := a.projects.List()
	if !slices.ContainsFunc(open, func(p model.ProjectInfo) bool { return p.ID == a.ws.ActiveProject }) {
		a.ws.ActiveProject = ""
		if len(open) > 0 {
			a.ws.ActiveProject = open[0].ID
		}
	}
	for id := range a.ws.Expanded {
		if !slices.ContainsFunc(open, func(p model.ProjectInfo) bool { return p.ID == id }) {
			delete(a.ws.Expanded, id)
		}
	}
	if a.appDir == "" {
		return nil
	}
	return settings.SaveWorkspace(a.appDir, a.ws)
}

func (a *App) GetWorkspace() settings.Workspace {
	a.wsMu.Lock()
	defer a.wsMu.Unlock()
	return a.ws
}

// SaveWorkspace uloží stav UI; seznam projektů spravuje backend a z argumentu se ignoruje.
func (a *App) SaveWorkspace(w settings.Workspace) error {
	return a.updateWorkspace(func(cur *settings.Workspace) {
		w.Projects = cur.Projects
		*cur = w
	})
}

func (a *App) ListProjects() []model.ProjectInfo {
	return a.projects.List()
}

// CreateProject založí projekt; prázdný parentDir = ~/Documents/MinorREST.
func (a *App) CreateProject(name, parentDir string) (model.ProjectInfo, error) {
	if parentDir == "" {
		dir, err := settings.DefaultProjectsDir()
		if err != nil {
			return model.ProjectInfo{}, err
		}
		parentDir = dir
	}
	p, err := storage.CreateProject(parentDir, name)
	if err != nil {
		return model.ProjectInfo{}, err
	}
	return a.activate(a.projects.Add(p))
}

// OpenProjectDialog nechá vybrat adresář projektu; nil = zrušeno.
func (a *App) OpenProjectDialog() (*model.ProjectInfo, error) {
	dir, err := runtime.OpenDirectoryDialog(a.ctx, runtime.OpenDialogOptions{CanCreateDirectories: false})
	if err != nil || dir == "" {
		return nil, err
	}
	p, err := a.projects.Open(dir)
	if err != nil {
		return nil, err
	}
	info, err := a.activate(p)
	return &info, err
}

func (a *App) activate(p *storage.Project) (model.ProjectInfo, error) {
	info := p.Info()
	return info, a.updateWorkspace(func(w *settings.Workspace) { w.ActiveProject = info.ID })
}

func (a *App) CloseProject(projectID string) error {
	if err := a.projects.Close(projectID); err != nil {
		return err
	}
	return a.updateWorkspace(func(w *settings.Workspace) {})
}

func (a *App) GetTree(projectID string) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.LoadTree()
}

func (a *App) CreateFolder(projectID, parentRel, name string) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.CreateFolder(parentRel, name)
}

func (a *App) CreateRequest(projectID, parentRel, name string) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.CreateRequest(parentRel, name)
}

func (a *App) RenameNode(projectID, rel, newName string) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.Rename(rel, newName)
}

func (a *App) MoveNode(projectID, rel, targetParentRel string, index int) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.Move(rel, targetParentRel, index)
}

// DuplicateNode zduplikuje uzel; copySuffix je přípona názvu v jazyce UI (prázdná = „ kopie“).
func (a *App) DuplicateNode(projectID, rel, copySuffix string) (model.TreeNode, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.Duplicate(rel, copySuffix)
}

func (a *App) DeleteNode(projectID, rel string) error {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return err
	}
	return p.Delete(rel)
}

func (a *App) RevealInFinder(projectID, rel string) error {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return err
	}
	path, err := p.Abs(rel)
	if err != nil {
		return err
	}
	return exec.Command("open", "-R", path).Run()
}
