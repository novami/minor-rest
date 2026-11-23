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

@Test func bulkRoundTrip() {
    let rows = [KV(name: "Accept", value: "*/*", description: "typ"), KV(name: "X-A", value: "a: b", enabled: false),
                KV(name: "wsdl", bare: true)]
    let text = KVBulk.text(rows)
    #expect(text == "Accept: */*\n//X-A: a: b\nwsdl")
    #expect(KVBulk.parse(text, prev: rows, allowBare: true) == rows)
    // bez allowBare je řádek bez `:` obyčejný s prázdnou hodnotou; prázdné řádky se vynechají
    #expect(KVBulk.parse("\n  wsdl \n\n// x:1", prev: []) == [KV(name: "wsdl"), KV(name: "x", value: "1", enabled: false)])
}

@Test(arguments: [
    ("{{base}}/users/:id/posts/:post_id?x=:no", ["id", "post_id"]),
    ("http://localhost:8080/a/:id/:id", ["id"]),
    ("localhost:8080", []),
    ("http://x/:", []),
])
func pathParamNames(url: String, names: [String]) {
    #expect(PathParams.names(url) == names)
}

@Test func pathParamSyncKeepsValues() {
    let path = [PathParam(name: "id", value: "1", description: "d")]
    #expect(PathParams.sync("http://x/:id", path) == nil)
    #expect(PathParams.sync("http://x/:v/:id", path) == [PathParam(name: "v"), path[0]])
    #expect(PathParams.sync("http://x/", path) == [])
}

@Test func headerHints() {
    #expect(HeaderHints.values(for: " content-type ").first == "application/json")
    #expect(HeaderHints.complete("acc", in: HeaderHints.names) == ["Accept", "Accept-Charset", "Accept-Encoding", "Accept-Language"])
    #expect(HeaderHints.complete("Accept", in: HeaderHints.names).count == 3)
}

/// Tokeny jako `druh:text` pro čitelné porovnání.
private func syntax(_ text: String, _ lang: SyntaxLang) -> String {
    let ns = text as NSString
    return Syntax.tokens(text, lang).map { "\($0.kind):\(ns.substring(with: $0.range))" }.joined(separator: " ")
}

@Test(arguments: [
    (#"{"jméno": "Žluť 😀", "n": -1.5e3, "ok": true, "x": null, "id": {{id}}}"#, SyntaxLang.json,
     #"property:"jméno" string:"Žluť 😀" property:"n" number:-1.5e3 property:"ok" keyword:true property:"x" keyword:null property:"id""#),
    (#"{"a\"b" : "rozepsan"#, .json, #"property:"a\"b" string:"rozepsan"#),
    (#"<?xml v="1"?><!-- c --><a:b x="1" y='2'>t<![CDATA[<z>]]></a:b>"#, .xml,
     #"comment:<?xml v="1"?> comment:<!-- c --> keyword:a:b property:x string:"1" property:y string:'2' string:<![CDATA[<z>]]> keyword:a:b"#),
    ("<p>a < b</p>", .html, "keyword:p keyword:p"),
    ("{\"a\": 1}", .text, ""),
    ("# Nadpis\n- `x` a [odkaz](http://a)\n1. b\n> c\n```\n# ne\n```\n```\nrozepsáno", .markdown,
     "keyword:# Nadpis number:- string:`x` property:(http://a) number:1. comment:> c string:```\n# ne\n``` string:```\nrozepsáno"),
])
func syntaxTokens(text: String, lang: SyntaxLang, expected: String) {
    #expect(syntax(text, lang) == expected)
}
