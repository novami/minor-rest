import Foundation
import Observation

/// Odeslání requestů aktivních tabů přes sdílený `HTTPEngine`; poslední běh per tab (jen v paměti),
/// cookie jar per projekt a zápis historie.
@MainActor @Observable
final class RunStore {
    struct Run {
        let runID: String
        let started = Date()
        var running = true
        var result: RunResult?
        /// Tělo bez úprav (Raw, Náhled) a odsazené (Pretty, načte se při prvním zobrazení).
        var body: BodyView?
        var pretty: BodyView?
        /// Pretty u těla nad `BodyView.autoPretty` až na vyžádání.
        var forcePretty = false
        /// Výsledek JSONPath filtru pro `filtered.expr`.
        var filtered: Filtered?
        /// Pohled zvolený uživatelem; `nil` = výchozí podle Content-Type.
        var mode: BodyMode?
        /// Chyba přípravy (proměnné, URL) nebo odeslání.
        var error: ErrorParts?
        var unresolved: [String] = []
        /// Maskovaný snímek běhu pro „Uložit odpověď“.
        var entry: SavedResponse?
    }

    struct Filtered {
        let expr: String
        var text: String?
        var error: String?
    }

    private(set) var runs: [String: Run] = [:]
    /// Uložené verze per request (klíč `projectID/requestID`), načtené při zobrazení záložky Verze.
    /// Historie odeslání (všechny projekty, nejnovější první).
    private(set) var historyItems: [HistoryItem] = []
    private(set) var versions: [String: [SavedInfo]] = [:]
    /// JSONPath výraz per tab (platí i pro další běhy).
    var filters: [String: String] = [:]
    @ObservationIgnored let engine = HTTPEngine()
    @ObservationIgnored let oauth: OAuthClient
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let environments: EnvironmentsStore
    @ObservationIgnored private let vars: VarsStore
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let appDir: URL
    @ObservationIgnored private var jars: [String: CookieJar] = [:]
    @ObservationIgnored let history: History

