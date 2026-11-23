import AppKit
import MinorRESTCore
import Observation

/// Automatické aktualizace z GitHub Releases (PLAN kap. 10): kontrola, stažení, ověření, instalace.
@MainActor @Observable
final class UpdateStore {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateInfo)
        case downloading(UpdateInfo, Double)
        case ready(UpdateInfo)
        case failed(String)
    }

    static let feedURL = URL(string: "https://github.com/novami/minor-rest/releases/latest/download/appcast.json")!
    private static let autoCheckKey = "updates.autoCheck"
    private static let autoDownloadKey = "updates.autoDownload"

    private(set) var state: State = .idle
    let currentVersion: AppVersion
    private let toasts: ToastCenter
    private let defaults: UserDefaults
    private let checker: UpdateChecker
    private var installer: UpdateInstaller?
    private var readyApp: URL?
    private var loop: Task<Void, Never>?
    private var relaunch = false

    /// Výchozí hodnota obou voleb je zapnuto.
    var autoCheck: Bool {
        didSet { defaults.set(autoCheck, forKey: Self.autoCheckKey); restartLoop() }
    }
    var autoDownload: Bool {
        didSet { defaults.set(autoDownload, forKey: Self.autoDownloadKey) }
    }

    /// Nalezená aktualizace (v jakémkoli stavu, kdy je známa).
    var info: UpdateInfo? {
        switch state {
        case .available(let i), .downloading(let i, _), .ready(let i): return i
        default: return nil
        }
    }

    var statusText: String {
        switch state {
        case .idle: return t("updates.status.idle")
        case .checking: return t("updates.status.checking")
        case .upToDate: return t("updates.status.upToDate")
        case .available: return t("updates.status.available")
        case .downloading(_, let p): return t("updates.status.downloading", ["percent": String(Int(p * 100))])
        case .ready: return t("updates.status.ready")
        case .failed(let message): return message
        }
    }

    /// Vývojový build (0.0.0) neaktualizujeme.
    var isDevelopment: Bool { currentVersion.isDevelopment }

    init(toasts: ToastCenter, defaults: UserDefaults = .standard) {
        self.toasts = toasts
        self.defaults = defaults
        let bundle = Bundle.main
        currentVersion = AppVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? AppVersion(0, 0, 0)
        autoCheck = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        autoDownload = defaults.object(forKey: Self.autoDownloadKey) as? Bool ?? true
        checker = UpdateChecker(feedURL: Self.feedURL, current: currentVersion)
        let key = bundle.object(forInfoDictionaryKey: "MRUpdatePublicKey") as? String ?? ""
        let work = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MinorREST/update")
        installer = try? UpdateInstaller(publicKeyBase64: key, bundleID: bundle.bundleIdentifier ?? "", workDir: work)
    }

    /// Spustí periodickou kontrolu (10 s po startu, pak každých 24 h), pokud je zapnutá.
    func start() { restartLoop() }

    private func restartLoop() {
        loop?.cancel()
        guard autoCheck, !isDevelopment else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.check(manual: false)
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    /// Kontrola nyní; automatická nikdy nepřepisuje rozdělané stažení/hotovou aktualizaci.
    func check(manual: Bool) async {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        if isDevelopment { state = .failed(t("updates.devBuild")); return }
        state = .checking
        do {
            guard let info = try await checker.check() else { state = .upToDate; return }
            state = .available(info)
            if autoDownload { await download() }
        } catch {
            state = manual ? .failed(errorText(error)) : .idle
        }
    }

    /// Stažení a ověření nalezené aktualizace.
    func download() async {
        guard case .available(let info) = state else { return }
        guard let installer else { state = .failed(errorText(CoreError(.updateNotConfigured))); return }
        state = .downloading(info, 0)
        do {
            let app = try await installer.prepare(info) { [weak self] value in
                Task { @MainActor in self?.progress(value, info) }
            }
            readyApp = app
            state = .ready(info)
            toasts.show(t("updates.readyToast", ["version": info.version.description]), seconds: 6)
        } catch {
            state = .failed(errorText(error))
        }
    }

    private func progress(_ value: Double, _ info: UpdateInfo) {
        if case .downloading = state { state = .downloading(info, value) }
    }

    /// Restartovat a nainstalovat; samotná výměna proběhne při ukončení (po dotazu na neuložené taby).
    func installAndRestart() {
        guard case .ready = state else { return }
        if let reason = UpdateInstaller.installBlocker(bundleURL: Bundle.main.bundleURL) {
            state = .failed(t("updates.blocked.\(reason)"))
            return
        }
        relaunch = true
        NSApp.terminate(nil)
    }

    /// Volá `applicationWillTerminate`: připravenou aktualizaci nainstaluje (i při „Později“).
    func installIfReadyOnQuit() {
        guard case .ready = state, let new = readyApp, !isDevelopment else { return }
        let current = Bundle.main.bundleURL
        guard UpdateInstaller.installBlocker(bundleURL: current) == nil else { return }
        do { try UpdateInstaller.swap(current: current, with: new) } catch { return }
        guard relaunch else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", current.path]
        try? task.run()
    }
}
