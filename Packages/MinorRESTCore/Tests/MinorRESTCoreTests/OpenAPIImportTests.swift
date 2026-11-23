import Foundation
import Testing
@testable import MinorRESTCore

private func fixture(_ name: String) throws -> APISpec {
    let url = Bundle.module.resourceURL!.appending(path: "Fixtures/openapi/\(name)")
    return try OpenAPIImport.parse(String(contentsOf: url, encoding: .utf8))
}

@Test func openAPIv2Parse() throws {
    let s = try fixture("petstore2.json")
    #expect(s.title == "Swagger Petstore" && s.servers.map(\.url) == ["https://petstore.swagger.io/v2"])
    #expect(s.auth?.type == AuthType.apiKey && s.auth?.apiKey == APIKeyAuth(key: "api_key", value: "{{apiKey}}", location: "header"))
    #expect(s.warnings == ["security: petstore_auth"])
    #expect(s.operations.map(\.method) == ["POST", "GET", "POST", "DELETE", "GET", "GET"])
    let add = s.operations[0], get = s.operations[1]
    #expect(add.title == "Add a pet" && add.tag == "pet" && add.body?.type == BodyType.json)
    #expect(add.body?.raw.contains("\"name\": \"doggie\"") == true && add.body?.raw.contains("\"status\": \"available\"") == true)
    #expect(add.body?.raw.contains("2024-01-01T00:00:00Z") == true)
    #expect(get.title == "getPetById" && get.path == "/pet/:petId" && get.pathParams == [PathParam(name: "petId", value: "7")])
    #expect(s.operations[2].body?.type == BodyType.form && s.operations[2].body?.form.map(\.name) == ["name"])
    #expect(s.operations[3].auth?.type == AuthType.none && s.operations[0].auth == nil)
    let inv = s.operations[4]
    #expect(inv.query == [KV(name: "limit", value: "10", enabled: false)] && inv.headers[0].enabled)
    #expect(s.operations[5].title == "GET /ping")
}

@Test func openAPIv3Parse() throws {
    let s = try fixture("petstore3.yaml")
    #expect(s.servers.map(\.url) == ["https://prod.example.com/api/v3", "http://localhost:8080/api"])
    #expect(s.auth?.bearer?.token == "{{token}}" && s.variables.contains("username"))
    let put = s.operations[0]
    #expect(put.body?.type == BodyType.json)
    #expect(put.body?.raw.contains("\"id\": 0") == true && put.body?.raw.contains("\"name\": \"string\"") == true)
    #expect(put.body?.raw.contains("\"ro\"") == false)
    let list = s.operations[1]
    #expect(list.tag == "" && list.query == [KV(name: "status", value: "a", enabled: true), KV(name: "page", value: "2", enabled: false)])
    let up = s.operations[2]
    #expect(up.auth?.type == AuthType.basic && up.pathParams == [PathParam(name: "name", value: "bob")])
    #expect(up.body?.multipart == [MultipartPart(name: "file", kind: "file"), MultipartPart(name: "note", value: "string")])
}

@Test func openAPICycleAndInvalid() throws {
    let s = try fixture("cycle31.yaml")
    let raw = try #require(s.operations.first?.body?.raw)
    #expect(raw.contains("\"name\": \"string\"") && raw.contains("\"kids\": []"))
    #expect(throws: CoreError.self) { try OpenAPIImport.parse("hello: 1") }
}

@Test func openAPIGenerate() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mr-oa-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let spec = try fixture("petstore3.yaml")
    let pv = OpenAPIImport.preview(spec)
    #expect(pv.requestCount == 3 && pv.folders.map(\.name) == ["pet", "Ostatní", "user"] && pv.serverCount == 2)

    let secrets = MemorySecrets()
    let res = try OpenAPIImport.importProject(spec, in: dir, secrets: secrets, trash: { _ in })
    #expect(res.requestCount == 3 && res.environmentID != nil)
    let p = try Project.open(URL(fileURLWithPath: res.project.path), trash: { _ in })
    #expect(p.config.auth.type == AuthType.bearer && p.config.vars.map(\.name).contains("token"))
    let envs = try p.listEnvironments()
    #expect(envs.map(\.name).sorted() == ["Default", "Lokální"])
    #expect(envs.first { $0.name == "Default" }?.vars == [Var(name: "baseUrl", value: "https://prod.example.com/api/v3")])
    let tree = try p.loadTree()
    let pet = try #require(tree.children.first { $0.name == "pet" })
    let r = try p.loadRequest(pet.children[0].rel)
    #expect(r.method == "PUT" && r.url == "{{baseUrl}}/pet" && r.auth.type == AuthType.inherit)

    // do existujícího projektu: nová složka s baseUrl a auth
    let into = try OpenAPIImport.importFolder(spec, into: p)
    #expect(into.requestCount == 3)
    let wrap = try #require(try p.loadTree().children.first { $0.name == "Petstore 3" })
    #expect(try p.loadFolderConfig(wrap.rel).vars.first { $0.name == "baseUrl" }?.value == "https://prod.example.com/api/v3")
}
