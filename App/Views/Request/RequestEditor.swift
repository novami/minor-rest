import MinorRESTCore
import SwiftUI

/// Editor aktivního tabu: metoda, URL bar (URL + zapnuté query), Odeslat; záložky Parametry | Tělo | Hlavičky.
struct RequestEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    let tab: RequestTab

    var body: some View {
        let tabs = model.tabs
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                MethodPicker(method: Binding(get: { tab.draft.method },
                                             set: { m in tabs.edit { $0.draft.method = m } }))
                VarField(text: urlText, placeholder: t("request.urlPlaceholder"), font: fonts.codeNSFont,
                         focusRequest: tabs.focusURLRequest, onSubmit: send)
                Button(t("request.send"), action: send)
            }
            .padding(10)
            sectionBar
            Divider()
            ScrollView {
                content.padding(10)
            }
        }
    }

    private var sectionBar: some View {
        HStack(spacing: 2) {
            ForEach(RequestSection.allCases, id: \.self) { s in
                Button { model.tabs.edit { $0.section = s } } label: {
                    HStack(spacing: 4) {
                        Text(t("request.section.\(s.rawValue)"))
                        if s == .body, tab.draft.body.type != "none", !tab.draft.body.type.isEmpty {
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
        case .body: return nil
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
        case .body:
            Text(t("body.none")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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

    private func send() { model.notImplemented("menu.send") }
}