    static let userAgent =
        "MinorREST/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")

    init(projects: ProjectsStore, environments: EnvironmentsStore, vars: VarsStore, toasts: ToastCenter, appDir: URL) {
        self.projects = projects
        self.environments = environments
        self.vars = vars
        self.toasts = toasts
        self.appDir = appDir
        oauth = OAuthClient(engine: engine, secrets: Secrets())
        history = History(dir: appDir.appending(path: "history"))
    }

    func jar(_ projectID: String) -> CookieJar {
        if let j = jars[projectID] { return j }
        let j = CookieJar(file: CookieJar.file(projectID: projectID, in: appDir))
        jars[projectID] = j
        return j
    }

    /// Vyhodnocená OAuth2 pole a nastavení odeslání pro panel tokenu; `rel` = cesta, od které se skládají složky.
    func oauthParams(_ arg: OAuth2Auth, projectID: String, rel: String?) async throws -> (
        OAuthParams, HTTPEngine.Options
    ) {
        let project = try await projects.project(projectID)
        let vars = try await environments.varsForSend(projectID)
        let input = PrepareInput(
            request: Request(), project: project.config, folders: try rel.map { try project.folderChain($0) } ?? [],
            runtime: self.vars.runtimeVars(projectID), environment: vars.environment, globals: vars.globals)
        return (
            try Prepare.oauthParams(arg, input),
            HTTPEngine.Options(project.config.settings.over(.builtin), userAgent: Self.userAgent)
        )
    }

    func run(_ tabID: String) -> Run? { runs[tabID] }

    func isRunning(_ tabID: String) -> Bool { runs[tabID]?.running == true }

    func send(_ tab: RequestTab) async {
        guard !isRunning(tab.id) else { return }
        let runID = ULID.make()
        runs[tab.id] = Run(runID: runID)
        do {
            let prepared = try await prepare(tab.projectID, tab.rel, tab.draft)
            update(tab.id, runID) { $0.unresolved = prepared.unresolved }
            let jar = jar(tab.projectID)
            let result = await engine.send(runID: runID, prepared.request, prepared.options, jar: jar)
            let body = result.error == nil ? try? await engine.body(runID: runID, pretty: false) : nil
            update(tab.id, runID) {
                $0.running = false
                $0.result = result
                $0.body = body
                $0.error = result.error.map(ErrorParts.init)
            }
            await applyExtract(tab, runID: runID, result: result)
            var entry = SavedResponse(result, request: prepared.request, secrets: prepared.secrets)
            (entry.projectID, entry.requestID, entry.requestName) = (tab.projectID, tab.draft.id, tab.draft.name)
            update(tab.id, runID) { $0.entry = entry }
            await persist(runID: runID, entry: entry, hasBody: result.error == nil, jar: jar)
        } catch {
            update(tab.id, runID) {
                $0.running = false
                $0.error = ErrorParts(error)
            }
        }
    }

    /// Připraví request (proměnné, auth, path params) přesně tak, jak se odešle.
    private func prepare(_ projectID: String, _ rel: String, _ draft: Request) async throws -> Prepared {
        let project = try await projects.project(projectID)
        let vars = try await environments.varsForSend(projectID)
        return try await Prepare.prepare(
            PrepareInput(
                request: draft, project: project.config, folders: try project.folderChain(rel),
                runtime: self.vars.runtimeVars(projectID), environment: vars.environment, globals: vars.globals,
                baseDir: project.root.path, userAgent: Self.userAgent, oauth: oauth))
    }

    /// cURL requestu do schránky; chyba přípravy = toast.
    func copyCurl(_ projectID: String, _ rel: String, _ draft: Request, multiline: Bool, mask: Bool) async {
        do {
            let par = try await prepare(projectID, rel, draft)
            copyText(
                Export.curl(par.request, options: par.options, multiline: multiline, mask: mask, secrets: par.secrets))
            toasts.show(t("curl.copied"))
        } catch {
            toasts.show(errorText(error), isError: true)
        }
    }

    /// `extract` requestu → runtime proměnné projektu (jen odpověď 2xx); pravidla bez výsledku = toast, hodnota zůstane.
    private func applyExtract(_ tab: RequestTab, runID: String, result: RunResult) async {
        let rules = tab.draft.extract.filter { $0.enabled && !$0.name.isEmpty }
        guard !rules.isEmpty, result.error == nil, (200..<300).contains(result.status) else { return }
        let headers = result.headers
        let data = (try? await engine.rawBody(runID: runID, limit: 1 << 30)) ?? Data()
        let out = await Task.detached {
            Extractor.run(rules, body: String(decoding: data, as: UTF8.self), headers: headers)
        }.value
        for kv in out.values { vars.setRuntime(tab.projectID, kv.name, kv.value) }
        if !out.warnings.isEmpty {
            toasts.show(t("extract.failed", ["items": out.warnings.joined(separator: "; ")]), isError: true)
        }
    }

    /// Zápis jaru a historie mimo hlavní vlákno; chyba = toast.
    private func persist(runID: String, entry: SavedResponse, hasBody: Bool, jar: CookieJar) async {
        let body = hasBody ? try? await engine.rawBody(runID: runID, limit: History.maxBody + 1) : nil
        let history = history
        let err: (any Error)? = await Task.detached {
            do {
                try jar.save()
                try history.add(entry, body: body)
                return nil
            } catch { return error }
        }.value
        if let err { toasts.show(errorText(err), isError: true) }
        await loadHistory()
    }

    func loadHistory() async {
        let history = history
        historyItems = await Task.detached { history.list() }.value
    }

    func historyEntry(_ id: String) async -> (SavedResponse, Data)? {
        let history = history
        do { return try await Task.detached { (try history.entry(id), try history.body(id) ?? Data()) }.value } catch {
            toasts.show(errorText(error), isError: true)
            return nil
        }
    }

    func clearHistory() async {
        let history = history
        do { try await Task.detached { try history.clear() }.value } catch {
            toasts.show(errorText(error), isError: true)
        }
        await loadHistory()
    }

    func setMode(_ tabID: String, _ mode: BodyMode) {
        guard let res = runs[tabID] else { return }
        update(tabID, res.runID) { $0.mode = mode }
    }

    /// Odsazené tělo pro Pretty (mimo hlavní vlákno v enginu); chyba = zůstane Raw.
    func loadPretty(_ tabID: String) async {
        guard let res = runs[tabID], !res.running, res.pretty == nil, res.body != nil else { return }
        let val = try? await engine.body(runID: res.runID, pretty: true)
        update(tabID, res.runID) { $0.pretty = val ?? $0.body }
    }

    func forcePretty(_ tabID: String) {
        guard let res = runs[tabID] else { return }
        update(tabID, res.runID) { $0.forcePretty = true }
    }

    /// Vyhodnotí filtr tabu nad posledním během (mimo hlavní vlákno v enginu).
    func applyFilter(_ tabID: String) async {
        let expr = filters[tabID, default: ""].trimmingCharacters(in: .whitespaces)
        guard let res = runs[tabID], !res.running, res.filtered?.expr != expr else { return }
        guard !expr.isEmpty else { return update(tabID, res.runID) { $0.filtered = nil } }
        var fn = Filtered(expr: expr)
        do { fn.text = try await engine.filter(runID: res.runID, jsonPath: expr) } catch { fn.error = errorText(error) }
        update(tabID, res.runID) { $0.filtered = fn }
    }

    /// Uloží surové tělo; chyba → toast.
    func saveBody(_ tabID: String, to url: URL) async {
        guard let res = runs[tabID] else { return }
        do { try await engine.saveBody(runID: res.runID, to: url) } catch {
            toasts.show(errorText(error), isError: true)
        }
    }

    // MARK: Uložené verze

    static func key(_ projectID: String, _ requestID: String) -> String { projectID + "/" + requestID }

    private func responses(_ projectID: String, _ requestID: String) async throws -> Responses {
        Responses(project: try await projects.project(projectID), requestID: requestID)
    }

    func loadVersions(_ projectID: String, _ requestID: String) async {
        guard let store = try? await responses(projectID, requestID) else { return }
        versions[Self.key(projectID, requestID)] = await Task.detached { store.list() }.value
    }

    /// Uloží odpověď aktivního běhu jako další verzi; vrací číslo verze.
    @discardableResult
    func saveResponse(_ tabID: String, projectID: String, requestID: String, label: String = "") async -> Int? {
        guard let res = runs[tabID], !res.running, let entry = res.entry else { return nil }
        do {
            let store = try await responses(projectID, requestID)
            let body = res.result?.error == nil ? try? await engine.rawBody(runID: res.runID, limit: 1 << 30) : nil
            let info = try await Task.detached { try store.save(entry, body: body, label: label) }.value
            await loadVersions(projectID, requestID)
            return info.version
        } catch {
            toasts.show(errorText(error), isError: true)
            return nil
        }
    }

    func version(_ projectID: String, _ requestID: String, _ val: Int) async -> (SavedResponse, Data)? {
        do {
            let store = try await responses(projectID, requestID)
            return try await Task.detached { (try store.get(val), try store.body(val)) }.value
        } catch {
            toasts.show(errorText(error), isError: true)
            return nil
        }
    }

    func setLabel(_ projectID: String, _ requestID: String, _ val: Int, _ label: String) async {
        do { try await responses(projectID, requestID).setLabel(val, label) } catch {
            toasts.show(errorText(error), isError: true)
        }
        await loadVersions(projectID, requestID)
    }

    func deleteVersion(_ projectID: String, _ requestID: String, _ val: Int) async {
        do { try await responses(projectID, requestID).delete(val) } catch {
            toasts.show(errorText(error), isError: true)
        }
        await loadVersions(projectID, requestID)
    }

    func cancel(_ tabID: String) async {
        guard let res = runs[tabID], res.running else { return }
        await engine.cancel(runID: res.runID)
    }

    /// Smaže výsledky a temp soubory (ukončení aplikace).
    func close() async { await engine.close() }

    /// Změna jen pokud tab mezitím nespustil nový běh.
    private func update(_ tabID: String, _ runID: String, _ change: (inout Run) -> Void) {
        guard var res = runs[tabID], res.runID == runID else { return }
        change(&res)
        runs[tabID] = res
    }
}
