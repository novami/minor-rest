import MinorRESTCore
import SwiftUI

/// Editor aktivního tabu: metoda, URL bar (URL + zapnuté query), Odeslat; záložky Parametry | Tělo | Hlavičky |
/// Auth | Nastavení | Dokumentace; banner, když se request změnil na disku a tab má neuložené změny.
struct RequestEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    let tab: RequestTab
    @State private var inherited: HTTPSettings?
    @State private var inheritedAuth: InheritedAuth?

    var body: some View {
        let tabs = model.tabs
        VStack(spacing: 0) {
            if tab.diskChanged != nil {
                HStack(spacing: 8) {
                    Text(t("request.changedOnDisk"))
                    Spacer()
                    Button(t("request.loadFromDisk")) { tabs.reloadFromDisk(tab.id) }
                    Button(t("request.keepMine")) { tabs.keepMine(tab.id) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                Divider()
            }
            HStack(spacing: 8) {
                MethodPicker(method: Binding(get: { tab.draft.method },
                                             set: { m in tabs.edit { $0.draft.method = m } }))
                VarField(text: urlText, placeholder: t("request.urlPlaceholder"), font: fonts.codeNSFont,
                         focusRequest: tabs.focusURLRequest, onSubmit: send)
                if model.runs.isRunning(tab.id) {
                    Button(t("request.cancel")) { model.cancelRun() }
                } else {
                    Button(t("request.send"), action: send)
                }
            }
            .padding(10)
            sectionBar
            Divider()
            if tab.section == .body {
                BodyEditor(requestBody: Binding(get: { tab.draft.body }, set: { b in tabs.edit { $0.draft.body = b } }),
                           tabID: tab.id, projectID: tab.projectID)
                    .padding(10)
            } else if tab.section == .docs {
                CodeTextView(text: Binding(get: { tab.draft.docs }, set: { d in tabs.edit { $0.draft.docs = d } }),
                             lang: .markdown, font: fonts.codeNSFont)
                    .id(tab.id + "/docs")
                    .padding(10)
            } else {
                ScrollView {
                    content.padding(10)
                }
            }
        }
        .environment(\.varContext, model.vars.context?.tabID == tab.id ? model.vars.context : nil)
    }

    private var sectionBar: some View {
        HStack(spacing: 2) {
            ForEach(RequestSection.allCases, id: \.self) { s in
                Button { model.tabs.edit { $0.section = s } } label: {
                    HStack(spacing: 4) {
                        Text(t("request.section.\(s.rawValue)"))
                        if (s == .body && tab.draft.body.type != "none" && !tab.draft.body.type.isEmpty)
                            || (s == .docs && !tab.draft.docs.isEmpty)
                            || (s == .auth && !AuthApply.isInherit(tab.draft.auth)) {
                            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                        }
                        if let n = count(s), n > 0 {
                            Text("\(n)").font(fonts.small).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tab.section == s ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private func count(_ s: RequestSection) -> Int? {
        let on = { (rows: [KV]) in rows.filter { $0.enabled && !$0.name.isEmpty }.count }
        switch s {
        case .params: return on(tab.draft.params.query) + pathRows.count
        case .headers: return on(tab.draft.headers)
        case .settings:
            let st = tab.draft.settings
            return [st.httpVersion != nil, st.followRedirects != nil, st.maxRedirects != nil,
                    st.timeoutMs != nil, st.verifyTLS != nil, st.cookieJar != nil].filter { $0 }.count
        case .body, .docs, .auth: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let tabs = model.tabs
        switch tab.section {
        case .params:
            VStack(alignment: .leading, spacing: 6) {
                KvEditor(title: t("request.query"), rows: Binding(get: { tab.draft.params.query },
                                       set: { q in tabs.edit { $0.draft.params.query = q } }),
                         allowBare: true)
                if !pathRows.isEmpty {
                    KvEditor(title: t("request.path"), rows: Binding(get: { pathRows.map { KV(name: $0.name, value: $0.value, description: $0.description) } },
                                           set: { rows in tabs.edit {
                                               $0.draft.params.path = rows.map { PathParam(name: $0.name, value: $0.value, description: $0.description) }
                                           } }),
                             fixed: true)
                    .padding(.top, 10)
                }
            }
        case .headers:
            KvEditor(rows: Binding(get: { tab.draft.headers }, set: { h in tabs.edit { $0.draft.headers = h } }),
                     names: HeaderHints.names, valuesFor: HeaderHints.values(for:))
        case .settings:
            SettingsEditor(settings: Binding(get: { tab.draft.settings }, set: { st in tabs.edit { $0.draft.settings = st } }),
                           inherited: inherited)
                .task(id: tab.projectID) {
                    inherited = (try? await model.projects.project(tab.projectID))?.config.settings.over(.builtin)
                }
        case .auth:
            AuthEditor(auth: Binding(get: { tab.draft.auth }, set: { a in tabs.edit { $0.draft.auth = a } }),
                       scope: .request, projectID: tab.projectID, inherited: inheritedAuth,
                       manualAuthorization: tab.draft.headers.contains {
                           $0.enabled && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Authorization") == .orderedSame
                       })
                .task(id: "\(tab.projectID)|\(tab.rel)|\(model.vars.revision)") {
                    guard let project = try? await model.projects.project(tab.projectID) else { return }
                    let rel = tab.rel
                    let folders = await Task.detached { (try? project.folderChain(rel)) ?? [] }.value
                    inheritedAuth = InheritedAuth(folders: folders, project: project.config.auth)
                }
        case .body, .docs:
            EmptyView()
        }
    }

    /// Path parametry podle `:name` v URL (uložené se dorovnají až při úpravě URL nebo hodnoty).
    private var pathRows: [PathParam] {
        PathParams.sync(tab.draft.url, tab.draft.params.path) ?? tab.draft.params.path
    }

    /// Vlastní text se drží, dokud po rozparsování odpovídá draftu (např. rozepsané `?` nebo `&`).
    private var urlText: Binding<String> {
        Binding(get: {
            let composed = URLBar.compose(url: tab.draft.url, query: tab.draft.params.query)
            guard let own = tab.urlText else { return composed }
            let p = URLBar.parse(own, query: tab.draft.params.query)
            return URLBar.compose(url: p.url, query: p.query) == composed ? own : composed
        }, set: { text in
            model.tabs.edit { t in
                let p = URLBar.parse(text, query: t.draft.params.query)
                t.urlText = text
                t.draft.url = p.url
                t.draft.params.query = p.query
                if let path = PathParams.sync(p.url, t.draft.params.path) { t.draft.params.path = path }
            }
        })
    }

    private func send() { model.send() }
}
