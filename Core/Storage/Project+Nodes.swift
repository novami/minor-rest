import Foundation

nonisolated extension Project {
    // MARK: - Vytvoření

    func createFolder(parent: String, name: String) throws -> TreeNode {
        try create(parent: parent, name: name, kind: .folder)
    }

    /// Nový request (GET, prázdná URL) na konci sourozenců.
    func createRequest(parent: String, name: String) throws -> TreeNode {
        try create(parent: parent, name: name, kind: .request)
    }

    private func create(parent: String, name: String, kind: TreeNode.Kind) throws -> TreeNode {
        try locked {
            try writable()
            let name = try Self.cleanName(name)
            try requireFolder(parent)
            let rel = try freeRel(parent: parent, slug: Slug.make(name), kind: kind)
            let seq = (try siblings(parent, kind: kind).map(\.seq).max() ?? 0) + 1
            let target = try url(rel)
            if kind == .folder {
                try FileIO.createDirectory(target)
                try FileIO.writeYAML(
                    FolderConfig(name: name, seq: max(seq, 1), auth: Auth(type: AuthType.inherit)),
                    to: target.appending(path: ProjectFormat.folderFile))
            } else {
                var res = Request.new(id: ULID.make(), name: name)
                res.seq = max(seq, 1)
                try FileIO.writeYAML(res, to: target)
            }
            return try node(rel, deep: false)
        }
    }

    // MARK: - Requesty a konfigurace složek

    func loadRequest(_ rel: String) throws -> Request {
        try locked { try FileIO.readYAML(Request.self, from: try requestURL(rel)).fillingSecrets(secrets) }
    }

    /// Uloží obsah requestu; ID, název a pořadí zůstanou z disku (identitu drží strom).
    func saveRequest(_ rel: String, _ request: Request) throws {
        try locked {
            try writable()
            let file = try requestURL(rel)
            guard FileIO.exists(file) else { throw CoreError(.notFound, rel) }
            var res = request
            if let current = try? FileIO.readYAML(Request.self, from: file) {
                res.id = current.id
                res.name = current.name
                res.seq = current.seq
            }
            try FileIO.writeYAML(res.storingSecrets(secrets), to: file)
        }
    }

    /// Jednorázově přesune literály tajných hodnot ze všech requestů projektu do Keychainu.
    func migrateSecrets() {
        locked {
            for file in requestFiles(in: root) {
                guard let res = try? FileIO.readYAML(Request.self, from: file), !res.id.isEmpty,
                    let stored = try? res.storingSecrets(secrets), stored != res
                else { continue }
                try? FileIO.writeYAML(stored, to: file)
            }
            if let cur = try? FileIO.readYAML(
                ProjectConfig.self, from: root.appending(path: ProjectFormat.projectFile)),
                let stored = try? cur.storingSecrets(secrets), stored != cur {
                try? FileIO.writeYAML(stored, to: root.appending(path: ProjectFormat.projectFile))
            }
        }
    }

    func loadFolderConfig(_ rel: String) throws -> FolderConfig {
        try locked { try FileIO.readYAML(from: try folderFile(rel)) }
    }

    func saveFolderConfig(_ rel: String, _ config: FolderConfig) throws {
        try locked {
            try writable()
            let file = try folderFile(rel)
            guard FileIO.exists(file) else { throw CoreError(.notFound, rel) }
            try FileIO.writeYAML(config, to: file)
        }
    }

    // MARK: - Přejmenování, přesun, duplikace, smazání

    /// Změní název a přejmenuje soubor/adresář na nový slug; vrací uzel s novým `rel`.
    func rename(_ rel: String, to newName: String) throws -> TreeNode {
        try locked {
            try writable()
            let name = try Self.cleanName(newName)
            try requireNode(rel)
            try update(rel) { num, _ in num = name }
            let newRel = try freeRel(
                parent: RelPath.parent(rel), slug: Slug.make(name), kind: RelPath.kind(rel),
                self: RelPath.slug(rel))
            try move(from: rel, to: newRel)
            return try node(newRel, deep: true)
        }
    }

    /// Přesune položku do složky `target` na pozici `index` mezi sourozenci stejného druhu.
    func move(_ rel: String, to target: String, index: Int) throws -> TreeNode {
        try locked {
            try writable()
            try requireNode(rel)
            try requireFolder(target)
            let kind = RelPath.kind(rel)
            if kind == .folder && (target == rel || target.hasPrefix(rel + "/")) {
                throw CoreError(.moveIntoSelf, rel)
            }
            let oldParent = RelPath.parent(rel)
            var newRel = rel
            if oldParent != target {
                newRel = try freeRel(parent: target, slug: RelPath.slug(rel), kind: kind)
                try move(from: rel, to: newRel)
                try renumber(oldParent, kind: kind)
            }
            try renumber(target, kind: kind, place: newRel, at: index)
            return try node(newRel, deep: true)
        }
    }

    /// Kopie hned za originálem s názvem `<název><přípona>` a novými ID requestů.
    func duplicate(_ rel: String, copySuffix: String = "") throws -> TreeNode {
        try locked {
            try writable()
            try requireNode(rel)
            let kind = RelPath.kind(rel)
            let parent = RelPath.parent(rel)
            let name = try node(rel, deep: false).name + (copySuffix.isEmpty ? Self.defaultCopySuffix : copySuffix)
            let newRel = try freeRel(parent: parent, slug: Slug.make(name), kind: kind)
            let src = try url(rel)
            let dst = try url(newRel)
            if kind == .request {
                var res = try FileIO.readYAML(Request.self, from: src).fillingSecrets(secrets)
                res.id = ULID.make()
                res.name = name
                try FileIO.writeYAML(res.storingSecrets(secrets), to: dst)
            } else {
                try copyFolder(src, to: dst, name: name)
            }
            let sibs = try siblings(parent, kind: kind)
            let index = (sibs.firstIndex { $0.rel == rel }).map { $0 + 1 } ?? sibs.count
            try renumber(parent, kind: kind, place: newRel, at: index)
            return try node(newRel, deep: true)
        }
    }

    /// Přesune položku do Koše, včetně uložených odpovědí jejích requestů (pokud ID nepoužívá jiný request).
    func delete(_ rel: String) throws {
        try locked {
            try writable()
            try requireNode(rel)
            let target = try url(rel)
            let ids = requestIDs(in: target)
            do { try trash(target) } catch { throw CoreError(.trashFailed, error.localizedDescription) }
            let inUse = ids.isEmpty ? [] : Set(requestIDs(in: root))
            for id in ids where !inUse.contains(id) {
                let dir = root.appending(path: ProjectFormat.responsesDir).appending(path: id)
                guard FileIO.exists(dir) else { continue }
                do { try trash(dir) } catch { throw CoreError(.trashFailed, error.localizedDescription) }
            }
        }
    }

    // MARK: - Interní (volat se zámkem)

    func requestURL(_ rel: String) throws -> URL {
        guard RelPath.kind(rel) == .request else { throw CoreError(.pathInvalid, rel) }
        return try url(rel)
    }

    func folderFile(_ rel: String) throws -> URL {
        guard !rel.isEmpty, RelPath.kind(rel) == .folder else { throw CoreError(.pathInvalid, rel) }
        return try url(rel).appending(path: ProjectFormat.folderFile)
    }

    /// Kořen nebo existující složka.
    func requireFolder(_ rel: String) throws {
        if rel.isEmpty { return }
        guard FileIO.exists(try folderFile(rel)) else { throw CoreError(.notFound, rel) }
    }

    func requireNode(_ rel: String) throws {
        if rel.isEmpty { throw CoreError(.pathInvalid, "root") }
        if RelPath.kind(rel) == .folder { return try requireFolder(rel) }
        guard FileIO.exists(try url(rel)) else { throw CoreError(.notFound, rel) }
    }

    /// Volný `rel` pro slug v rodiči (`self` = vlastní současný slug, nepočítá se jako kolize).
    func freeRel(parent: String, slug: String, kind: TreeNode.Kind, self own: String = "") throws -> String {
        var taken = try FileIO.takenNames(in: try url(parent))
        taken.remove(own.lowercased())
        if parent.isEmpty { taken.insert(ProjectFormat.environmentDir) }
        return RelPath.join(parent, Slug.unique(slug) { taken.contains($0) } + RelPath.suffix(kind))
    }

    func move(from: String, to: String) throws {
        if from == to { return }
        guard Darwin.rename(try url(from).path, try url(to).path) == 0 else {
            throw FileIO.error(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
        }
    }

    /// Upraví název nebo pořadí v souboru requestu / `_folder.yaml`.
    func update(_ rel: String, _ change: (inout String, inout Int) -> Void) throws {
        if RelPath.kind(rel) == .request {
            let file = try url(rel)
            var res: Request = try FileIO.readYAML(from: file)
            change(&res.name, &res.seq)
            try FileIO.writeYAML(res, to: file)
        } else {
            let file = try folderFile(rel)
            var cfg: FolderConfig = try FileIO.readYAML(from: file)
            change(&cfg.name, &cfg.seq)
            try FileIO.writeYAML(cfg, to: file)
        }
    }

    /// Přečísluje sourozence 1..n (volitelně s `place` vloženým na `index`); zapíše jen změněné.
    func renumber(_ parent: String, kind: TreeNode.Kind, place: String = "", at index: Int = 0) throws {
        var sibs = try siblings(parent, kind: kind)
        if !place.isEmpty, let i = sibs.firstIndex(where: { $0.rel == place }) {
            let moved = sibs.remove(at: i)
            sibs.insert(moved, at: min(max(index, 0), sibs.count))
        }
        for (i, num) in sibs.enumerated() where num.error.isEmpty && num.seq != i + 1 {
            try update(num.rel) { _, seq in seq = i + 1 }
        }
    }

    private func copyFolder(_ src: URL, to dst: URL, name: String) throws {
        do { try FileIO.fm.copyItem(at: src, to: dst) } catch { throw FileIO.error(error) }
        let cfgFile = dst.appending(path: ProjectFormat.folderFile)
        var cfg: FolderConfig = try FileIO.readYAML(from: cfgFile)
        cfg.name = name
        try FileIO.writeYAML(cfg, to: cfgFile)
        for file in requestFiles(in: dst) {
            guard var res = try? FileIO.readYAML(Request.self, from: file).fillingSecrets(secrets) else { continue }  // poškozený nech být
            res.id = ULID.make()
            try FileIO.writeYAML(res.storingSecrets(secrets), to: file)
        }
    }

    private func requestFiles(in url: URL) -> [URL] {
        if !FileIO.isDirectory(url) { return url.lastPathComponent.hasSuffix(ProjectFormat.requestSuffix) ? [url] : [] }
        guard let elem = FileIO.fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
        return elem.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasSuffix(ProjectFormat.requestSuffix) }
    }

    private func requestIDs(in url: URL) -> [String] {
        requestFiles(in: url).compactMap { file in
            guard let res = try? FileIO.readYAML(Request.self, from: file), !res.id.isEmpty,
                !res.id.contains(where: { "/\\.".contains($0) })
            else { return nil }
            return res.id
        }
    }
}
