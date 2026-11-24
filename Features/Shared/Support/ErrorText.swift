/// Lokalizovaný text chyby jádra: `errors.<kód>` + detail v závorce; neznámá chyba = její popis.
@MainActor
func errorText(_ error: Error) -> String {
    guard let elem = error as? CoreError else { return String(describing: error) }
    let key = "errors.\(elem.code.rawValue)"
    let message = t(key)
    if message == key { return elem.description }
    return elem.detail.isEmpty ? message : "\(message) (\(elem.detail))"
}

/// Lokalizovaný text chybového kódu (např. `TreeNode.error`).
@MainActor
func errorText(code: String) -> String {
    let message = t("errors.\(code)")
    return message == "errors.\(code)" ? code : message
}

/// Chyba pro chybový panel: lokalizovaná zpráva a technický detail zvlášť.
struct ErrorParts: Equatable {
    var message: String
    var detail: String

    @MainActor init(_ error: Error) {
        guard let elem = error as? CoreError else {
            (message, detail) = (String(describing: error), "")
            return
        }
        let key = "errors.\(elem.code.rawValue)"
        let map = t(key)
        (message, detail) = map == key ? (elem.code.rawValue, elem.detail) : (map, elem.detail)
    }
}
