import Foundation

nonisolated extension Project {
    /// Celý strom projektu. Requesty se shodným ID (kopie z Finderu) dostanou nové ID;
    /// původní zůstane nejdříve vytvořenému souboru.
    func loadTree() throws -> TreeNode {
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
        var num = try folderNode(rel)
        if deep && num.error.isEmpty { num.children = try children(rel, deep: true) }
        return num
    }

    /// Uzel requestu; nečitelný soubor dostane `error` (kód) a název ze slugu.
    func requestNode(_ rel: String) throws -> TreeNode {
        var num = TreeNode(kind: .request, rel: rel, name: RelPath.slug(rel))
        do {
            let res: Request = try FileIO.readYAML(from: try url(rel))
            num.name = res.name
            num.seq = res.seq
            num.id = res.id
            num.method = res.method
            num.url = res.url
        } catch let elem as CoreError {
            if elem.code == .notFound { throw elem }
            num.error = elem.code.rawValue
        }
        return num
    }

    func folderNode(_ rel: String) throws -> TreeNode {
        var num = TreeNode(kind: .folder, rel: rel, name: RelPath.slug(rel))
        do {
            let cfg: FolderConfig = try FileIO.readYAML(from: try url(rel).appending(path: ProjectFormat.folderFile))
            num.name = cfg.name
            num.seq = cfg.seq
        } catch let elem as CoreError {
            if elem.code == .notFound { throw elem }
            num.error = elem.code.rawValue
        }
        return num
    }

    /// Složky (adresáře s `_folder.yaml`) a pak requesty, každé seřazené dle `seq` a názvu.
    func children(_ rel: String, deep: Bool) throws -> [TreeNode] {
        let dir = try url(rel)
        let names: [String]
        do { names = try FileIO.fm.contentsOfDirectory(atPath: dir.path).sorted() } catch { throw FileIO.error(error) }
        var folders: [TreeNode] = []
        var requests: [TreeNode] = []
        for name in names where !name.hasPrefix(".") && !name.hasPrefix("_") {
            let childRel = RelPath.join(rel, name)
            if FileIO.isDirectory(dir.appending(path: name)) {
                if rel.isEmpty && name == ProjectFormat.environmentDir { continue }
                guard var num = try? folderNode(childRel) else { continue }  // adresář bez _folder.yaml
                if deep && num.error.isEmpty { num.children = try children(childRel, deep: true) }
                folders.append(num)
            } else if name.hasSuffix(ProjectFormat.requestSuffix), let num = try? requestNode(childRel) {
                requests.append(num)
            }
        }
        return Self.sorted(folders) + Self.sorted(requests)
    }

    func siblings(_ rel: String, kind: TreeNode.Kind) throws -> [TreeNode] {
        try children(rel, deep: false).filter { $0.kind == kind }
    }

    static func sorted(_ nodes: [TreeNode]) -> [TreeNode] {
        nodes.sorted { arg, buf in
            if arg.error.isEmpty != buf.error.isEmpty { return arg.error.isEmpty }  // nečitelné na konec
            if arg.seq != buf.seq { return arg.seq < buf.seq }
            let la = arg.name.lowercased()
            let lb = buf.name.lowercased()
            return la != lb ? la < lb : arg.rel < buf.rel
        }
    }

    private func fixDuplicateIDs(_ tree: inout TreeNode) {
        var byID: [String: [String]] = [:]
        func collect(_ num: TreeNode) {
            for cur in num.children {
                if cur.kind == .request && !cur.id.isEmpty { byID[cur.id, default: []].append(cur.rel) }
                collect(cur)
            }
        }
        collect(tree)
        var replaced: [String: String] = [:]  // rel → nové ID
        for (_, rels) in byID where rels.count > 1 {
            let ordered = rels.sorted { arg, buf in
                let da = (try? url(arg)).map(FileIO.creationDate) ?? .distantPast
                let db = (try? url(buf)).map(FileIO.creationDate) ?? .distantPast
                return da != db ? da < db : arg < buf
            }
            for rel in ordered.dropFirst() {
                let id = ULID.make()
                guard let file = try? url(rel), var res = try? FileIO.readYAML(Request.self, from: file) else {
                    continue
                }
                res.id = id
                if (try? FileIO.writeYAML(res, to: file)) != nil { replaced[rel] = id }
            }
        }
        guard !replaced.isEmpty else { return }
        func apply(_ num: inout TreeNode) {
            if let id = replaced[num.rel] { num.id = id }
            for i in num.children.indices { apply(&num.children[i]) }
        }
        apply(&tree)
    }
}
