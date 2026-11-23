import MinorRESTCore
import SwiftUI

/// Dočasné zobrazení odpovědi (F4/3): stav, protokol, čas, velikost, varování a raw tělo. Plné UI v F5.
struct ResponsePane: View {
    let run: RunStore.Run
    @Environment(\.appFonts) private var fonts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if run.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("response.sending")).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header.padding(.horizontal, 10).padding(.vertical, 6)
                Divider()
                content
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = run.result, r.error == nil {
                HStack(spacing: 12) {
                    Text("\(r.status) \(r.statusText)").bold().foregroundStyle(statusColor(r.status))
                    Text(r.proto)
                    Text("\(Int(r.timing.totalMs.rounded())) ms")
                    Text(size(r.sizes.bodyDecoded))
                }
                .font(fonts.code)
            }
            if let error = run.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            if !run.unresolved.isEmpty {
                Text(t("response.unresolved", ["names": run.unresolved.joined(separator: ", ")]))
                    .foregroundStyle(.orange)
            }
            if run.result?.truncated == true {
                Text(t("response.truncated")).foregroundStyle(.orange)
            }
            if let b = run.body, b.partial {
                Text(t("response.partial", ["size": size(b.size)])).foregroundStyle(.secondary)
            }
        }
        .font(fonts.small)
    }

    @ViewBuilder private var content: some View {
        if let r = run.result, r.isBinary {
            EmptyState(title: t("response.binary", ["size": size(r.sizes.bodyDecoded)]))
        } else if let b = run.body {
            CodeTextView(text: .constant(b.text), lang: SyntaxLang(rawValue: b.lang) ?? .text,
                         editable: false, font: fonts.codeNSFont)
                .id(run.runID)
        } else {
            Spacer()
        }
    }

    private func statusColor(_ status: Int) -> Color {
        switch status {
        case 200..<300: .green
        case 300..<400: .blue
        case 400...: .red
        default: .primary
        }
    }

    private func size(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
