import Foundation

/// Konfigurace jedné nadřazené složky requestu.
public struct PrepareFolder: Sendable, Equatable {
    public var rel: String
    public var config: FolderConfig

    public init(rel: String, config: FolderConfig) {
        self.rel = rel
        self.config = config
    }
}

/// Vše, co odeslání potřebuje (načte volající).
public struct PrepareInput: Sendable {
    public var request: Request
    public var project: ProjectConfig
    /// Od kořene k nejbližší složce.
    public var folders: [PrepareFolder]
    public var runtime: [Var]
    public var environment: [Var]
    public var globals: [Var]
    /// Globální výchozí nastavení.
    public var defaults: HTTPSettings
    public var baseDir: String
    public var userAgent: String
    /// OAuth2 klient; bez něj se OAuth2 auth nepřidá.
    public var oauth: OAuthClient?

    public init(request: Request, project: ProjectConfig = ProjectConfig(), folders: [PrepareFolder] = [],
                runtime: [Var] = [], environment: [Var] = [], globals: [Var] = [],
                defaults: HTTPSettings = .builtin, baseDir: String = "", userAgent: String = "",
                oauth: OAuthClient? = nil) {
        self.request = request
        self.project = project
        self.folders = folders
        self.runtime = runtime
        self.environment = environment
        self.globals = globals
        self.defaults = defaults
        self.baseDir = baseDir
        self.userAgent = userAgent
        self.oauth = oauth
    }
}

/// Request připravený pro `HTTPEngine`.
public struct Prepared: Sendable, Equatable {
    public var request: PreparedRequest
    public var options: HTTPEngine.Options
    public var unresolved: [String]
    /// Odkud je auth: `request`, `folder:<rel>`, `project` (`AuthApply.effective`).
    public var authSource: String
    /// Hodnoty tajných proměnných (maskování historie a uložených odpovědí).
    public var secrets: [String] = []
}

public enum Prepare {
    /// Automatické hlavičky, které lze vypnout řádkem se stejným názvem a `enabled: false`.
    static let autoHeaders = ["User-Agent", "Accept", "Content-Type"]

    /// Vyhodnotí proměnné, složí hlavičky (projekt → složky → request; nižší úroveň přepíše
    /// stejný název bez ohledu na velikost písmen) a nastavení (request → projekt → výchozí).
    /// Auth se zdědí (`AuthApply.effective`) a přidá za hlavičky. `async` kvůli OAuth (F7/2).
    public static func prepare(_ input: PrepareInput) async throws -> Prepared {
        let sc = scopes(input)
        let r = Resolver(scopes: sc)
        let req = input.request
        var url = try URLBuilder.build(req.url, path: req.params.path, query: req.params.query, resolver: r)

        var levels = [input.project.headers]
        levels += input.folders.map(\.config.headers)
        levels.append(req.headers)
        var (headers, noAuto) = try mergeHeaders(levels, r)
        let body = try resolveBody(req.body, r)

        let auth = AuthApply.effective(req.auth, folders: input.folders, project: input.project.auth)
        let queryNames = Set(try req.params.query.filter(\.enabled).map { try r.resolve($0.name).value })
        let s = req.settings.over(input.project.settings).over(input.defaults)
        let options = HTTPEngine.Options(s, userAgent: input.userAgent)
        let applied: (query: KV?, secrets: [String])
        if auth.auth.type == AuthType.oauth2, let client = input.oauth {
            applied = try await AuthApply.applyOAuth(auth.auth.oauth2 ?? OAuth2Auth(), client: client, options: options,
                                                     headers: &headers, queryNames: queryNames, r)
        } else {
            applied = try AuthApply.apply(auth.auth, headers: &headers, queryNames: queryNames, r)
        }
        if let q = applied.query {
            url += (url.contains("?") ? "&" : "?") + URLBuilder.encodeQuery([q])
        }

        return Prepared(
            request: PreparedRequest(method: req.method.trimmingCharacters(in: .whitespaces).uppercased(),
                                     url: url, headers: headers, body: body,
                                     baseDir: input.baseDir, noAuto: noAuto),
            options: options,
            unresolved: r.unresolved, authSource: auth.source,
            secrets: sc.flatMap(\.vars).filter { $0.secret && !$0.value.isEmpty }.map(\.value) + applied.secrets)
    }

