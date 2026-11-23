import Foundation
import MinorRESTCore
import Observation

/// Odeslání requestů aktivních tabů přes sdílený `HTTPEngine`; poslední běh per tab (jen v paměti).
@MainActor @Observable
final class RunStore {
    struct Run {
        let runID: String
        var running = true
        var result: RunResult?
        var body: BodyView?
        /// Chyba přípravy (proměnné, URL) nebo odeslání.
        var error: String?
        var unresolved: [String] = []
    }

    private(set) var runs: [String: Run] = [:]
    @ObservationIgnored let engine = HTTPEngine()
    @ObservationIgnored private let projects: ProjectsStore

    static let userAgent = "MinorREST/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")

    init(projects: ProjectsStore) {
        self.projects = projects
    }

    func run(_ tabID: String) -> Run? { runs[tabID] }

    func isRunning(_ tabID: String) -> Bool { runs[tabID]?.running == true }

    func send(_ tab: RequestTab) async {
        guard !isRunning(tab.id) else { return }
        let runID = ULID.make()
        runs[tab.id] = Run(runID: runID)
        do {
            let project = try await projects.project(tab.projectID)
            let prepared = try await Prepare.prepare(PrepareInput(
                request: tab.draft, project: project.config, folders: try project.folderChain(tab.rel),
                baseDir: project.root.path, userAgent: Self.userAgent))
            update(tab.id, runID) { $0.unresolved = prepared.unresolved }
            let result = await engine.send(runID: runID, prepared.request, prepared.options)
            let body = result.error == nil ? try? await engine.body(runID: runID, pretty: false) : nil
            update(tab.id, runID) {
                $0.running = false
                $0.result = result
                $0.body = body
                $0.error = result.error.map(errorText)
            }
        } catch {
            update(tab.id, runID) {
                $0.running = false
                $0.error = errorText(error)
            }
        }
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
