import Testing
@testable import MinorRESTCore

@Suite struct ModelTests {
    @Test(arguments: [
        ("Příliš žluťoučký kůň", "prilis-zlutoucky-kun"),
        ("Úpěl ďábelské ódy".decomposedStringWithCanonicalMapping, "upel-dabelske-ody"),
        ("  Łódź / Straße -- Ærø ", "lodz-strasse-aero"),
        ("GET /users/{id}", "get-users-id"),
        ("!!!", "polozka"),
        ("", "polozka"),
        ("日本語", "polozka"),
        (String(repeating: "a", count: 59) + " b", String(repeating: "a", count: 59)),
    ])
    func slug(input: String, expected: String) {
        #expect(Slug.make(input) == expected)
    }

    @Test func uniqueSlug() {
        let taken: Set = ["uzivatele", "uzivatele-2"]
        #expect(Slug.unique("nove") { taken.contains($0) } == "nove")
        #expect(Slug.unique("Uzivatele") { taken.contains($0) } == "Uzivatele-3")
        #expect(Slug.unique("") { taken.contains($0) } == "polozka")
        let long = String(repeating: "x", count: 60)
        #expect(Slug.unique(long) { $0 == long } == String(repeating: "x", count: 58) + "-2")
    }

    @Test func settingsOver() {
        let got = HTTPSettings(httpVersion: "http1", maxRedirects: 0)
            .over(HTTPSettings(httpVersion: "auto", maxRedirects: 10, verifyTLS: false))
        #expect(got == HTTPSettings(httpVersion: "http1", maxRedirects: 0, verifyTLS: false))
    }

    @Test func ulid() {
        struct Fixed: RandomNumberGenerator {
            var value: UInt64
            mutating func next() -> UInt64 { value }
        }
        var zero = Fixed(value: 0), ones = Fixed(value: .max)
        #expect(ULID.make(ms: 0, using: &zero) == String(repeating: "0", count: 26))
        // max. čas (48 bitů) a samé jedničky v náhodné části
        #expect(ULID.make(ms: (1 << 48) - 1, using: &ones) == "7" + String(repeating: "Z", count: 25))
        let a = ULID.make(), b = ULID.make(date: .now.addingTimeInterval(1))
        #expect(a.count == 26 && a < b)
    }
}
