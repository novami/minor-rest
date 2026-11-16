package main

import (
	"os/exec"
	"strings"

	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/menu/keys"
)

// systemLang returns "cs" or "en" based on the macOS preferred languages.
// Replaced by the language from settings in F11.
func systemLang() string {
	out, err := exec.Command("defaults", "read", "-g", "AppleLanguages").Output()
	if err == nil {
		s := strings.TrimLeft(strings.TrimSpace(string(out)), "( \n\"")
		if strings.HasPrefix(s, "cs") {
			return "cs"
		}
	}
	return "en"
}

var menuTexts = map[string]map[string]string{
	"cs": {
		"file": "Soubor", "newRequest": "Nový request", "newFolder": "Nová složka", "save": "Uložit",
		"closeTab": "Zavřít záložku", "settings": "Nastavení…",
		"request": "Request", "saveResponse": "Uložit odpověď", "copyCurl": "Kopírovat jako cURL",
		"duplicate": "Duplikovat", "focusUrl": "Přejít na URL",
		"view": "Zobrazení", "toggleSidebar": "Zobrazit/skrýt postranní panel", "palette": "Hledat…",
		"environment": "Vybrat prostředí…",
		"closeTitle": "Neuložené změny", "closeMessage": "Některé requesty mají neuložené změny. Opravdu ukončit?",
		"closeQuit": "Ukončit bez uložení", "closeCancel": "Zrušit",
	},
	"en": {
		"file": "File", "newRequest": "New Request", "newFolder": "New Folder", "save": "Save",
		"closeTab": "Close Tab", "settings": "Settings…",
		"request": "Request", "saveResponse": "Save Response", "copyCurl": "Copy as cURL",
		"duplicate": "Duplicate", "focusUrl": "Go to URL",
		"view": "View", "toggleSidebar": "Toggle Sidebar", "palette": "Search…",
		"environment": "Select Environment…",
		"closeTitle": "Unsaved changes", "closeMessage": "Some requests have unsaved changes. Quit anyway?",
		"closeQuit": "Quit without saving", "closeCancel": "Cancel",
	},
}

func menuLabels(lang string) map[string]string {
	if l, ok := menuTexts[lang]; ok {
		return l
	}
	return menuTexts["en"]
}

// buildMenu creates the native menu. Items only emit "menu:<action>" events;
// the frontend performs the action. Shortcuts defined here must not be handled
// again by frontend keydown listeners.
func (a *App) buildMenu() *menu.Menu {
	l := menuLabels(systemLang())
	cmdShift := func(k string) *keys.Accelerator { return keys.Combo(k, keys.CmdOrCtrlKey, keys.ShiftKey) }
	item := func(m *menu.Menu, label string, acc *keys.Accelerator, action string) {
		m.AddText(label, acc, func(*menu.CallbackData) { a.emit("menu:" + action) })
	}

	root := menu.NewMenu()
	root.Append(menu.AppMenu())

	file := root.AddSubmenu(l["file"])
	item(file, l["newRequest"], keys.CmdOrCtrl("n"), "new-request")
	item(file, l["newFolder"], cmdShift("n"), "new-folder")
	file.AddSeparator()
	item(file, l["save"], keys.CmdOrCtrl("s"), "save")
	item(file, l["closeTab"], keys.CmdOrCtrl("w"), "close-tab")
	file.AddSeparator()
	item(file, l["settings"], keys.CmdOrCtrl(","), "settings")

	root.Append(menu.EditMenu()) // required for Cmd+C/V/X/A/Z in the WebView

	req := root.AddSubmenu(l["request"])
	item(req, l["focusUrl"], keys.CmdOrCtrl("l"), "focus-url")
	item(req, l["saveResponse"], cmdShift("s"), "save-response")
	item(req, l["copyCurl"], cmdShift("c"), "copy-curl")
	item(req, l["duplicate"], keys.CmdOrCtrl("d"), "duplicate")

	view := root.AddSubmenu(l["view"])
	item(view, l["toggleSidebar"], keys.CmdOrCtrl("b"), "toggle-sidebar")
	item(view, l["palette"], keys.CmdOrCtrl("k"), "palette")
	item(view, l["environment"], keys.CmdOrCtrl("e"), "environment")

	root.Append(menu.WindowMenu())
	return root
}
