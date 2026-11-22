import AppKit
import MinorRESTCore
import Observation
import os

let log = Logger(subsystem: "com.github.novami.minorrest", category: "app")

/// `workspace.yaml`: načte se při startu, změny se ukládají se zpožděním a při ukončení aplikace.
@MainActor @Observable
final class WorkspaceStore {
    private(set) var ws: Workspace
    let directory: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL = DebugTools.workspaceDirectory ?? Workspace.appDirectory) {
        self.directory = directory
        do {
            ws = try Workspace.load(from: directory)
        } catch {
            log.error("workspace.yaml nelze načíst: \(String(describing: error))")
            ws = Workspace()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    /// Změní workspace a naplánuje uložení.
    func update(_ change: (inout Workspace) -> Void) {
        let before = ws
        change(&ws)
        guard ws != before else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try ws.save(to: directory)
        } catch {
            log.error("workspace.yaml nelze uložit: \(String(describing: error))")
        }
    }
}
