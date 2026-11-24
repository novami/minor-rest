import AppKit
import Observation

/// `settings.yaml` (kap. 9): načte se při startu, změny se projeví ihned a ukládají se se zpožděním a při ukončení.
@MainActor @Observable
final class SettingsStore {
    var value: AppSettings {
        didSet {
            guard value != oldValue else { return }
            if value.normalized() != value { value = value.normalized() }
            apply()
            scheduleSave()
        }
    }

    let directory: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL) {
        self.directory = directory
        do {
            value = try AppSettings.load(from: directory)
        } catch {
            AppLog.app.error("settings.yaml nelze načíst: \(error.localizedDescription, privacy: .public)")
            value = AppSettings()
        }
        apply()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    /// `User-Agent` odeslání; prázdné nastavení = `MinorREST/<verze>`.
    var userAgent: String {
        let custom = value.requests.userAgent.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }
        return "MinorREST/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
    }

    /// Nastavení odeslání z globálních výchozích a nastavení projektu (request → projekt → globální).
    func options(project: HTTPSettings) -> HTTPEngine.Options {
        var opts = HTTPEngine.Options(project.over(value.requests.http), userAgent: userAgent)
        opts.maxBodyBytes = value.responses.maxBodyBytes
        return opts
    }

    /// Jazyk se projeví okamžitě.
    private func apply() {
        L10n.shared.language = AppLanguage(rawValue: value.general.language) ?? .auto
    }

    private func scheduleSave() {
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
            try value.save(to: directory)
        } catch {
            AppLog.app.error("settings.yaml nelze uložit: \(error.localizedDescription, privacy: .public)")
        }
    }
}
