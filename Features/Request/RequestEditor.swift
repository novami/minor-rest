import SwiftUI

/// Editor aktivního tabu: metoda, URL bar (URL + zapnuté query), Odeslat; záložky Parametry | Tělo | Hlavičky |
/// Auth | Nastavení | Dokumentace; banner, když se request změnil na disku a tab má neuložené změny.
struct RequestEditor: View {
    @Environment(AppModel.self) private var model

    private var curlMultiline: Binding<Bool> {
        Binding(get: { model.settings.value.copy.multiline }, set: { model.settings.value.copy.multiline = $0 })
    }

    private var curlMask: Binding<Bool> {
        Binding(get: { model.settings.value.copy.maskSecrets }, set: { model.settings.value.copy.maskSecrets = $0 })
    }
    @Environment(\.appFonts) private var fonts
    let tab: RequestTab
    @State private var inherited: HTTPSettings?
    @State private var inheritedAuth: InheritedAuth?
    /// Vložený příkaz cURL čekající na volbu (import / ponechat jako URL).
    @State private var pendingCurl: String?

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
            if let curl = pendingCurl {
                HStack {
                    Text(t("curl.importOffer"))
                    Spacer()
                    Button(t("curl.import")) {
                        importCurl(curl)
                        pendingCurl = nil
                    }
                    Button(t("curl.keepText")) {
                        applyURL(curl)
                        pendingCurl = nil
                    }
                    Button(t("common.cancel")) { pendingCurl = nil }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.15))
                Divider()
            }
            HStack(spacing: 8) {
                MethodPicker(
                    method: Binding(
                        get: { tab.draft.method },
                        set: { map in tabs.edit { $0.draft.method = map } }))
                VarField(
                    text: urlText, placeholder: t("request.urlPlaceholder"), font: fonts.codeNSFont,
                    focusRequest: tabs.focusURLRequest, onSubmit: send)
                Menu {
                    Picker("", selection: curlMultiline) {
                        Text(t("curl.multiline")).tag(true)
                        Text(t("curl.oneline")).tag(false)
                    }
                    .pickerStyle(.inline)
                    Toggle(t("curl.mask"), isOn: curlMask)
                } label: {
                    Image(systemName: "doc.on.doc")
                } primaryAction: {
                    Task {
                        await model.runs.copyCurl(
                            tab.projectID, tab.rel, tab.draft, multiline: model.settings.value.copy.multiline,
                            mask: model.settings.value.copy.maskSecrets)
                    }
                }
                .menuStyle(.button).fixedSize()
                .help(t("curl.copy"))
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
                BodyEditor(
                    requestBody: Binding(get: { tab.draft.body }, set: { buf in tabs.edit { $0.draft.body = buf } }),
                    tabID: tab.id, projectID: tab.projectID
                )
                .padding(10)
            } else if tab.section == .docs {
                CodeTextView(
                    text: Binding(get: { tab.draft.docs }, set: { dat in tabs.edit { $0.draft.docs = dat } }),
                    lang: .markdown, font: fonts.codeNSFont
                )
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
            ForEach(RequestSection.allCases, id: \.self) { str in
                Button {
                    model.tabs.edit { $0.section = str }
                } label: {
                    HStack(spacing: 4) {
                        Text(t("request.section.\(str.rawValue)"))
                        if (str == .body && tab.draft.body.type != "none" && !tab.draft.body.type.isEmpty)
                            || (str == .docs && !tab.draft.docs.isEmpty)
                            || (str == .auth && !AuthApply.isInherit(tab.draft.auth)) {
                            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                        }
                        if let num = count(str), num > 0 {
                            Text("\(num)").font(fonts.small).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(tab.section == str ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private func count(_ str: RequestSection) -> Int? {
        let on = { (rows: [KeyValue]) in rows.filter { $0.enabled && !$0.name.isEmpty }.count }
        switch str {
        case .params: return on(tab.draft.params.query) + pathRows.count
        case .headers: return on(tab.draft.headers)
        case .settings:
            let st = tab.draft.settings
            return [
                st.httpVersion != nil, st.followRedirects != nil, st.maxRedirects != nil,
                st.timeoutMs != nil, st.verifyTLS != nil, st.cookieJar != nil
            ].filter { $0 }.count
        case .vars:
            return tab.draft.vars.filter { $0.enabled && !$0.name.isEmpty }.count
                + tab.draft.extract.filter { $0.enabled && !$0.name.isEmpty }.count
        case .body, .docs, .auth: return nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let tabs = model.tabs
        switch tab.section {
        case .params:
            VStack(alignment: .leading, spacing: 6) {
                KvEditor(
                    title: t("request.query"),
                    rows: Binding(
                        get: { tab.draft.params.query },
                        set: { que in tabs.edit { $0.draft.params.query = que } }),
                    allowBare: true)
                if !pathRows.isEmpty {
                    KvEditor(
                        title: t("request.path"),
                        rows: Binding(
                            get: {
                                pathRows.map { KeyValue(name: $0.name, value: $0.value, description: $0.description) }
                            },
                            set: { rows in
                                tabs.edit {
                                    $0.draft.params.path = rows.map {
                                        PathParam(name: $0.name, value: $0.value, description: $0.description)
                                    }
                                }
                            }),
                        fixed: true
                    )
                    .padding(.top, 10)
                }
            }
        case .headers:
            KvEditor(
                rows: Binding(get: { tab.draft.headers }, set: { hdr in tabs.edit { $0.draft.headers = hdr } }),
                names: HeaderHints.names, valuesFor: HeaderHints.values(for:))
        case .settings:
            SettingsEditor(
                settings: Binding(get: { tab.draft.settings }, set: { st in tabs.edit { $0.draft.settings = st } }),
                inherited: inherited
            )
            .task(id: tab.projectID) {
                inherited = (try? await model.projects.project(tab.projectID))?.config.settings.over(.builtin)
            }
        case .auth:
            AuthEditor(
                auth: Binding(get: { tab.draft.auth }, set: { arg in tabs.edit { $0.draft.auth = arg } }),
                scope: .request, projectID: tab.projectID, inherited: inheritedAuth,
                manualAuthorization: tab.draft.headers.contains {
                    $0.enabled
                        && $0.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Authorization")
                            == .orderedSame
                }, oauthRel: tab.rel
            )
            .task(id: "\(tab.projectID)|\(tab.rel)|\(model.vars.revision)") {
                guard let project = try? await model.projects.project(tab.projectID) else { return }
                let rel = tab.rel
                let folders = await Task.detached { (try? project.folderChain(rel)) ?? [] }.value
                inheritedAuth = InheritedAuth(folders: folders, project: project.config.auth)
            }
        case .vars:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(t("request.vars")).font(fonts.ui.bold())
                    VarsEditor(
                        vars: Binding(get: { tab.draft.vars }, set: { val in tabs.edit { $0.draft.vars = val } }),
                        allowSecret: false, reveal: true)
                    Text(t("request.extract")).font(fonts.ui.bold())
                    Text(t("request.extract.hint")).font(fonts.small).foregroundStyle(.secondary)
                    ExtractEditor(
                        rules: Binding(get: { tab.draft.extract }, set: { res in tabs.edit { $0.draft.extract = res } })
                    )
                }
                .padding(.horizontal, 10)
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
        Binding(
            get: {
                let composed = URLBar.compose(url: tab.draft.url, query: tab.draft.params.query)
                guard let own = tab.urlText else { return composed }
                let par = URLBar.parse(own, query: tab.draft.params.query)
                return URLBar.compose(url: par.url, query: par.query) == composed ? own : composed
            },
            set: { text in
                if CurlImport.looksLikeCurl(text) {
                    pendingCurl = text
                    return
                }
                applyURL(text)
            })
    }

    private func applyURL(_ text: String) {
        model.tabs.edit { txt in
            let par = URLBar.parse(text, query: txt.draft.params.query)
            txt.urlText = text
            txt.draft.url = par.url
            txt.draft.params.query = par.query
            if let path = PathParams.sync(par.url, txt.draft.params.path) { txt.draft.params.path = path }
        }
    }

    /// Nahradí metodu, URL, parametry, hlavičky, auth, tělo a nastavení; id, název, proměnné, extract a docs zůstanou.
    private func importCurl(_ text: String) {
        do {
            let (res, warnings) = try CurlImport.parse(text)
            model.tabs.edit { txt in
                txt.draft.method = res.method
                txt.draft.url = res.url
                txt.draft.params = res.params
                txt.draft.headers = res.headers
                txt.draft.auth = res.auth
                txt.draft.body = res.body
                txt.draft.settings = res.settings
                txt.urlText = nil
            }
            if !warnings.isEmpty {
                model.toasts.show(t("curl.importWarnings", ["items": warnings.joined(separator: ", ")]))
            }
        } catch {
            model.toasts.show(errorText(error), isError: true)
        }
    }

    private func send() { model.send() }
}
