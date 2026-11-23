import MinorRESTCore
import SwiftUI

/// Tabulka `název / hodnota / popis` (query, path, headers…): psaní do posledního („duch“) řádku přidá řádek,
/// pořadí se mění přetažením za úchyt, Hromadná úprava = text `název: hodnota` (`//` = vypnutý).
/// `fixed` = path parametry (názvy z URL: bez přidávání, mazání, vypínání a přetahování).
/// Hromadná úprava jen pro `KV`; `valueCell` nahradí pole hodnoty (multipart: text/soubor).
struct KvEditor<Row: KvRow>: View {
    @Environment(\.appFonts) private var fonts
    var title: String?
    @Binding var rows: [Row]
    var fixed = false
    var allowBare = false
    var names: [String] = []
    var valuesFor: ((String) -> [String])?
    var noteTitle = t("kv.description")
    var valueCell: ((Binding<Row>, _ ghost: Bool) -> AnyView)?

    @State private var bulk: String?
    @State private var bulkBase: [KV] = []
    @State private var dragging: Int?
    @State private var dropLine: Int?


    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            toolbar
            if let bulk {
                TextEditor(text: Binding(get: { bulk }, set: { text in
                    self.bulk = text
                    rows = KVBulk.parse(text, prev: bulkBase + (rows as? [KV] ?? []), allowBare: allowBare) as? [Row] ?? rows
                }))
                .font(fonts.code)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                Text(t("kv.bulkHint")).font(fonts.small).foregroundStyle(.secondary)
            } else {
                header
                ForEach(0..<(rows.count + (fixed ? 0 : 1)), id: \.self) { i in
                    row(i)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            if let title { Text(title).font(fonts.ui.bold()) }
            Spacer()
            if !fixed, Row.self == KV.self {
                Button(bulk == nil ? t("kv.bulk") : t("kv.table")) {
                    if bulk == nil {
                        bulkBase = rows as? [KV] ?? []
                        bulk = KVBulk.text(bulkBase)
                    } else {
                        bulk = nil
                    }
                }
                .buttonStyle(.link)
                .font(fonts.small)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if !fixed { Color.clear.frame(width: 34, height: 1) }
            Text(t("kv.name")).frame(maxWidth: .infinity, alignment: .leading)
            Text(t("kv.value")).frame(maxWidth: .infinity, alignment: .leading)
            Text(noteTitle).frame(maxWidth: .infinity, alignment: .leading)
            if !fixed { Color.clear.frame(width: 16, height: 1) }
        }
        .font(fonts.small)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ i: Int) -> some View {
        let ghost = i >= rows.count
        let r = binding(i)
        HStack(spacing: 6) {
            if !fixed {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                    .opacity(ghost ? 0 : 1)
                    .help(t("kv.drag"))
                    .onDrag {
                        dragging = i
                        return NSItemProvider(object: "minorrest-kv-\(i)" as NSString)
                    }
                Toggle("", isOn: r.enabled).labelsHidden().toggleStyle(.checkbox)
                    .frame(width: 16).opacity(ghost ? 0 : 1).disabled(ghost)
            }
            if fixed {
                Text(r.wrappedValue.name).font(fonts.code)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VarField(text: r.name, placeholder: ghost ? t("kv.name") : "", font: fonts.codeNSFont,
                         completions: names.isEmpty ? nil : { HeaderHints.complete($0, in: names) })
                    .frame(maxWidth: .infinity)
            }
            Group {
                if let valueCell {
                    valueCell(r, ghost)
                } else {
                    VarField(text: r.value, placeholder: ghost ? t("kv.value") : "", font: fonts.codeNSFont,
                             completions: valuesFor.map { f in { [name = r.wrappedValue.name] in HeaderHints.complete($0, in: f(name)) } })
                }
            }
            .frame(maxWidth: .infinity)
            TextField("", text: r.note, prompt: ghost ? Text(noteTitle) : nil)
                .textFieldStyle(.roundedBorder)
                .font(fonts.ui)
                .frame(maxWidth: .infinity)
            if !fixed {
                Button { rows.remove(at: i) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                    .help(t("kv.delete"))
                    .opacity(ghost ? 0 : 1)
                    .disabled(ghost)
            }
        }
        .frame(height: kvRowHeight)
        .opacity(r.wrappedValue.enabled || ghost ? 1 : 0.55)
        .overlay(alignment: .top) { dropIndicator(i) }
        .overlay(alignment: .bottom) { if i == rows.count - 1 { dropIndicator(rows.count) } }
        .onDrop(of: [.text], delegate: RowDrop(index: i, count: rows.count, height: kvRowHeight,
                                               dragging: $dragging, line: $dropLine, move: move))
    }

    @ViewBuilder
    private func dropIndicator(_ line: Int) -> some View {
        if dropLine == line {
            Rectangle().fill(Color.accentColor).frame(height: 2).offset(y: line == rows.count ? 1 : -1)
        }
    }

    /// Duch řádek se stane skutečným při prvním neprázdném zápisu (stejný index → pole neztratí fokus).
    private func binding(_ i: Int) -> Binding<Row> {
        Binding(get: { i < rows.count ? rows[i] : Row() }, set: { v in
            if i < rows.count { rows[i] = v } else if v != Row() { rows.append(v) }
        })
    }

    /// Přesun řádku `from` před pozici `line` (0…count).
    private func move(_ from: Int, _ line: Int) {
        guard from < rows.count, line != from, line != from + 1 else { return }
        rows.move(fromOffsets: [from], toOffset: line)
    }
}

/// Řádek tabulky; `note` = třetí sloupec (popis, u multipart Content-Type).
private let kvRowHeight: CGFloat = 26

protocol KvRow: Equatable {
    init()
    var name: String { get set }
    var value: String { get set }
    var enabled: Bool { get set }
    var note: String { get set }
}

extension KV: KvRow {
    init() { self.init(name: "") }
    var note: String {
        get { description }
        set { description = newValue }
    }
}

extension MultipartPart: KvRow {
    init() { self.init(name: "") }
    var note: String {
        get { contentType }
        set { contentType = newValue }
    }
}

/// Přetažení řádku: horní polovina řádku = čára před ním, dolní = za ním (jen řádky tohoto editoru).
private struct RowDrop: DropDelegate {
    let index: Int
    let count: Int
    let height: CGFloat
    @Binding var dragging: Int?
    @Binding var line: Int?
    let move: (Int, Int) -> Void

    private func target(_ info: DropInfo) -> Int {
        min(info.location.y < height / 2 ? index : index + 1, count)
    }

    func validateDrop(info: DropInfo) -> Bool { dragging != nil && index <= count }

    func dropEntered(info: DropInfo) { line = target(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        line = target(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { line = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; line = nil }
        guard let from = dragging else { return false }
        move(from, target(info))
        return true
    }
}
