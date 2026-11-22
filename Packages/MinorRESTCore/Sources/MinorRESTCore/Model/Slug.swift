import Foundation

extension String {
    /// Unicode NFC (diakritika jako jeden znak) – normalizace všech vstupů.
    public var nfc: String { precomposedStringWithCanonicalMapping }
}

/// Názvy souborů a adresářů z názvů položek (PLAN 2.2).
public enum Slug {
    static let maxLength = 60
    static let fallback = "polozka"

    private static let map: [Unicode.Scalar: String] = [
        "ł": "l", "Ł": "l", "đ": "d", "Đ": "d", "ß": "ss",
        "ø": "o", "Ø": "o", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe",
    ]

    /// `Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`; prázdný výsledek → `polozka`.
    public static func make(_ name: String) -> String {
        var out = ""
        var dash = false
        for scalar in name.nfc.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            let mapped = map[scalar] ?? String(scalar).lowercased()
            for c in mapped.unicodeScalars {
                if ("a"..."z").contains(c) || ("0"..."9").contains(c) {
                    if dash && !out.isEmpty { out.append("-") }
                    dash = false
                    out.unicodeScalars.append(c)
                } else {
                    dash = true
                }
            }
        }
        return trim(out, maxLength)
    }

    /// Volný slug: při kolizi (case-insensitive, `taken` dostává lowercase) přidá `-2`, `-3`…
    public static func unique(_ slug: String, taken: (String) -> Bool) -> String {
        let slug = slug.isEmpty ? fallback : slug
        if !taken(slug.lowercased()) { return slug }
        var n = 2
        while true {
            let suffix = "-\(n)"
            let candidate = trim(slug, maxLength - suffix.count) + suffix
            if !taken(candidate.lowercased()) { return candidate }
            n += 1
        }
    }

    private static func trim(_ s: String, _ max: Int) -> String {
        let cut = String(s.prefix(max)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cut.isEmpty ? fallback : cut
    }
}
