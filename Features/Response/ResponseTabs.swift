import AppKit
import SwiftUI

/// Záložky odpovědi (PLAN 8.4): Tělo, Hlavičky, Cookies, Časování, Odesláno, Redirecty (jen pokud byly).
struct ResponseTabs: View {
    let tabID: String
    let run: RunStore.Run
    let result: RunResult
    let section: ResponseSection
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts

    var body: some View {
        let sections = ResponseSection.allCases.filter { $0 != .redirects || !result.redirects.isEmpty }
        let current = sections.contains(section) ? section : .body
        if current == .body {
            ResponseBodyPane(tabID: tabID, run: run, result: result) { bar(sections, current) }
        } else {
            VStack(spacing: 0) {
                HStack { bar(sections, current); Spacer() }
                    .frame(minHeight: 24)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                content(current)
            }
        }
    }

    private func bar(_ sections: [ResponseSection], _ current: ResponseSection) -> some View {
        HStack(spacing: 2) {
            ForEach(sections, id: \.self) { str in
                Button { model.tabs.edit { $0.responseSection = str } } label: {
                    HStack(spacing: 4) {
                        Text(t("response.tab.\(str.rawValue)"))
                        if let num = count(str), num > 0 {
                            Text("\(num)").font(fonts.small).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(current == str ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 5))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func count(_ str: ResponseSection) -> Int? {
        switch str {
        case .headers: result.headers.count
        case .cookies: result.cookies.count
        case .redirects: result.redirects.count
        case .versions:
            model.tabs.list.first(where: { $0.id == tabID }).flatMap { model.runs.versions[RunStore.key($0.projectID, $0.draft.id)]?.count }
        default: nil
        }
    }

    @ViewBuilder private func content(_ str: ResponseSection) -> some View {
        switch str {
        case .body: EmptyView()
        case .headers: HeaderTable(rows: result.headers, empty: t("response.headers.none"))
        case .cookies: CookieTable(cookies: result.cookies)
        case .timing: ScrollView { TimingDetail(result: result).padding(12) }
        case .sent: SentView(sent: result.sent)
        case .redirects: RedirectList(redirects: result.redirects)
        case .versions:
            if let tab = model.tabs.list.first(where: { $0.id == tabID }) {
                VersionsView(tabID: tabID, projectID: tab.projectID, requestID: tab.draft.id)
            }
        }
    }
}

@MainActor func copyText(_ str: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(str, forType: .string)
}

/// Tabulka hlaviček; ⌘C kopíruje hodnoty vybraných řádků, kontextové menu i celé řádky.
struct HeaderTable: View {
    let rows: [KV]
    let empty: String
    @State private var selection = Set<Int>()
    @Environment(\.appFonts) private var fonts

    private struct Row: Identifiable {
        let id: Int
        let name: String
        let value: String
    }

    var body: some View {
        if rows.isEmpty {
            EmptyState(title: empty)
        } else {
            Table(rows.enumerated().map { Row(id: $0.offset, name: $0.element.name, value: $0.element.value) },
                  selection: $selection) {
                TableColumn(t("response.col.name")) { Text($0.name).font(fonts.code) }
                    .width(min: 80, ideal: 200, max: 400)
                TableColumn(t("response.col.value")) { Text($0.value).font(fonts.code).help($0.value) }
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if !ids.isEmpty {
                    Button(t("response.copyValue")) { copyText(text(ids) { $0.value }) }
                    Button(t("response.copyRow")) { copyText(text(ids) { "\($0.name): \($0.value)" }) }
                }
            }
            .onCopyCommand { selection.isEmpty ? [] : [NSItemProvider(object: text(selection) { $0.value } as NSString)] }
        }
    }

    private func text(_ ids: Set<Int>, _ line: (KV) -> String) -> String {
        ids.sorted().filter { $0 < rows.count }.map { line(rows[$0]) }.joined(separator: "\n")
    }
}

/// Cookies z `Set-Cookie` odpovědi (i ze skoků redirectu).
struct CookieTable: View {
    let cookies: [Cookie]
    @State private var selection = Set<Int>()
    @Environment(\.appFonts) private var fonts

    private struct Row: Identifiable {
        let id: Int
        let cur: Cookie
    }

    var body: some View {
        if cookies.isEmpty {
            EmptyState(title: t("response.cookies.none"))
        } else {
            Table(cookies.enumerated().map { Row(id: $0.offset, cur: $0.element) }, selection: $selection) {
                TableColumn(t("response.col.name")) { Text($0.cur.name).font(fonts.code) }
                    .width(min: 60, ideal: 120)
                TableColumn(t("response.col.value")) { Text($0.cur.value).font(fonts.code).help($0.cur.value) }
                    .width(min: 80, ideal: 200)
                TableColumn(t("cookie.domain")) { Text($0.cur.domain) }.width(min: 60, ideal: 120)
                TableColumn(t("cookie.path")) { Text($0.cur.path) }.width(min: 30, ideal: 50)
                TableColumn(t("cookie.expires")) { Text(expires($0.cur.expires)) }.width(min: 60, ideal: 140)
                TableColumn(t("cookie.flags")) { Text(flags($0.cur)) }.width(min: 60, ideal: 160)
            }
            .contextMenu(forSelectionType: Int.self) { ids in
                if !ids.isEmpty {
                    Button(t("response.copyValue")) { copyText(values(ids)) }
                }
            }
            .onCopyCommand { selection.isEmpty ? [] : [NSItemProvider(object: values(selection) as NSString)] }
        }
    }

    private func values(_ ids: Set<Int>) -> String {
        ids.sorted().filter { $0 < cookies.count }.map { cookies[$0].value }.joined(separator: "\n")
    }

    private func expires(_ str: String) -> String {
        guard !str.isEmpty else { return t("cookie.session") }
        guard let dat = try? Date(str, strategy: .iso8601) else { return str }
        return dat.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: L10n.shared.code)))
    }

    private func flags(_ cur: Cookie) -> String {
        [cur.secure ? "Secure" : nil, cur.httpOnly ? "HttpOnly" : nil, cur.sameSite.isEmpty ? nil : "SameSite=\(cur.sameSite)"]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// Záložka Časování: vodopád, spojení (protokol, adresy) a detail TLS.
struct TimingDetail: View {
    let result: RunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimingView(timing: result.timing)
            section("response.connection", [
                ("response.proto", result.proto), ("response.remote", result.remoteAddr),
                ("response.local", result.localAddr),
            ])
            if let tls = result.tls {
                section("tls.title", [
                    ("tls.version", tls.version), ("tls.cipher", tls.cipher), ("tls.serverName", tls.serverName),
                    ("tls.subject", tls.subject), ("tls.issuer", tls.issuer), ("tls.notAfter", tls.notAfter),
                ])
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        let shown = rows.filter { !$0.1.isEmpty }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(t(title)).bold()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(shown, id: \.0) { key, value in
                        GridRow {
                            Text(t(key)).foregroundStyle(.secondary)
                            Text(value)
                        }
                    }
                }
            }
        }
    }
}

/// Záložka Odesláno: metoda + URL, hlavičky a začátek těla, jak je odeslal URLSession.
struct SentView: View {
    let sent: SentRequest
    @Environment(\.appFonts) private var fonts

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(sent.method).bold()
                Text(sent.url).lineLimit(1).truncationMode(.middle).help(sent.url)
            }
            .font(fonts.code)
            .textSelection(.enabled)
            .padding(.horizontal, 10).padding(.bottom, 6)
            if sent.bodySize > 0 {
                VSplitView {
                    HeaderTable(rows: sent.headers, empty: t("response.headers.none")).frame(minHeight: 80)
                    sentBody.frame(minHeight: 60)
                }
            } else {
                HeaderTable(rows: sent.headers, empty: t("response.headers.none"))
            }
            Text(t("response.sent.note"))
                .font(fonts.small).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 4)
        }
    }

    @ViewBuilder private var sentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t(Int64(sent.bodyPreview.utf8.count) < sent.bodySize ? "response.sent.bodyPartial" : "response.sent.body",
                   ["size": fmtBytes(sent.bodySize)]))
                .font(fonts.small).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
            if sent.bodyPreview.isEmpty {
                EmptyState(title: t("response.sent.noPreview"))
            } else {
                CodeTextView(text: .constant(sent.bodyPreview), lang: lang, editable: false, font: fonts.codeNSFont)
            }
        }
    }

    private var lang: SyntaxLang {
        let ct = sent.headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value.lowercased() ?? ""
        if ct.contains("json") { return .json }
        if ct.contains("html") { return .html }
        if ct.contains("xml") { return .xml }
        return .text
    }
}

/// Skoky redirectu v pořadí: status, metoda, URL → Location.
struct RedirectList: View {
    let redirects: [Redirect]
    @Environment(\.appFonts) private var fonts

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(redirects.indices, id: \.self) { i in
                    let res = redirects[i]
                    GridRow(alignment: .firstTextBaseline) {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        StatusBadge(status: res.status, text: HTTPStatus.text(res.status))
                        Text(res.method).font(fonts.code).bold()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(res.url)
                            Text("→ " + res.location).foregroundStyle(.secondary)
                        }
                        .font(fonts.code)
                        .textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
