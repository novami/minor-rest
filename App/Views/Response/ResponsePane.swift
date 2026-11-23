import MinorRESTCore
import SwiftUI

/// Panel odpovědi aktivního tabu (PLAN 8.4): odesílání, chyba, nebo meta bar + záložky.
struct ResponsePane: View {
    let tabID: String
    let run: RunStore.Run
    let section: ResponseSection
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if run.running {
                sending
            } else if let r = run.result, r.error == nil {
                ResponseMetaBar(result: r).padding(.horizontal, 10).padding(.vertical, 6)
                warnings
                Divider()
                ResponseTabs(tabID: tabID, run: run, result: r, section: section)
            } else if let error = run.error {
                ErrorPanel(error: error)
                warnings
                Spacer(minLength: 0)
            }
        }
    }

    private var sending: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: run.started, by: 0.1)) { ctx in
                    Text(t("response.sending") + " "
                         + fmtMs(ctx.date.timeIntervalSince(run.started) * 1000))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button(t("request.cancel")) { model.cancelRun() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var warnings: some View {
        let items = warningTexts
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { s in
                    Label(s, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            .font(fonts.small)
            .padding(.horizontal, 10).padding(.bottom, 6)
        }
    }

    private var warningTexts: [String] {
        var out: [String] = []
        if !run.unresolved.isEmpty {
            out.append(t("response.unresolved", ["names": run.unresolved.joined(separator: ", ")]))
        }
        return out
    }
}

/// Červený panel chyby sítě/přípravy: lokalizovaná zpráva + technický detail.
struct ErrorPanel: View {
    let error: ErrorParts
    @Environment(\.appFonts) private var fonts

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(error.message).bold()
                if !error.detail.isEmpty {
                    Text(error.detail).font(fonts.small).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4)))
        .padding(10)
    }
}

/// Čísla dle jazyka UI (PLAN 8.1).
@MainActor func fmtBytes(_ n: Int64) -> String {
    DisplayFormat.bytes(n, locale: Locale(identifier: L10n.shared.code))
}

@MainActor func fmtMs(_ ms: Double) -> String {
    DisplayFormat.duration(ms: ms, locale: Locale(identifier: L10n.shared.code))
}
