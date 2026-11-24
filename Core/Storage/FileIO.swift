import Foundation

/// Souborové operace úložiště s chybami jako `CoreError`.
nonisolated enum FileIO {
    static var fm: FileManager { .default }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    /// Převod systémové chyby: neexistující soubor → `NOT_FOUND`, jinak `FS_ERROR`.
    static func error(_ error: Error) -> CoreError {
        if let elem = error as? CoreError { return elem }
        let ns = error as NSError
        let missing =
            (ns.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
            || (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map {
                $0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOENT)
            } == true
        return CoreError(missing ? .notFound : .fsError, ns.localizedDescription)
    }

    /// Atomický zápis: dočasný `.tmp-*` ve stejném adresáři (watcher ho ignoruje) + `rename(2)`.
    static func writeAtomic(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appending(path: ".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tmp, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: tmp)
            try handle.synchronize()
            try handle.close()
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tmp.path)
            guard rename(tmp.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw Self.error(error)
        }
    }

    static func readYAML<T: YAMLDecodable>(_ type: T.Type = T.self, from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Self.error(error)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CoreError(.yamlInvalid, "\(url.lastPathComponent): not UTF-8")
        }
        return try YAML.decode(T.self, from: text)
    }

    static func writeYAML<T: YAMLEncodable>(_ value: T, to url: URL) throws {
        try writeAtomic(Data(YAML.encode(value).utf8), to: url)
    }

    static func createDirectory(_ url: URL, intermediate: Bool = false) throws {
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: intermediate)
        } catch {
            throw Self.error(error)
        }
    }

    /// Názvy položek adresáře (lowercase, bez `.req.yaml`) – obsazené slugy.
    static func takenNames(in dir: URL) throws -> Set<String> {
        do {
            return Set(
                try fm.contentsOfDirectory(atPath: dir.path).map {
                    ($0.hasSuffix(ProjectFormat.requestSuffix)
                        ? String($0.dropLast(ProjectFormat.requestSuffix.count)) : $0)
                        .lowercased()
                })
        } catch {
            throw Self.error(error)
        }
    }

    /// Skutečná cesta s rozvinutými symlinky; neexistující konec se připojí k nejbližšímu existujícímu předkovi.
    static func realPath(_ path: String) -> String {
        var dir = (path as NSString).standardizingPath
        var rest: [String] = []
        while true {
            if let resolved = realpath(dir, nil) {
                defer { free(resolved) }
                return ([String(cString: resolved)] + rest.reversed()).joined(separator: "/")
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return path }
            rest.append((dir as NSString).lastPathComponent)
            dir = parent
        }
    }

    static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

/// Pomocné funkce pro relativní cesty (`/`, kořen = "").
nonisolated enum RelPath {
    static func join(_ parent: String, _ name: String) -> String { parent.isEmpty ? name : parent + "/" + name }

    static func parent(_ rel: String) -> String {
        guard let i = rel.lastIndex(of: "/") else { return "" }
        return String(rel[..<i])
    }

    static func base(_ rel: String) -> String {
        guard let i = rel.lastIndex(of: "/") else { return rel }
        return String(rel[rel.index(after: i)...])
    }

    static func kind(_ rel: String) -> TreeNode.Kind {
        rel.hasSuffix(ProjectFormat.requestSuffix) ? .request : .folder
    }

    static func slug(_ rel: String) -> String {
        let buf = base(rel)
        return buf.hasSuffix(ProjectFormat.requestSuffix)
            ? String(buf.dropLast(ProjectFormat.requestSuffix.count)) : buf
    }

    static func suffix(_ kind: TreeNode.Kind) -> String { kind == .request ? ProjectFormat.requestSuffix : "" }

    /// Platná relativní cesta: bez `\`, absolutní cesty, prázdných segmentů, `.` a `..`.
    static func isValid(_ rel: String) -> Bool {
        if rel.isEmpty { return true }
        if rel.contains("\\") || rel.hasPrefix("/") { return false }
        return rel.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}
