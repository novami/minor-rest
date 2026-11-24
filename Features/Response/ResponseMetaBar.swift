import SwiftUI

/// Meta bar odpovědi: status, čas (vodopád), velikost (rozpad), protokol, IP.
struct ResponseMetaBar: View {
    let result: RunResult
    @State private var showTiming = false
    @State private var showSizes = false
    @Environment(\.appFonts) private var fonts

    var body: some View {
        HStack(spacing: 14) {
            StatusBadge(status: result.status, text: result.statusText)
            Button(fmtMs(result.timing.totalMs)) { showTiming.toggle() }
                .popover(isPresented: $showTiming, arrowEdge: .bottom) { TimingView(timing: result.timing).padding(12) }
                .help(t("timing.total"))
            Button(fmtBytes(result.sizes.bodyDecoded)) { showSizes.toggle() }
                .popover(isPresented: $showSizes, arrowEdge: .bottom) { SizesView(sizes: result.sizes).padding(12) }
                .help(t("size.body"))
            if !result.proto.isEmpty {
                Text(result.proto).help(t("response.proto"))
            }
            if !result.remoteAddr.isEmpty {
                Text(result.remoteAddr)
                    .textSelection(.enabled)
                    .help(t("response.remote") + (result.localAddr.isEmpty ? "" : "\n" + t("response.local") + ": " + result.localAddr))
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// Barevný štítek statusu (1xx šedá … 5xx červená); tooltip = popis kódu `status.<kód>`.
struct StatusBadge: View {
    let status: Int
    let text: String
    @Environment(\.appFonts) private var fonts

    var body: some View {
        Text("\(status) \(text)")
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color, in: .rect(cornerRadius: 4))
            .help(help)
    }

    private var color: Color {
        switch status {
        case 200..<300: Color("MethodGet")
        case 300..<400: Color("MethodPut")
        case 400..<500: Color("MethodPost")
        case 500...: Color("MethodDelete")
        default: Color("MethodHead")
        }
    }

    private var help: String {
        let key = "status.\(status)"
        let str = t(key)
        return str == key ? text : str
    }
}

/// Vodopád DNS / TCP / TLS / TTFB / stahování.
struct TimingView: View {
    let timing: Timing
    private static let barWidth: CGFloat = 220

    var body: some View {
        let rows: [(String, Double, Color)] = [
            ("timing.dns", timing.dnsMs, .teal), ("timing.connect", timing.connectMs, .orange),
            ("timing.tls", timing.tlsMs, .purple), ("timing.ttfb", timing.ttfbMs, .green),
            ("timing.download", timing.downloadMs, .blue),
        ]
        let total = max(timing.totalMs, rows.reduce(0) { $0 + $1.1 }, 0.001)
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                let (key, ms, color) = rows[i]
                let offset = rows[..<i].reduce(0) { $0 + $1.1 }
                GridRow {
                    Text(t(key))
                    ZStack(alignment: .leading) {
                        Color.secondary.opacity(0.1)
                        color.frame(width: max(ms > 0 ? 2 : 0, Self.barWidth * ms / total))
                            .offset(x: Self.barWidth * offset / total)
                    }
                    .frame(width: Self.barWidth, height: 8)
                    .clipShape(.rect(cornerRadius: 2))
                    Text(fmtMs(ms)).gridColumnAlignment(.trailing)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                Text(t("timing.total")).bold()
                Color.clear.frame(width: Self.barWidth, height: 1)
                Text(fmtMs(timing.totalMs)).bold()
            }
            if timing.reused {
                GridRow {
                    Text(t("timing.reused")).foregroundStyle(.secondary).gridCellColumns(3)
                }
            }
        }
        .monospacedDigit()
    }
}

/// Rozpad velikostí: odpověď (hlavičky, tělo přenesené → dekomprimované) a request.
struct SizesView: View {
    let sizes: Sizes

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow { Text(t("size.response")).bold().gridCellColumns(2) }
            row("size.headers", fmtBytes(sizes.headers))
            row("size.body", sizes.bodyWire == sizes.bodyDecoded ? fmtBytes(sizes.bodyDecoded)
                : t("size.transferred", ["wire": fmtBytes(sizes.bodyWire), "decoded": fmtBytes(sizes.bodyDecoded)]))
            GridRow { Text(t("size.request")).bold().gridCellColumns(2) }.padding(.top, 6)
            row("size.headers", fmtBytes(sizes.reqHeaders))
            row("size.body", fmtBytes(sizes.reqBody))
        }
        .monospacedDigit()
    }

    private func row(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(t(key)).foregroundStyle(.secondary).padding(.leading, 8)
            Text(value)
        }
    }
}
