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
