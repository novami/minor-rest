import MinorRESTCore
import SwiftUI

/// Editor aktivního tabu: metoda, URL bar (URL + zapnuté query), Odeslat.
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
            Divider()
            Spacer()
        }
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
            }
        })
    }

    private func send() { model.notImplemented("menu.send") }
}
