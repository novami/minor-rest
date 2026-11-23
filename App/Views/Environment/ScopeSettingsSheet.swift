import MinorRESTCore
import SwiftUI

/// Cíl nastavení: složka (`rel`) nebo celý projekt.
enum ScopeTarget: Identifiable, Hashable {
    case folder(rel: String, name: String)
    case project

    var id: String {
        switch self {
        case .folder(let rel, _): "f:" + rel
        case .project: "project"
        }
    }
}

/// „Nastavení složky“ / „Nastavení projektu“ (PLAN 8.5): proměnné, hlavičky, auth, u projektu i HTTP
/// nastavení. Úpravy se drží v konceptu a uloží se najednou.
struct ScopeSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFonts) private var fonts
    let target: ScopeTarget

    private enum Tab: Hashable { case vars, headers, auth, http }

    private struct Draft: Equatable {
        var name = ""
        var description = ""
        var vars: [Var] = []
        var headers: [KV] = []
        var auth = Auth()
        var settings = HTTPSettings()
        var ignoreResponsesInGit = false
    }

    @State private var tab = Tab.vars
    @State private var original: Draft?
    @State private var draft = Draft()
    @State private var readOnly = false
    @State private var inheritedAuth: InheritedAuth?
    @State private var saving = false
    @State private var error: String?

    private var projectID: String { model.projects.activeID }
    private var isProject: Bool { target == .project }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Picker("", selection: $tab) {
                Text(t("scope.tab.vars")).tag(Tab.vars)
                Text(t("scope.tab.headers")).tag(Tab.headers)
                Text(t("request.section.auth")).tag(Tab.auth)
                if isProject { Text(t("scope.tab.http")).tag(Tab.http) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if original == nil && error == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if original != nil {
                switch tab {
                case .vars:
                    ScrollView { VarsEditor(vars: $draft.vars, allowSecret: false, reveal: true) }
                case .headers:
                    ScrollView {
                        KvEditor(rows: $draft.headers, names: HeaderHints.names, valuesFor: HeaderHints.values(for:))
                    }
                case .auth:
                    ScrollView {
                        AuthEditor(auth: $draft.auth, scope: isProject ? .project : .folder, projectID: projectID,
                                   inherited: inheritedAuth,
                                   manualAuthorization: draft.headers.contains {
                                       $0.enabled && $0.name.caseInsensitiveCompare("Authorization") == .orderedSame
                                   })
                    }
                case .http:
                    projectHTTP
                }
            }

            if let error { Text(error).foregroundStyle(.red).font(fonts.small).textSelection(.enabled) }
            HStack {
                if readOnly { Text(t("project.readOnly")).foregroundStyle(.secondary) }
                Spacer()
                Button(t("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(t("common.save")) { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(original == nil || saving || original == cleaned)
            }
        }
        .padding(16)
        .frame(width: 720, height: 480)
        .task { await load() }
    }

    private var title: String {
        switch target {
        case .folder(_, let name): t("scope.folderTitle", ["name": name])
        case .project: t("scope.projectTitle", ["name": draft.name])
        }
    }

    private var projectHTTP: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(t("project.name"), text: $draft.name).textFieldStyle(.roundedBorder)
                TextField(t("scope.description"), text: $draft.description, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                Text(t("scope.httpHint")).font(fonts.small).foregroundStyle(.secondary)
                SettingsEditor(settings: $draft.settings, inherited: .builtin)
                Toggle(t("scope.ignoreResponses"), isOn: $draft.ignoreResponsesInGit).toggleStyle(.checkbox)
            }
        }
    }

    /// Koncept bez prázdných řádků.
    private var cleaned: Draft {
        var d = draft
        d.vars = d.vars.filter { !$0.name.isEmpty }
        d.headers = d.headers.filter { !$0.name.isEmpty }
        d.name = d.name.trimmingCharacters(in: .whitespaces)
        return d
    }

    private func load() async {
        do {
            let project = try await model.projects.project(projectID)
            let (d, parents): (Draft, [PrepareFolder]) = try await Task.detached {
                switch target {
                case .folder(let rel, _):
                    let c = try project.loadFolderConfig(rel)
                    return (Draft(vars: c.vars, headers: c.headers, auth: c.auth), try project.folderChain(rel))
                case .project:
                    let c = project.config
                    return (Draft(name: c.name, description: c.description, vars: c.vars, headers: c.headers,
                                  auth: c.auth, settings: c.settings, ignoreResponsesInGit: c.ignoreResponsesInGit), [])
                }
            }.value
            inheritedAuth = InheritedAuth(folders: parents, project: project.config.auth)
            readOnly = project.readOnly
            draft = d
            original = d
        } catch {
            self.error = errorText(error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let d = cleaned
        if isProject && d.name.isEmpty { error = t("scope.nameEmpty"); return }
        do {
            let project = try await model.projects.project(projectID)
            try await Task.detached {
                switch target {
                case .folder(let rel, _):
                    var c = try project.loadFolderConfig(rel)
                    c.vars = d.vars
                    c.headers = d.headers
                    c.auth = d.auth
                    try project.saveFolderConfig(rel, c)
                case .project:
                    var c = project.config
                    c.name = d.name
                    c.description = d.description
                    c.vars = d.vars
                    c.headers = d.headers
                    c.auth = d.auth
                    c.settings = d.settings
                    c.ignoreResponsesInGit = d.ignoreResponsesInGit
                    try project.saveConfig(c)
                }
            }.value
            if isProject { await model.projects.reload() }
            model.vars.invalidate()
            dismiss()
        } catch {
            self.error = errorText(error)
        }
    }
}
