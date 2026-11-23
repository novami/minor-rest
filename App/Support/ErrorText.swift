import MinorRESTCore

/// Lokalizovaný text chyby jádra: `errors.<kód>` + detail v závorce; neznámá chyba = její popis.
@MainActor
func errorText(_ error: Error) -> String {
    guard let e = error as? CoreError else { return String(describing: error) }
    let key = "errors.\(e.code.rawValue)"
    let message = t(key)
    if message == key { return e.description }
    return e.detail.isEmpty ? message : "\(message) (\(e.detail))"
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
        guard let e = error as? CoreError else {
            (message, detail) = (String(describing: error), "")
            return
        }
        let key = "errors.\(e.code.rawValue)"
        let m = t(key)
        (message, detail) = m == key ? (e.code.rawValue, e.detail) : (m, e.detail)
    }
}