    /// Platné proměnné pro UI (zvýraznění, hover, „oko“). Tajné proměnné bez načtené hodnoty
    /// (seznamy bez Keychain) se ve vnořených hodnotách zobrazí jako `***`, ne jako prázdný text.
    public static func explain(_ input: PrepareInput) -> [VarInfo] {
        let sc = scopes(input).map { scope in
            var scope = scope
            scope.vars = scope.vars.map { v in
                var v = v
                if v.secret && v.value.isEmpty { v.value = Resolver.masked }
                return v
            }
            return scope
        }
        return Resolver(scopes: sc).explain()
    }

    /// Vyhodnocená pole OAuth2 pro panel tokenu (stejné proměnné jako při odeslání).
    public static func oauthParams(_ a: OAuth2Auth, _ input: PrepareInput) throws -> OAuthParams {
        let r = Resolver(scopes: scopes(input))
        return try OAuthParams(a) { try r.resolve($0).value }
    }

    static func scopes(_ i: PrepareInput) -> [VarScope] {
        var s = [VarScope(.runtime, vars: i.runtime), VarScope(.request, vars: i.request.vars)]
        s += i.folders.reversed().map { VarScope(.folder, ref: $0.rel, vars: $0.config.vars) }
        s += [VarScope(.environment, vars: i.environment), VarScope(.project, vars: i.project.vars),
              VarScope(.global, vars: i.globals)]
        return s
    }

    /// Názvy zmíněné na nižší úrovni (zapnuté i vypnuté) odstraní zděděné, zapnuté řádky úrovně
    /// se připojí. Vypnutý řádek automatické hlavičky bez zapnutého protějšku ji vypne (`noAuto`).
    static func mergeHeaders(_ levels: [[KV]], _ r: Resolver) throws -> ([KV], [String]) {
        var out: [KV] = []
        var disabled: Set<String> = []
        for level in levels {
            var rows: [KV] = []
            var names: Set<String> = []
            for var h in level {
                let name = try r.resolve(h.name.trimmingCharacters(in: .whitespaces)).value
                if name.isEmpty { continue }
                let key = name.lowercased()
                names.insert(key)
                guard h.enabled else { disabled.insert(key); continue }
                disabled.remove(key)
                h.name = name
                h.value = try r.resolve(h.value).value
                rows.append(h)
            }
            out = out.filter { !names.contains($0.name.lowercased()) } + rows
        }
        return (out, autoHeaders.filter { disabled.contains($0.lowercased()) })
    }

    static func resolveBody(_ b: Body, _ r: Resolver) throws -> Body {
        func res(_ s: String) throws -> String { try r.resolve(s).value }
        var out = Body(type: b.type.isEmpty ? BodyType.none : b.type)
        switch out.type {
        case BodyType.form:
            for var kv in b.form where kv.enabled {
                kv.name = try res(kv.name)
                kv.value = try res(kv.value)
                out.form.append(kv)
            }
        case BodyType.multipart:
            for var p in b.multipart where p.enabled {
                p.name = try res(p.name)
                p.value = try res(p.value)
                p.path = try res(p.path)
                p.contentType = try res(p.contentType)
                out.multipart.append(p)
            }
        case BodyType.binary:
            out.binaryPath = try res(b.binaryPath)
        case BodyType.none:
            break
        default:
            out.raw = try res(b.raw)
        }
        return out
    }
}

extension Project {
    /// Konfigurace nadřazených složek requestu `rel` (od kořene); chybějící `_folder.yaml` = prázdná.
    public func folderChain(_ rel: String) throws -> [PrepareFolder] {
        var out: [PrepareFolder] = []
        var dir = (rel as NSString).deletingLastPathComponent
        while !dir.isEmpty && dir != "/" {
            do {
                out.append(PrepareFolder(rel: dir, config: try loadFolderConfig(dir)))
            } catch let e as CoreError where e.code == .notFound {
                out.append(PrepareFolder(rel: dir, config: FolderConfig()))
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return out.reversed()
    }
}
