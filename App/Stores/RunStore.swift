import Foundation
import MinorRESTCore
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
    }

    struct Filtered {
        let expr: String
        var text: String?
        var error: String?
    }

    private(set) var runs: [String: Run] = [:]
    /// JSONPath výraz per tab (platí i pro další běhy).
    var filters: [String: String] = [:]
    @ObservationIgnored let engine = HTTPEngine()
    @ObservationIgnored private let projects: ProjectsStore
    @ObservationIgnored private let environments: EnvironmentsStore
    @ObservationIgnored private let vars: VarsStore
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let appDir: URL
    @ObservationIgnored private var jars: [String: CookieJar] = [:]
    @ObservationIgnored let history: History

    static let userAgent = "MinorREST/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")

    init(projects: ProjectsStore, environments: EnvironmentsStore, vars: VarsStore, toasts: ToastCenter, appDir: URL) {
        self.projects = projects
        self.environments = environments
        self.vars = vars
        self.toasts = toasts
        self.appDir = appDir
        history = History(dir: appDir.appending(path: "history"))
    }

    func jar(_ projectID: String) -> CookieJar {
        if let j = jars[projectID] { return j }
        let j = CookieJar(file: CookieJar.file(projectID: projectID, in: appDir))
        jars[projectID] = j
        return j
    }

    func run(_ tabID: String) -> Run? { runs[tabID] }

    func isRunning(_ tabID: String) -> Bool { runs[tabID]?.running == true }

    func send(_ tab: RequestTab) async {
        guard !isRunning(tab.id) else { return }
        let runID = ULID.make()
        runs[tab.id] = Run(runID: runID)
        do {
            let project = try await projects.project(tab.projectID)
            let vars = try await environments.varsForSend(tab.projectID)
            let prepared = try await Prepare.prepare(PrepareInput(
                request: tab.draft, project: project.config, folders: try project.folderChain(tab.rel),
                runtime: self.vars.runtimeVars(tab.projectID), environment: vars.environment, globals: vars.globals,
                baseDir: project.root.path, userAgent: Self.userAgent))
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
            var entry = SavedResponse(result, request: prepared.request, secrets: prepared.secrets)
            (entry.projectID, entry.requestID, entry.requestName) = (tab.projectID, tab.draft.id, tab.draft.name)
            await persist(runID: runID, entry: entry, hasBody: result.error == nil, jar: jar)
        } catch {
            update(tab.id, runID) {
                $0.running = false
                $0.error = ErrorParts(error)
            }
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
    }

    func setMode(_ tabID: String, _ mode: BodyMode) {
        guard let r = runs[tabID] else { return }
        update(tabID, r.runID) { $0.mode = mode }
    }

    /// Odsazené tělo pro Pretty (mimo hlavní vlákno v enginu); chyba = zůstane Raw.
    func loadPretty(_ tabID: String) async {
        guard let r = runs[tabID], !r.running, r.pretty == nil, r.body != nil else { return }
        let v = try? await engine.body(runID: r.runID, pretty: true)
        update(tabID, r.runID) { $0.pretty = v ?? $0.body }
    }

    func forcePretty(_ tabID: String) {
        guard let r = runs[tabID] else { return }
        update(tabID, r.runID) { $0.forcePretty = true }
    }

    /// Vyhodnotí filtr tabu nad posledním během (mimo hlavní vlákno v enginu).
    func applyFilter(_ tabID: String) async {
        let expr = filters[tabID, default: ""].trimmingCharacters(in: .whitespaces)
        guard let r = runs[tabID], !r.running, r.filtered?.expr != expr else { return }
        guard !expr.isEmpty else { return update(tabID, r.runID) { $0.filtered = nil } }
        var f = Filtered(expr: expr)
        do { f.text = try await engine.filter(runID: r.runID, jsonPath: expr) } catch { f.error = errorText(error) }
        update(tabID, r.runID) { $0.filtered = f }
    }

    /// Uloží surové tělo; chyba → toast.
    func saveBody(_ tabID: String, to url: URL) async {
        guard let r = runs[tabID] else { return }
        do { try await engine.saveBody(runID: r.runID, to: url) } catch { toasts.show(errorText(error), isError: true) }
    }

    func cancel(_ tabID: String) async {
        guard let r = runs[tabID], r.running else { return }
        await engine.cancel(runID: r.runID)
    }

    /// Smaže výsledky a temp soubory (ukončení aplikace).
    func close() async { await engine.close() }

    /// Změna jen pokud tab mezitím nespustil nový běh.
    private func update(_ tabID: String, _ runID: String, _ change: (inout Run) -> Void) {
        guard var r = runs[tabID], r.runID == runID else { return }
        change(&r)
        runs[tabID] = r
    }
}
