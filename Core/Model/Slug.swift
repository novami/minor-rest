import Foundation

nonisolated extension String {
    /// Unicode NFC (diakritika jako jeden znak) – normalizace všech vstupů.
    var nfc: String { precomposedStringWithCanonicalMapping }
}

/// Názvy souborů a adresářů z názvů položek (PLAN 2.2).
nonisolated enum Slug {
    static let maxLength = 60
    static let fallback = "polozka"

    private static let map: [Unicode.Scalar: String] = [
        "ł": "l", "Ł": "l", "đ": "d", "Đ": "d", "ß": "ss",
        "ø": "o", "Ø": "o", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe"
    ]

    /// `Příliš žluťoučký kůň` → `prilis-zlutoucky-kun`; prázdný výsledek → `polozka`.
    static func make(_ name: String) -> String {
        var out = ""
        var dash = false
        for scalar in name.nfc.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            let mapped = map[scalar] ?? String(scalar).lowercased()
            for cur in mapped.unicodeScalars {
                if ("a"..."z").contains(cur) || ("0"..."9").contains(cur) {
                    if dash && !out.isEmpty { out.append("-") }
                    dash = false
                    out.unicodeScalars.append(cur)
                } else {
                    dash = true
                }
            }
        }
        return trim(out, maxLength)
    }

    /// Volný slug: při kolizi (case-insensitive, `taken` dostává lowercase) přidá `-2`, `-3`…
    static func unique(_ slug: String, taken: (String) -> Bool) -> String {
        let slug = slug.isEmpty ? fallback : slug
        if !taken(slug.lowercased()) { return slug }
        var num = 2
        while true {
            let suffix = "-\(num)"
            let candidate = trim(slug, maxLength - suffix.count) + suffix
            if !taken(candidate.lowercased()) { return candidate }
            num += 1
        }
    }

    private static func trim(_ str: String, _ max: Int) -> String {
        let cut = String(str.prefix(max)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cut.isEmpty ? fallback : cut
    }
}
