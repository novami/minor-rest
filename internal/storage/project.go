package storage

import (
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"

	"golang.org/x/text/unicode/norm"

	"github.com/novami/minor-rest/internal/model"
)

const gitignoreResponses = model.ResponsesDir + "/"

// Project je otevřený projekt. Metody jsou bezpečné pro souběžné volání.
type Project struct {
	Root     string
	mu       sync.Mutex
	cfg      model.ProjectConfig
	readOnly bool
}

// CreateProject založí projekt v novém adresáři `<parentDir>/<slug>`.
func CreateProject(parentDir, name string) (*Project, error) {
	name, err := cleanName(name)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(parentDir, 0o755); err != nil {
		return nil, fsErr(err)
	}
	taken, err := dirNames(parentDir)
	if err != nil {
		return nil, err
	}
	root := filepath.Join(parentDir, model.UniqueSlug(model.Slugify(name), has(taken)))
	if err := os.Mkdir(root, 0o755); err != nil {
		return nil, fsErr(err)
	}
	return InitProject(root, name)
}

// InitProject založí projekt v existujícím adresáři (už založený → PROJECT_INVALID).
func InitProject(root, name string) (*Project, error) {
	name, err := cleanName(name)
	if err != nil {
		return nil, err
	}
	if exists(filepath.Join(root, model.ProjectFile)) {
		return nil, errCode(ErrProjectInvalid, "already exists: "+root)
	}
	cfg := model.ProjectConfig{
		FormatVersion:        model.FormatVersion,
		ID:                   model.NewID(),
		Name:                 name,
		Auth:                 model.Auth{Type: model.AuthNone},
		IgnoreResponsesInGit: true,
	}
	if err := writeYAML(filepath.Join(root, model.ProjectFile), cfg); err != nil {
		return nil, err
	}
	if err := syncGitignore(root, true); err != nil {
		return nil, err
	}
	return &Project{Root: root, cfg: cfg}, nil
}

// IsProjectDir říká, zda adresář obsahuje soubor projektu.
func IsProjectDir(root string) bool { return exists(filepath.Join(root, model.ProjectFile)) }

// OpenProject otevře existující projekt. Vyšší formatVersion → jen pro čtení.
func OpenProject(root string) (*Project, error) {
	var cfg model.ProjectConfig
	if err := readYAML(filepath.Join(root, model.ProjectFile), &cfg); err != nil {
		if codeOf(err) == ErrNotFound {
			return nil, errf(ErrProjectInvalid, err)
		}
		return nil, err
	}
	if cfg.ID == "" {
		return nil, errCode(ErrProjectInvalid, "missing id")
	}
	return &Project{Root: root, cfg: cfg, readOnly: cfg.FormatVersion > model.FormatVersion}, nil
}

func (p *Project) Info() model.ProjectInfo {
	p.mu.Lock()
	defer p.mu.Unlock()
	return model.ProjectInfo{ID: p.cfg.ID, Name: p.cfg.Name, Path: p.Root, ReadOnly: p.readOnly}
}

func (p *Project) Config() model.ProjectConfig {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cfg
}

// SaveConfig uloží `minorrest.yaml` (ID a formatVersion zachová) a upraví .gitignore.
func (p *Project) SaveConfig(cfg model.ProjectConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.readOnly {
		return errCode(ErrReadOnly, p.Root)
	}
	model.NormalizeNFC(&cfg)
	cfg.ID, cfg.FormatVersion = p.cfg.ID, p.cfg.FormatVersion
	if err := writeYAML(filepath.Join(p.Root, model.ProjectFile), cfg); err != nil {
		return err
	}
	p.cfg = cfg
	return syncGitignore(p.Root, cfg.IgnoreResponsesInGit)
}

// abs převede relativní cestu (s `/`) na absolutní; odmítne `..` a absolutní cesty.
func (p *Project) abs(rel string) (string, error) {
	if rel == "" {
		return p.Root, nil
	}
	if strings.Contains(rel, `\`) || path.IsAbs(rel) || path.Clean(rel) != rel ||
		rel == ".." || strings.HasPrefix(rel, "../") {
		return "", errCode(ErrPathInvalid, rel)
	}
	return filepath.Join(p.Root, filepath.FromSlash(rel)), nil
}

func (p *Project) writable() error {
	if p.readOnly {
		return errCode(ErrReadOnly, p.Root)
	}
	return nil
}

func cleanName(name string) (string, error) {
	name = strings.TrimSpace(norm.NFC.String(name))
	if name == "" {
		return "", errCode(ErrNameEmpty, "")
	}
	return name, nil
}

// dirNames vrátí lowercase názvy položek adresáře (requesty bez přípony).
func dirNames(dir string) (map[string]bool, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fsErr(err)
	}
	m := make(map[string]bool, len(entries))
	for _, e := range entries {
		m[strings.ToLower(strings.TrimSuffix(e.Name(), model.RequestSuffix))] = true
	}
	return m, nil
}

func has(m map[string]bool) func(string) bool { return func(s string) bool { return m[s] } }

// syncGitignore přidá/odebere řádek `.responses/` v .gitignore projektu.
func syncGitignore(root string, ignore bool) error {
	name := filepath.Join(root, ".gitignore")
	data, err := os.ReadFile(name)
	if err != nil && !os.IsNotExist(err) {
		return fsErr(err)
	}
	var lines []string
	if len(data) > 0 {
		lines = strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	}
	found := -1
	for i, l := range lines {
		if strings.TrimSpace(l) == gitignoreResponses {
			found = i
			break
		}
	}
	switch {
	case ignore && found < 0:
		lines = append(lines, gitignoreResponses)
	case !ignore && found >= 0:
		lines = append(lines[:found], lines[found+1:]...)
	default:
		return nil
	}
	out := ""
	if len(lines) > 0 {
		out = strings.Join(lines, "\n") + "\n"
	}
	return WriteFileAtomic(name, []byte(out))
}

// Abs vrátí absolutní cestu uzlu (pro „Zobrazit ve Finderu“).
func (p *Project) Abs(rel string) (string, error) { return p.abs(rel) }
