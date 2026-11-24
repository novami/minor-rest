import Foundation

nonisolated extension TreeNode {
    /// Rodičovská cesta (`""` = kořen).
    static func parent(of rel: String) -> String {
        rel.lastIndex(of: "/").map { String(rel[..<$0]) } ?? ""
    }

    func find(_ rel: String) -> TreeNode? {
        if self.rel == rel { return self }
        for cur in children {
            if let hit = cur.find(rel) { return hit }
        }
        return nil
    }

    /// Request podle ID (identita tabu přežije přejmenování a přesun).
    func findRequest(id: String) -> TreeNode? {
        if kind == .request && self.id == id { return self }
        for cur in children {
            if let hit = cur.findRequest(id: id) { return hit }
        }
        return nil
    }

    /// Text bez diakritiky a velikosti písmen pro hledání.
    static func fold(_ str: String) -> String {
        str.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Filtr podle názvu, URL a metody (bez diakritiky a velikosti písmen): shody a jejich nadřazené složky,
    /// u shody složky celý podstrom. Kořen se vrací vždy (bez shod s prázdnými `children`).
    func filtered(_ query: String) -> TreeNode {
        let que = Self.fold(query.trimmingCharacters(in: .whitespaces))
        guard !que.isEmpty else { return self }
        func matches(_ num: TreeNode) -> Bool {
            if Self.fold(num.name).contains(que) { return true }
            return num.kind == .request && (Self.fold(num.url).contains(que) || Self.fold(num.method).contains(que))
        }
        func walk(_ nodes: [TreeNode]) -> [TreeNode] {
            nodes.compactMap { num in
                if matches(num) { return num }
                guard num.kind == .folder else { return nil }
                let sub = walk(num.children)
                if sub.isEmpty { return nil }
                var copy = num
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
    func moveIndex(of dragged: TreeNode, before child: Int?) -> Int? {
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
