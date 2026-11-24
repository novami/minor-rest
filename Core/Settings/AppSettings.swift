import Foundation

/// Globální nastavení aplikace (`settings.yaml` v adresáři aplikace, PLAN kap. 9). Chybějící klíč = výchozí hodnota.
nonisolated struct AppSettings: Equatable, Sendable {
    static let file = "settings.yaml"

    struct General: Equatable, Sendable {
        /// `auto` | `cs` | `en`
        var language = "auto"
        /// Výchozí adresář nových projektů; prázdný = `~/Documents/MinorREST`.
        var projectsDir = ""
        /// Při startu znovu otevřít projekty a taby.
        var restoreSession = true

        var projectsDirectory: URL {
            projectsDir.isEmpty ? Workspace.defaultProjectsDirectory : URL(fileURLWithPath: projectsDir)
        }
    }

    struct Requests: Equatable, Sendable {
        var followRedirects = true
        var maxRedirects = 10
        var timeoutMs = 30_000
        var verifyTLS = true
        var cookieJar = true
        /// Prázdný = `MinorREST/<verze>`.
        var userAgent = ""

        /// Globální výchozí pro skládání request → projekt → globální.
        var http: HTTPSettings {
            HTTPSettings(
                httpVersion: HTTPSettings.builtin.httpVersion, followRedirects: followRedirects,
                maxRedirects: maxRedirects, timeoutMs: timeoutMs, verifyTLS: verifyTLS, cookieJar: cookieJar)
        }
    }

    struct Responses: Equatable, Sendable {
        /// Největší stažené tělo (MB); větší se ořízne.
        var maxBodyMB = 100
        var historyLimit = 200
        /// Do této velikosti (MB) se Pretty spouští automaticky.
        var autoPrettyMB = 5

        var maxBodyBytes: Int64 { Int64(max(1, maxBodyMB)) << 20 }
        var autoPrettyBytes: Int64 { Int64(max(0, autoPrettyMB)) * 1_000_000 }
    }

    struct Copy: Equatable, Sendable {
        /// Při kopírování cURL nahradit tajné hodnoty `***`.
        var maskSecrets = true
    }

    var general = General()
    var requests = Requests()
    var responses = Responses()
    var copy = Copy()

    static func load(from dir: URL) throws -> AppSettings {
        let file = dir.appending(path: Self.file)
        guard FileIO.exists(file) else { return AppSettings() }
        return try FileIO.readYAML(AppSettings.self, from: file).normalized()
    }

    func save(to dir: URL) throws {
        try FileIO.createDirectory(dir, intermediate: true)
        try FileIO.writeYAML(normalized(), to: dir.appending(path: Self.file))
    }

    /// Neplatné hodnoty nahradí výchozími.
    func normalized() -> AppSettings {
        var par = self
        let def = AppSettings()
        if !["auto", "cs", "en"].contains(par.general.language) { par.general.language = def.general.language }
        if par.requests.maxRedirects < 0 { par.requests.maxRedirects = def.requests.maxRedirects }
        if par.requests.timeoutMs < 0 { par.requests.timeoutMs = def.requests.timeoutMs }
        if par.responses.maxBodyMB < 1 { par.responses.maxBodyMB = def.responses.maxBodyMB }
        if par.responses.historyLimit < 1 { par.responses.historyLimit = def.responses.historyLimit }
        if par.responses.autoPrettyMB < 0 { par.responses.autoPrettyMB = def.responses.autoPrettyMB }
        return par
    }
}

nonisolated extension AppSettings: YAMLCodable {
    var yaml: YNode {
        var gen = YMap()
        gen.add("language", general.language)
        gen.add("projectsDir", general.projectsDir)
        gen.add("restoreSession", general.restoreSession)
        var req = YMap()
        req.add("followRedirects", requests.followRedirects)
        req.add("maxRedirects", requests.maxRedirects)
        req.add("timeoutMs", requests.timeoutMs)
        req.add("verifyTLS", requests.verifyTLS)
        req.add("cookieJar", requests.cookieJar)
        req.add("userAgent", requests.userAgent)
        var res = YMap()
        res.add("maxBodyMB", responses.maxBodyMB)
        res.add("historyLimit", responses.historyLimit)
        res.add("autoPrettyMB", responses.autoPrettyMB)
        var cpy = YMap()
        cpy.add("maskSecrets", copy.maskSecrets)
        var map = YMap()
        map.add("general", gen.node)
        map.add("requests", req.node)
        map.add("responses", res.node)
        map.add("copy", cpy.node)
        return map.node
    }

    init(yaml opt: YAMLObject) throws {
        self.init()
        if let sec: General = try opt.object("general") { general = sec }
        if let sec: Requests = try opt.object("requests") { requests = sec }
        if let sec: Responses = try opt.object("responses") { responses = sec }
        if let sec: Copy = try opt.object("copy") { copy = sec }
    }
}

nonisolated extension AppSettings.General: YAMLDecodable {
    init(yaml opt: YAMLObject) throws {
        self.init()
        language = try opt.optionalString("language") ?? language
        projectsDir = try opt.optionalString("projectsDir") ?? projectsDir
        restoreSession = try opt.optionalBool("restoreSession") ?? restoreSession
    }
}

nonisolated extension AppSettings.Requests: YAMLDecodable {
    init(yaml opt: YAMLObject) throws {
        self.init()
        followRedirects = try opt.optionalBool("followRedirects") ?? followRedirects
        maxRedirects = try opt.optionalInt("maxRedirects") ?? maxRedirects
        timeoutMs = try opt.optionalInt("timeoutMs") ?? timeoutMs
        verifyTLS = try opt.optionalBool("verifyTLS") ?? verifyTLS
        cookieJar = try opt.optionalBool("cookieJar") ?? cookieJar
        userAgent = try opt.optionalString("userAgent") ?? userAgent
    }
}

nonisolated extension AppSettings.Responses: YAMLDecodable {
    init(yaml opt: YAMLObject) throws {
        self.init()
        maxBodyMB = try opt.optionalInt("maxBodyMB") ?? maxBodyMB
        historyLimit = try opt.optionalInt("historyLimit") ?? historyLimit
        autoPrettyMB = try opt.optionalInt("autoPrettyMB") ?? autoPrettyMB
    }
}

nonisolated extension AppSettings.Copy: YAMLDecodable {
    init(yaml opt: YAMLObject) throws {
        self.init()
        maskSecrets = try opt.optionalBool("maskSecrets") ?? maskSecrets
    }
}
