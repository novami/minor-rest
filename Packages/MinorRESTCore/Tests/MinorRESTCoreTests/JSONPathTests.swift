import Foundation
import Testing
@testable import MinorRESTCore

private let doc = """
{"store": {"book": [
  {"category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century", "price": 8.95},
  {"category": "fiction", "author": "Evelyn Waugh", "title": "Sword of Honour", "price": 12.99},
  {"category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99},
  {"category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", "isbn": "0-395-19395-8", "price": 22.99}
], "bicycle": {"color": "red", "price": 399}}, "čísla": [0, 1, 2, 3, 4, 5], "e": [], "n": null}
"""

// Příklady z RFC 9535 (kap. 1.5, 2.3, 2.4) – výsledek kompaktně.
@Test(arguments: [
    ("$.store.book[*].author", #"["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"]"#),
    ("$..author", #"["Nigel Rees","Evelyn Waugh","Herman Melville","J. R. R. Tolkien"]"#),
    ("$.store..price", "[8.95,12.99,8.99,22.99,399]"),
    ("$..book[2].title", #"["Moby Dick"]"#),
    ("$..book[-1].title", #"["The Lord of the Rings"]"#),
    ("$..book[0,1].price", "[8.95,12.99]"),
    ("$..book[:2].price", "[8.95,12.99]"),
    ("$['čísla'][1:5:2]", "[1,3]"),
    ("$.čísla[::-2]", "[5,3,1]"),
    ("$.čísla[5:1:-2]", "[5,3]"),
    ("$.čísla[0:6:0]", "[]"),
    ("$..book[?@.isbn].title", #"["Moby Dick","The Lord of the Rings"]"#),
    ("$..book[?(@.price < 10)].price", "[8.95,8.99]"),
    ("$..book[?@.price<10 && @.category=='fiction'].title", #"["Moby Dick"]"#),
    ("$..book[?!(@.price >= 10) || @.author == \"J. R. R. Tolkien\"].price", "[8.95,8.99,22.99]"),
    ("$..book[?@.price == $.store.bicycle.price]", "[]"),
    ("$..book[?@.missing == @.alsoMissing].price", "[8.95,12.99,8.99,22.99]"),
    ("$..book[?length(@.title) > 15].price", "[8.95,22.99]"),
    ("$..book[?match(@.author, 'H.*')].price", "[8.99]"),
    ("$..book[?search(@.title, 'of')].price", "[8.95,12.99,22.99]"),
    ("$.store[?count(@.*) == 2].color", #"["red"]"#),
    ("$..book[?value(@..isbn) == '0-553-21311-3'].title", #"["Moby Dick"]"#),
    ("$[?@ == null]", "[null]"),
    ("$.e[*]", "[]"),
    ("$", ""),
])
func jsonPathSelect(_ path: String, _ want: String) throws {
    let root = try JSONValue.parse(doc)
    let got = JSONValue.array(try JSONPath(path).select(root)).compact
    if want.isEmpty { #expect(got.hasPrefix("[{\"store\"")) } else { #expect(got == want, "\(path)") }
}

@Test(arguments: ["", "store", "$.", "$..", "$[01]", "$[-0]", "$['a'", "$[?@.a == ]", "$[?1 == 1 &&]",
                  "$[?length(@.*) > 1]", "$[?@.* == 1]", "$[?length(@.a)]", "$[?foo(@.a)]", "$[?'a']", "$[9007199254740992]"])
func jsonPathInvalid(_ path: String) {
    #expect(throws: CoreError.self) { try JSONPath(path) }
}

@Test func jsonPathFilterFormats() throws {
    #expect(try JSONPath.filter(json: #"{"a": {"b": 1.50, "c": "ž\n"}}"#, "$.a") == "[\n  {\n    \"b\": 1.50,\n    \"c\": \"ž\\n\"\n  }\n]")
    let e = try #require(throws: CoreError.self) { try JSONPath.filter(json: "{}", "$[?@.a ==]") }
    #expect(e.code == .jsonPathInvalid && e.detail.hasPrefix("10:"))
    #expect(throws: CoreError.self) { try JSONPath.filter(json: "{", "$") }
}

@Test func jsonPathDeepNesting() throws {
    let n = JSONValue.maxDepth - 1
    let deep = String(repeating: "[", count: n) + "1" + String(repeating: "]", count: n)
    #expect(try JSONPath.filter(json: deep, "$..[?@ == 1]").contains("1"))
    #expect(throws: CoreError.self) { try JSONValue.parse("[" + deep + "]") }
}
