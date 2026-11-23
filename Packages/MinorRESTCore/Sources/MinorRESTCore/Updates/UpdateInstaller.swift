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

    /// Podepisovaná zpráva (sdílená s `tools/minorupdate.swift`): `minorupdate-v1\n<appID>\n<verze>\n<sha256 hex>`.
    static func signedMessage(appID: String, version: String, sha256: String) -> Data {
        Data("minorupdate-v1\n\(appID)\n\(version)\n\(sha256)".utf8)
    }

    /// Ověří otisk archivu a podpis feedu (vázaný na appID, verzi a otisk).
    public func verify(zip: Data, info: UpdateInfo) throws {
        let hex = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        guard hex == info.sha256.lowercased(),
              let sig = Data(base64Encoded: info.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(sig, for: Self.signedMessage(appID: bundleID, version: info.version.description, sha256: hex))
        else { throw CoreError(.updateBadSignature) }
    }

    /// Stáhne zip, ověří, rozbalí a zkontroluje bundle. Vrací cestu k nové `.app`.
    public func prepare(_ info: UpdateInfo, progress: @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let fm = FileManager.default
        let dir = workDir.appendingPathComponent(info.version.description, isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipData: Data
        do {
            progress(0.1)
            let (zd, zr) = try await loader.load(URLRequest(url: info.url, timeoutInterval: 300))
            guard zr.statusCode == 200 else { throw CoreError(.updateDownload, "HTTP \(zr.statusCode)") }
            zipData = zd
        } catch let e as CoreError { throw e } catch { throw CoreError(.updateDownload, "\(error)") }
        try verify(zip: zipData, info: info)
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
