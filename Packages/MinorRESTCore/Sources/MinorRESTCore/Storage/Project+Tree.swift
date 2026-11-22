import Foundation

extension Project {
    /// Celý strom projektu. Requesty se shodným ID (kopie z Finderu) dostanou nové ID;
    /// původní zůstane nejdříve vytvořenému souboru.
    public func loadTree() throws -> TreeNode {
        try locked {
            var tree = try node("", deep: true)
            if !readOnly { fixDuplicateIDs(&tree) }
            return tree
        }
    }

    func node(_ rel: String, deep: Bool) throws -> TreeNode {
        if rel.isEmpty {
            return TreeNode(kind: .folder, rel: "", name: cfg.name, children: deep ? try children("", deep: true) : [])
        }
        _ = try url(rel)
        if RelPath.kind(rel) == .request { return try requestNode(rel) }
        var n = try folderNode(rel)
        if deep && n.error.isEmpty { n.children = try children(rel, deep: true) }
        return n
    }

    /// Uzel requestu; nečitelný soubor dostane `error` (kód) a název ze slugu.
    func requestNode(_ rel: String) throws -> TreeNode {
        var n = TreeNode(kind: .request, rel: rel, name: RelPath.slug(rel))
        do {
            let r: Request = try FileIO.readYAML(from: try url(rel))
            n.name = r.name
            n.seq = r.seq
            n.id = r.id
            n.method = r.method
            n.url = r.url
        } catch let e as CoreError {
            if e.code == .notFound { throw e }
            n.error = e.code.rawValue
        }
        return n
    }

    func folderNode(_ rel: String) throws -> TreeNode {
        var n = TreeNode(kind: .folder, rel: rel, name: RelPath.slug(rel))
        do {
            let cfg: FolderConfig = try FileIO.readYAML(from: try url(rel).appending(path: ProjectFormat.folderFile))
            n.name = cfg.name
            n.seq = cfg.seq
        } catch let e as CoreError {
            if e.code == .notFound { throw e }
            n.error = e.code.rawValue
        }
        return n
    }

    /// Složky (adresáře s `_folder.yaml`) a pak requesty, každé seřazené dle `seq` a názvu.
    func children(_ rel: String, deep: Bool) throws -> [TreeNode] {
        let dir = try url(rel)
        let names: [String]
        do { names = try FileIO.fm.contentsOfDirectory(atPath: dir.path).sorted() } catch { throw FileIO.error(error) }
        var folders: [TreeNode] = [], requests: [TreeNode] = []
        for name in names where !name.hasPrefix(".") && !name.hasPrefix("_") {
            let childRel = RelPath.join(rel, name)
            if FileIO.isDirectory(dir.appending(path: name)) {
                if rel.isEmpty && name == ProjectFormat.environmentDir { continue }
                guard var n = try? folderNode(childRel) else { continue } // adresář bez _folder.yaml
                if deep && n.error.isEmpty { n.children = try children(childRel, deep: true) }
                folders.append(n)
            } else if name.hasSuffix(ProjectFormat.requestSuffix), let n = try? requestNode(childRel) {
                requests.append(n)
            }
        }
        return Self.sorted(folders) + Self.sorted(requests)
    }

    func siblings(_ rel: String, kind: TreeNode.Kind) throws -> [TreeNode] {
        try children(rel, deep: false).filter { $0.kind == kind }
    }

    static func sorted(_ nodes: [TreeNode]) -> [TreeNode] {
        nodes.sorted { a, b in
            if a.error.isEmpty != b.error.isEmpty { return a.error.isEmpty } // nečitelné na konec
            if a.seq != b.seq { return a.seq < b.seq }
            let la = a.name.lowercased(), lb = b.name.lowercased()
            return la != lb ? la < lb : a.rel < b.rel
        }
    }

    private func fixDuplicateIDs(_ tree: inout TreeNode) {
        var byID: [String: [String]] = [:]
        func collect(_ n: TreeNode) {
            for c in n.children {
                if c.kind == .request && !c.id.isEmpty { byID[c.id, default: []].append(c.rel) }
                collect(c)
            }
        }
        collect(tree)
        var replaced: [String: String] = [:] // rel → nové ID
        for (_, rels) in byID where rels.count > 1 {
            let ordered = rels.sorted { a, b in
                let da = (try? url(a)).map(FileIO.creationDate) ?? .distantPast
                let db = (try? url(b)).map(FileIO.creationDate) ?? .distantPast
                return da != db ? da < db : a < b
            }
            for rel in ordered.dropFirst() {
                let id = ULID.make()
                guard let file = try? url(rel), var r = try? FileIO.readYAML(Request.self, from: file) else { continue }
                r.id = id
                if (try? FileIO.writeYAML(r, to: file)) != nil { replaced[rel] = id }
            }
        }
        guard !replaced.isEmpty else { return }
        func apply(_ n: inout TreeNode) {
            if let id = replaced[n.rel] { n.id = id }
            for i in n.children.indices { apply(&n.children[i]) }
        }
        apply(&tree)
    }
}
