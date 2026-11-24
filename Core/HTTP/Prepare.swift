import Foundation

/// Konfigurace jedné nadřazené složky requestu.
nonisolated struct PrepareFolder: Sendable, Equatable {
    var rel: String
    var config: FolderConfig
}

/// Vše, co odeslání potřebuje (načte volající).
nonisolated struct PrepareInput: Sendable {
    var request: Request
    var project: ProjectConfig
    /// Od kořene k nejbližší složce.
    var folders: [PrepareFolder]
    var runtime: [Var]
    var environment: [Var]
    var globals: [Var]
    /// Globální výchozí nastavení.
    var defaults: HTTPSettings
    var baseDir: String
    var userAgent: String
    /// OAuth2 klient; bez něj se OAuth2 auth nepřidá.
    var oauth: OAuthClient?

    init(
        request: Request, project: ProjectConfig = ProjectConfig(), folders: [PrepareFolder] = [],
        runtime: [Var] = [], environment: [Var] = [], globals: [Var] = [],
        defaults: HTTPSettings = .builtin, baseDir: String = "", userAgent: String = "",
        oauth: OAuthClient? = nil
    ) {
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
nonisolated struct Prepared: Sendable, Equatable {
    var request: PreparedRequest
    var options: HTTPEngine.Options
    var unresolved: [String]
    /// Odkud je auth: `request`, `folder:<rel>`, `project` (`AuthApply.effective`).
    var authSource: String
    /// Hodnoty tajných proměnných (maskování historie a uložených odpovědí).
    var secrets: [String] = []
}

nonisolated enum Prepare {
    /// Automatické hlavičky, které lze vypnout řádkem se stejným názvem a `enabled: false`.
    static let autoHeaders = ["User-Agent", "Accept", "Content-Type"]

    /// Vyhodnotí proměnné, složí hlavičky (projekt → složky → request; nižší úroveň přepíše
    /// stejný název bez ohledu na velikost písmen) a nastavení (request → projekt → výchozí).
    /// Auth se zdědí (`AuthApply.effective`) a přidá za hlavičky. `async` kvůli OAuth (F7/2).
    static func prepare(_ input: PrepareInput) async throws -> Prepared {
        let sc = scopes(input)
        let resVal = Resolver(scopes: sc)
        let req = input.request
        var url = try URLBuilder.build(req.url, path: req.params.path, query: req.params.query, resolver: resVal)

        var levels = [input.project.headers]
        levels += input.folders.map(\.config.headers)
        levels.append(req.headers)
        var (headers, noAuto) = try mergeHeaders(levels, resVal)
        let body = try resolveBody(req.body, resVal)

        let auth = AuthApply.effective(req.auth, folders: input.folders, project: input.project.auth)
        let queryNames = Set(try req.params.query.filter(\.enabled).map { try resVal.resolve($0.name).value })
        let str = req.settings.over(input.project.settings).over(input.defaults)
        let options = HTTPEngine.Options(str, userAgent: input.userAgent)
        let applied: (query: KeyValue?, secrets: [String])
        if auth.auth.type == AuthType.oauth2, let client = input.oauth {
            applied = try await AuthApply.applyOAuth(
                auth.auth.oauth2 ?? OAuth2Auth(), context: OAuthContext(client: client, options: options),
                headers: &headers, queryNames: queryNames, resVal)
        } else {
            applied = try AuthApply.apply(auth.auth, headers: &headers, queryNames: queryNames, resVal)
        }
        if let que = applied.query {
            url += (url.contains("?") ? "&" : "?") + URLBuilder.encodeQuery([que])
        }

        return Prepared(
            request: PreparedRequest(
                method: req.method.trimmingCharacters(in: .whitespaces).uppercased(),
                url: url, headers: headers, body: body,
                baseDir: input.baseDir, noAuto: noAuto),
            options: options,
            unresolved: resVal.unresolved, authSource: auth.source,
            secrets: sc.flatMap(\.vars).filter { $0.secret && !$0.value.isEmpty }.map(\.value) + applied.secrets)
    }

    /// Platné proměnné pro UI (zvýraznění, hover, „oko“). Tajné proměnné bez načtené hodnoty
    /// (seznamy bez Keychain) se ve vnořených hodnotách zobrazí jako `***`, ne jako prázdný text.
    static func explain(_ input: PrepareInput) -> [VarInfo] {
        let sc = scopes(input).map { scope in
            var scope = scope
            scope.vars = scope.vars.map { val in
                var val = val
                if val.secret && val.value.isEmpty { val.value = Resolver.masked }
                return val
            }
            return scope
        }
        return Resolver(scopes: sc).explain()
    }

    /// Vyhodnocená pole OAuth2 pro panel tokenu (stejné proměnné jako při odeslání).
    static func oauthParams(_ arg: OAuth2Auth, _ input: PrepareInput) throws -> OAuthParams {
        let resVal = Resolver(scopes: scopes(input))
        return try OAuthParams(arg) { try resVal.resolve($0).value }
    }

    static func scopes(_ i: PrepareInput) -> [VarScope] {
        var str = [VarScope(.runtime, vars: i.runtime), VarScope(.request, vars: i.request.vars)]
        str += i.folders.reversed().map { VarScope(.folder, ref: $0.rel, vars: $0.config.vars) }
        str += [
            VarScope(.environment, vars: i.environment), VarScope(.project, vars: i.project.vars),
            VarScope(.global, vars: i.globals)
        ]
        return str
    }

    /// Názvy zmíněné na nižší úrovni (zapnuté i vypnuté) odstraní zděděné, zapnuté řádky úrovně
    /// se připojí. Vypnutý řádek automatické hlavičky bez zapnutého protějšku ji vypne (`noAuto`).
    static func mergeHeaders(_ levels: [[KeyValue]], _ resVal: Resolver) throws -> ([KeyValue], [String]) {
        var out: [KeyValue] = []
        var disabled: Set<String> = []
        for level in levels {
            var rows: [KeyValue] = []
            var names: Set<String> = []
            for var hdr in level {
                let name = try resVal.resolve(hdr.name.trimmingCharacters(in: .whitespaces)).value
                if name.isEmpty { continue }
                let key = name.lowercased()
                names.insert(key)
                guard hdr.enabled else {
                    disabled.insert(key)
                    continue
                }
                disabled.remove(key)
                hdr.name = name
                hdr.value = try resVal.resolve(hdr.value).value
                rows.append(hdr)
            }
            out = out.filter { !names.contains($0.name.lowercased()) } + rows
        }
        return (out, autoHeaders.filter { disabled.contains($0.lowercased()) })
    }

    static func resolveBody(_ buf: Body, _ resVal: Resolver) throws -> Body {
        func res(_ str: String) throws -> String { try resVal.resolve(str).value }
        var out = Body(type: buf.type.isEmpty ? BodyType.none : buf.type)
        switch out.type {
        case BodyType.form:
            for var kv in buf.form where kv.enabled {
                kv.name = try res(kv.name)
                kv.value = try res(kv.value)
                out.form.append(kv)
            }
        case BodyType.multipart:
            for var par in buf.multipart where par.enabled {
                par.name = try res(par.name)
                par.value = try res(par.value)
                par.path = try res(par.path)
                par.contentType = try res(par.contentType)
                out.multipart.append(par)
            }
        case BodyType.binary:
            out.binaryPath = try res(buf.binaryPath)
        case BodyType.none:
            break
        default:
            out.raw = try res(buf.raw)
        }
        return out
    }
}

nonisolated extension Project {
    /// Konfigurace nadřazených složek requestu `rel` (od kořene); chybějící `_folder.yaml` = prázdná.
    func folderChain(_ rel: String) throws -> [PrepareFolder] {
        var out: [PrepareFolder] = []
        var dir = (rel as NSString).deletingLastPathComponent
        while !dir.isEmpty && dir != "/" {
            do {
                out.append(PrepareFolder(rel: dir, config: try loadFolderConfig(dir)))
            } catch let elem as CoreError where elem.code == .notFound {
                out.append(PrepareFolder(rel: dir, config: FolderConfig()))
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return out.reversed()
    }
}
