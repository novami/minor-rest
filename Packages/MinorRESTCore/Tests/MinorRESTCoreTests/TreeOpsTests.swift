import Testing
@testable import MinorRESTCore

private let tree = TreeNode(kind: .folder, rel: "", name: "P", children: [
    TreeNode(kind: .folder, rel: "uzivatele", name: "Uživatelé", children: [
        TreeNode(kind: .request, rel: "uzivatele/seznam.req.yaml", name: "Seznam", method: "GET", url: "{{base}}/users"),
        TreeNode(kind: .request, rel: "uzivatele/smaz.req.yaml", name: "Smaž", method: "DELETE"),
    ]),
    TreeNode(kind: .folder, rel: "objednavky", name: "Objednávky", children: [
        TreeNode(kind: .request, rel: "objednavky/list.req.yaml", name: "Výpis", method: "GET"),
    ]),
    TreeNode(kind: .request, rel: "login.req.yaml", name: "Přihlášení", method: "POST"),
    TreeNode(kind: .request, rel: "health.req.yaml", name: "Health", method: "HEAD"),
])

private func rels(_ n: TreeNode) -> [String] { n.children.flatMap { [$0.rel] + rels($0) } }

@Test(arguments: [
    ("", 7),
    ("UZIVATEL", 3),          // shoda složky = celý podstrom
    ("smaz", 2),              // bez diakritiky, s nadřazenou složkou
    ("/users", 2),            // URL
    ("head", 1),              // metoda
    ("nic", 0),
])
func treeFilter(query: String, count: Int) {
    #expect(rels(tree.filtered(query)).count == count)
}

@Test func treeMoveIndex() {
    let login = tree.children[2], health = tree.children[3], folder = tree.children[1]
    // na stejné místo → nil
    #expect(tree.moveIndex(of: login, before: 2) == nil)
    #expect(tree.moveIndex(of: login, before: 3) == nil)
    // za health
    #expect(tree.moveIndex(of: login, before: nil) == 1)
    // před první složku (mezi requesty = 0)
    #expect(tree.moveIndex(of: health, before: 0) == 0)
    // složka před první složku
    #expect(tree.moveIndex(of: folder, before: 0) == 0)
    // do jiné složky na konec
    #expect(tree.children[0].moveIndex(of: login, before: nil) == 2)
}
