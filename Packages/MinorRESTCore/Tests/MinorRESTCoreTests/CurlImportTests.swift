import Foundation
import Testing
@testable import MinorRESTCore

private func imp(_ s: String) throws -> (Request, [String]) { try CurlImport.parse(s) }

@Test func curlJsonPost() throws {
    let (r, w) = try imp("""
    curl 'https://api.x.cz/u/:id?page=2&q=k%C5%AF%C5%88' \\
      -H 'Content-Type: application/json' -H 'X-A: it'\\''s' \\
      -H "Authorization: Bearer $TOKEN" --data-raw '{"a":"Příliš"}' -u 'jan:t:ajné' -L --max-redirs 3 -k --compressed -s
    """)
    #expect(r.method == "POST" && r.url == "https://api.x.cz/u/:id" && w.isEmpty)
    #expect(r.params.query.map(\.name) == ["page", "q"] && r.params.query[1].value == "k%C5%AF%C5%88")
    #expect(r.params.path.map(\.name) == ["id"])
    #expect(r.headers.map(\.name) == ["X-A", "Authorization"] && r.headers[0].value == "it's")
    #expect(r.body.type == BodyType.json && r.body.raw == #"{"a":"Příliš"}"#)
    #expect(r.auth.basic == BasicAuth(username: "jan", password: "t:ajné"))
    #expect(r.settings.followRedirects == true && r.settings.maxRedirects == 3 && r.settings.verifyTLS == false)
}

@Test func curlFormMultipartHead() throws {
    var (r, _) = try imp("curl example.com -d 'a=1&b=k%C5%AF%C5%88+x' -d c=3")
    #expect(r.url == "http://example.com" && r.method == "POST" && r.body.type == BodyType.form)
    #expect(r.body.form.map(\.name) == ["a", "b", "c"] && r.body.form[1].value == "kůň x")

    (r, _) = try imp("curl -X PUT http://a/ -F 't=hi' -F 'f=@/x/a.txt;type=text/plain'")
    #expect(r.method == "PUT" && r.body.type == BodyType.multipart)
    #expect(r.body.multipart[1].kind == "file" && r.body.multipart[1].path == "/x/a.txt" && r.body.multipart[1].contentType == "text/plain")

    (r, _) = try imp("curl -I http://a/")
    #expect(r.method == "HEAD" && r.body.type == BodyType.none)
}

@Test func curlTokenizerAndWarnings() throws {
    #expect(try CurlImport.tokenize(#"curl $'a\ný' "x\"y" z\ w 'q r'"#) == ["curl", "a\ný", "x\"y", "z w", "q r"])
    #expect(try CurlImport.tokenize("curl 'http://a' \\  -H 'X: y'") == ["curl", "http://a", "-H", "X: y"])
    let (r, w) = try imp("curl http://a/ --weird -sSL -b 'k=v' -d @file.json")
    #expect(r.headers.map(\.name) == ["Cookie"] && r.settings.followRedirects == true)
    #expect(w == ["--weird", "-d @file.json"])
    #expect(throws: CoreError.self) { try CurlImport.parse("curl 'http://a") }
    #expect(throws: CoreError.self) { try CurlImport.parse("wget http://a") }
    #expect(throws: CoreError.self) { try CurlImport.parse("curl -H") }
}

/// Export → import vrací stejný request (metoda, URL, hlavičky, tělo).
@Test func curlExportImportRoundtrip() throws {
    let p = PreparedRequest(method: "POST", url: "http://a/x?k=1", headers: [KV(name: "X-A", value: "it's $x")],
                            body: Body(type: BodyType.json, raw: "{\n \"ž\": 1\n}"))
    let (r, w) = try CurlImport.parse(Export.curl(p))
    #expect(w.isEmpty && r.method == "POST" && r.url == "http://a/x" && r.params.query == [KV(name: "k", value: "1")])
    #expect(r.headers == [KV(name: "X-A", value: "it's $x")] && r.body == Body(type: BodyType.json, raw: "{\n \"ž\": 1\n}"))
}
