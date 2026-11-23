import Foundation
import Testing
@testable import MinorRESTCore

private func q(_ rows: [KV]) -> String { rows.map { "\($0.enabled ? "" : "!")\($0.name)=\($0.value)\($0.bare ? "~" : "")" }.joined(separator: ",") }

@Test(arguments: [
    // (text, výchozí query, očekávané url, query)
    ("{{base}}/u?page={{p}}&q=a=b", [], "{{base}}/u", "page={{p}},q=a=b"),
    ("http://x/?wsdl&flag=", [], "http://x/", "wsdl=~,flag="),
    ("http://x?b=2", [KV(name: "a", value: "1", enabled: false), KV(name: "old", value: "1", description: "d")],
     "http://x", "!a=1,b=2"),
    ("http://x", [KV(name: "a", value: "1"), KV(name: "b", value: "2", enabled: false)], "http://x", "!b=2"),
    ("http://x?&&c", [KV()], "http://x", "=,c=~"),
])
func urlBarParse(text: String, query: [KV], url: String, expected: String) {
    let r = URLBar.parse(text, query: query)
    #expect(r.url == url)
    #expect(q(r.query) == expected)
}

@Test func urlBarRoundTripKeepsDescription() {
    let query = [KV(name: "page", value: "1", description: "strana"), KV(name: "x", value: "", enabled: false),
                 KV(name: "wsdl", bare: true)]
    let text = URLBar.compose(url: "{{b}}/a", query: query)
    #expect(text == "{{b}}/a?page=1&wsdl")
    let r = URLBar.parse(text.replacingOccurrences(of: "page=1", with: "page=2"), query: query)
    #expect(r.query == [KV(name: "page", value: "2", description: "strana"), query[1], query[2]])
}

@Test func varTokens() {
    let s = "ž{{base}}/\\{{lit}}/{{ $uuid }}/{{open"
    let toks = VarToken.scan(s)
    #expect(toks.map(\.name) == ["base", "$uuid"])
    #expect(toks.map(\.kind) == [.variable, .dynamic])
    #expect((s as NSString).substring(with: toks[0].range) == "{{base}}")
    #expect((s as NSString).substring(with: toks[1].range) == "{{ $uuid }}")
}
