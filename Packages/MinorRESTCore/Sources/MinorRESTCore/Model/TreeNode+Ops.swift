import Foundation

extension TreeNode {
    /// Rodičovská cesta (`""` = kořen).
    public static func parent(of rel: String) -> String {
        rel.lastIndex(of: "/").map { String(rel[..<$0]) } ?? ""
    }

    public func find(_ rel: String) -> TreeNode? {
        if self.rel == rel { return self }
        for c in children {
            if let hit = c.find(rel) { return hit }
        }
        return nil
    }

    /// Text bez diakritiky a velikosti písmen pro hledání.
    public static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Filtr podle názvu, URL a metody (bez diakritiky a velikosti písmen): shody a jejich nadřazené složky,
    /// u shody složky celý podstrom. Kořen se vrací vždy (bez shod s prázdnými `children`).
    public func filtered(_ query: String) -> TreeNode {
        let q = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return self }
        func matches(_ n: TreeNode) -> Bool {
            if Self.fold(n.name).contains(q) { return true }
            return n.kind == .request && (Self.fold(n.url).contains(q) || Self.fold(n.method).contains(q))
        }
        func walk(_ nodes: [TreeNode]) -> [TreeNode] {
            nodes.compactMap { n in
                if matches(n) { return n }
                guard n.kind == .folder else { return nil }
                let sub = walk(n.children)
                if sub.isEmpty { return nil }
                var copy = n
                copy.children = sub
                return copy
            }
        }
        var root = self
        root.children = walk(children)
        return root
    }

    /// Index pro `Project.move` při vložení `dragged` do složky `self` před dítě na pozici `child`
    /// (index mezi všemi dětmi; `nil` = na konec). Počítá se mezi sourozenci stejného druhu bez přetahovaného
    /// uzlu. `nil` = přesun na stejné místo.
    public func moveIndex(of dragged: TreeNode, before child: Int?) -> Int? {
        let others = children.filter { $0.kind == dragged.kind && $0.rel != dragged.rel }
        var index = others.count
        if let child {
            index = children.prefix(child).filter { $0.kind == dragged.kind && $0.rel != dragged.rel }.count
        }
        if Self.parent(of: dragged.rel) == rel,
           children.filter({ $0.kind == dragged.kind }).firstIndex(where: { $0.rel == dragged.rel }) == index {
            return nil
        }
        return index
    }
}
