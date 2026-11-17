// Package watch hlásí změny souborů v adresářích projektů.
package watch

import (
	"path/filepath"
	"strings"
	"time"
)

// Latency je doba, po kterou se změny slučují do jednoho hlášení.
const Latency = 300 * time.Millisecond

// relOf vrátí cestu vůči kořeni projektu; ok=false pro cesty mimo projekt
// a pro skryté položky (.git, .responses, dočasné .tmp-*, .DS_Store …).
func relOf(root, path string) (string, bool) {
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, "../") {
		return "", false
	}
	for _, seg := range strings.Split(filepath.ToSlash(rel), "/") {
		if strings.HasPrefix(seg, ".") {
			return "", false
		}
	}
	return filepath.ToSlash(rel), true
}
