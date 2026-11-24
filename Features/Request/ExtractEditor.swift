import SwiftUI

/// Pravidla `extract`: `zapnuto / název / zdroj (tělo | hlavička) / JSONPath nebo název hlavičky / smazat`.
struct ExtractEditor: View {
    @Environment(\.appFonts) private var fonts
    @Binding var rules: [Extract]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 16, height: 1)
                Text(t("kv.name")).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 110, height: 1)
                Text(t("extract.path")).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 16, height: 1)
            }
            .font(fonts.small).foregroundStyle(.secondary)
            ForEach(0...rules.count, id: \.self) { row($0) }
        }
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let ghost = i >= rules.count
        let buf = binding(i)
        HStack(spacing: 6) {
            Toggle("", isOn: buf.enabled).labelsHidden().toggleStyle(.checkbox)
                .frame(width: 16).opacity(ghost ? 0 : 1).disabled(ghost)
            TextField("", text: buf.name, prompt: ghost ? Text(t("kv.name")) : nil)
                .textFieldStyle(.roundedBorder).font(fonts.code)
            Picker("", selection: buf.from) {
                Text(t("extract.body")).tag("body")
                Text(t("extract.header")).tag("header")
            }
            .labelsHidden().frame(width: 110)
            TextField(
                "", text: buf.path,
                prompt: Text(buf.wrappedValue.from == "header" ? "Location" : "$.data.token")
            )
            .textFieldStyle(.roundedBorder).font(fonts.code)
            Button {
                rules.remove(at: i)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .frame(width: 16).opacity(ghost ? 0 : 1).disabled(ghost)
            .help(t("kv.delete"))
        }
        .opacity(buf.wrappedValue.enabled || ghost ? 1 : 0.55)
    }

    /// Duch řádek se stane skutečným při prvním zápisu.
    private func binding(_ i: Int) -> Binding<Extract> {
        Binding(
            get: { i < rules.count ? rules[i] : Extract() },
            set: { res in
                if i < rules.count { rules[i] = res } else if res != Extract() { rules.append(res) }
            })
    }
}
