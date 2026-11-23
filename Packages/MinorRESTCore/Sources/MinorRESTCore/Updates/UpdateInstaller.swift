import CryptoKit
import Foundation

/// Stažení, ověření (ed25519 + identifikátor bundlu) a výměna aplikace.
public struct UpdateInstaller: Sendable {
    public let publicKey: Data      // 32 B, raw ed25519
    public let bundleID: String
    public let loader: DataLoader
    public let workDir: URL

    public init(publicKeyBase64: String, bundleID: String, loader: DataLoader = URLSession(configuration: .ephemeral), workDir: URL) throws {
        guard let key = Data(base64Encoded: publicKeyBase64), key.count == 32 else { throw CoreError(.updateNotConfigured) }
        publicKey = key
        self.bundleID = bundleID
        self.loader = loader
        self.workDir = workDir
    }

    /// Ověří podpis (base64) celého zipu.
    public func verify(zip: Data, signatureBase64: String) throws {
        guard let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(sig, for: zip)
        else { throw CoreError(.updateBadSignature) }
    }

    /// Stáhne zip + podpis, ověří, rozbalí a zkontroluje bundle. Vrací cestu k nové `.app`.
    public func prepare(_ info: UpdateInfo, progress: @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let fm = FileManager.default
        let dir = workDir.appendingPathComponent(info.version.description, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipData: Data, sigData: Data
        do {
            progress(0.1)
            let (sd, sr) = try await loader.load(URLRequest(url: info.signatureURL, timeoutInterval: 30))
            let (zd, zr) = try await loader.load(URLRequest(url: info.zipURL, timeoutInterval: 300))
            guard sr.statusCode == 200, zr.statusCode == 200 else { throw CoreError(.updateDownload, "HTTP \(zr.statusCode)") }
            sigData = sd
            zipData = zd
        } catch let e as CoreError { throw e } catch { throw CoreError(.updateDownload, "\(error)") }
        try verify(zip: zipData, signatureBase64: String(decoding: sigData, as: UTF8.self))
        progress(0.7)
        let zip = dir.appendingPathComponent("update.zip")
        try zipData.write(to: zip)
        let out = dir.appendingPathComponent("app", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let apps = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "app" } ?? []
        guard apps.count == 1, let bundle = Bundle(url: apps[0]), bundle.bundleIdentifier == bundleID,
              let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String, v == info.version.description
        else { throw CoreError(.updateBadBundle) }
        progress(1)
        return apps[0]
    }

    /// Nahradí `current` novým bundlem; při chybě vrátí původní.
    public static func swap(current: URL, with new: URL) throws {
        let fm = FileManager.default
        let old = current.deletingLastPathComponent().appendingPathComponent(current.lastPathComponent + ".old")
        try? fm.removeItem(at: old)
        do {
            try fm.moveItem(at: current, to: old)
            do { try fm.moveItem(at: new, to: current) } catch {
                try? fm.moveItem(at: old, to: current)
                throw error
            }
        } catch { throw CoreError(.updateInstall, "\(error)") }
        try? fm.removeItem(at: old)
    }

    /// Aplikaci nelze aktualizovat z karantény (translokace), z nezapisovatelného umístění ani z vývojového buildu.
    public static func installBlocker(bundleURL: URL) -> String? {
        if bundleURL.path.contains("/AppTranslocation/") { return "translocated" }
        if !FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) { return "not-writable" }
        return nil
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CoreError(.updateBadBundle, "\(tool) \(p.terminationStatus)") }
    }
}
