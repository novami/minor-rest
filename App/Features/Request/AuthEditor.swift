import AppKit
import MinorRESTCore
import SwiftUI

/// Co by se zdědilo při `inherit` (platná auth nadřazené úrovně a popis zdroje).
struct InheritedAuth: Equatable {
    var auth: Auth
    var source: String

    /// Platná auth pro úroveň s `inherit` nad `folders` (od kořene) a projektem.
    @MainActor init(folders: [PrepareFolder], project: Auth) {
        let e = AuthApply.effective(Auth(type: AuthType.inherit), folders: folders, project: project)
        auth = e.auth
        if e.source.hasPrefix(AuthApply.folderPrefix) {
            let rel = String(e.source.dropFirst(AuthApply.folderPrefix.count))
            let name = folders.first { $0.rel == rel }?.config.name ?? ""
            source = t("auth.source.folder", ["name": name.isEmpty ? (rel as NSString).lastPathComponent : name])
        } else {
            source = t("auth.source.project")
        }
    }
}

enum AuthScope { case request, folder, project }

/// Záložka Auth (request, složka, projekt): typ, pole typu (s proměnnými), u `inherit` odkud se dědí,
/// varování u hodnot zapsaných přímo s převodem na tajnou proměnnou aktivního prostředí.
struct AuthEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    @Binding var auth: Auth
    let scope: AuthScope
    let projectID: String
    /// `nil` = ještě nenačteno.
    var inherited: InheritedAuth?
    /// Vlastní zapnutá hlavička `Authorization` na téže úrovni (má přednost).
    var manualAuthorization = false
    /// Cesta, od které se pro proměnné skládají složky (request: jeho cesta, složka: `<složka>/_`, projekt: nil).
    var oauthRel: String?

    private var types: [String] {
        var all = [AuthType.none, AuthType.basic, AuthType.bearer, AuthType.apiKey, AuthType.oauth2]
        if scope != .project { all.insert(AuthType.inherit, at: 0) }
        return all
    }

    private var type: Binding<String> {
        Binding(get: {
            AuthApply.isInherit(auth) ? (scope == .project ? AuthType.none : AuthType.inherit) : auth.type
        }, set: { v in
            auth.type = v
            if v == AuthType.oauth2 && auth.oauth2 == nil {
                var o = OAuth2Auth()
                (o.grantType, o.clientAuth, o.tokenPlacement, o.autoRefresh) = (OAuthParams.clientCredentials, "header", "header", true)
                auth.oauth2 = o
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(t("auth.type"), selection: type) {
                ForEach(types, id: \.self) { Text(Self.typeLabel($0)).tag($0) }
            }
            .fixedSize()
            fields
            if manualAuthorization && [AuthType.basic, AuthType.bearer, AuthType.oauth2].contains(auth.type) {
                Label(t("auth.manualHeader"), systemImage: "info.circle")
                    .font(fonts.small).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func typeLabel(_ type: String) -> String {
        t("auth.type." + (type.isEmpty ? AuthType.inherit : type))
    }

    @ViewBuilder
    private var fields: some View {
        switch type.wrappedValue {
        case AuthType.inherit:
            Text(inherited.map { t("auth.inheritFrom", ["type": Self.typeLabel($0.auth.type), "source": $0.source]) } ?? " ")
                .foregroundStyle(.secondary)
        case AuthType.none:
            Text(t("auth.noneHint")).foregroundStyle(.secondary)
        case AuthType.basic:
            grid {
                row("auth.username", field(\.basic, BasicAuth(), \.username))
                row("auth.password", field(\.basic, BasicAuth(), \.password), literal: auth.basic?.password, name: "password")
            }
        case AuthType.bearer:
            grid {
                row("auth.token", field(\.bearer, BearerAuth(), \.token), literal: auth.bearer?.token, name: "token")
                row("auth.prefix", field(\.bearer, BearerAuth(), \.prefix, placeholder: "Bearer"))
            }
        case AuthType.apiKey:
            grid {
                row("auth.key", field(\.apiKey, APIKeyAuth(), \.key, placeholder: "X-API-Key"))
                row("auth.value", field(\.apiKey, APIKeyAuth(), \.value), literal: auth.apiKey?.value, name: "apiKey")
                GridRow {
                    Text(t("auth.location")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Picker("", selection: Binding(get: { auth.apiKey?.location == "query" ? "query" : "header" },
                                                  set: { v in update(\.apiKey, APIKeyAuth()) { $0.location = v } })) {
                        Text(t("auth.location.header")).tag("header")
                        Text(t("auth.location.query")).tag("query")
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        default:
            oauthFields
        }
    }

    private var oauthGrant: String { auth.oauth2?.grantType.isEmpty == false ? auth.oauth2!.grantType : OAuthParams.clientCredentials }

    @ViewBuilder
    private var oauthFields: some View {
        let o = auth.oauth2 ?? OAuth2Auth()
        grid {
            GridRow {
                Text(t("auth.oauth.grant")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { oauthGrant }, set: { v in update(\.oauth2, OAuth2Auth()) { $0.grantType = v } })) {
                    ForEach([OAuthParams.clientCredentials, OAuthParams.password, OAuthParams.authorizationCode], id: \.self) {
                        Text(t("auth.oauth.grant." + $0)).tag($0)
                    }
                }
                .labelsHidden().fixedSize()
            }
            if oauthGrant == OAuthParams.authorizationCode {
                row("auth.oauth.authURL", field(\.oauth2, OAuth2Auth(), \.authURL, placeholder: "{{baseUrl}}/oauth/authorize"))
            }
            row("auth.oauth.tokenURL", field(\.oauth2, OAuth2Auth(), \.tokenURL, placeholder: "{{baseUrl}}/oauth/token"))
            row("auth.oauth.clientID", field(\.oauth2, OAuth2Auth(), \.clientID))
            row("auth.oauth.clientSecret", field(\.oauth2, OAuth2Auth(), \.clientSecret), literal: o.clientSecret, name: "clientSecret")
            row("auth.oauth.scope", field(\.oauth2, OAuth2Auth(), \.scope))
            if oauthGrant == OAuthParams.authorizationCode {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle(t("auth.oauth.pkce"), isOn: Binding(get: { o.usePKCE },
                                                               set: { v in update(\.oauth2, OAuth2Auth()) { $0.usePKCE = v } }))
                }
                GridRow {
                    Text(t("auth.oauth.port")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("0", value: Binding(get: { o.redirectPort },
                                                  set: { v in update(\.oauth2, OAuth2Auth()) { $0.redirectPort = min(max(v, 0), 65535) } }),
                              format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                        .help(t("auth.oauth.portHelp"))
                }
            }
            if oauthGrant == OAuthParams.password {
                row("auth.username", field(\.oauth2, OAuth2Auth(), \.username))
                row("auth.password", field(\.oauth2, OAuth2Auth(), \.password), literal: o.password, name: "password")
            }
            GridRow {
                Text(t("auth.oauth.clientAuth")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { o.clientAuth == "body" ? "body" : "header" },
                                              set: { v in update(\.oauth2, OAuth2Auth()) { $0.clientAuth = v } })) {
                    Text(t("auth.oauth.clientAuth.header")).tag("header")
                    Text(t("auth.oauth.clientAuth.body")).tag("body")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            GridRow {
                Text(t("auth.oauth.placement")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { o.tokenPlacement == "query" ? "query" : "header" },
                                              set: { v in update(\.oauth2, OAuth2Auth()) { $0.tokenPlacement = v } })) {
                    Text(t("auth.location.header")).tag("header")
                    Text(t("auth.location.query")).tag("query")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            if o.tokenPlacement != "query" {
                row("auth.prefix", field(\.oauth2, OAuth2Auth(), \.headerPrefix, placeholder: "Bearer"))
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Toggle(t("auth.oauth.autoRefresh"), isOn: Binding(get: { o.autoRefresh },
                                                                  set: { v in update(\.oauth2, OAuth2Auth()) { $0.autoRefresh = v } }))
            }
        }
        OAuthPanel(auth: o, projectID: projectID, rel: oauthRel)
    }

    private func grid(@ViewBuilder _ rows: () -> some View) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) { rows() }
    }

    @ViewBuilder
    private func row(_ key: String, _ field: some View, literal: String? = nil, name: String = "") -> some View {
        GridRow {
            Text(t(key)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            field.frame(maxWidth: 480)
        }
        if let literal, AuthApply.isLiteral(literal) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                LiteralWarning(projectID: projectID, value: literal, suggested: name) { newName in
                    replaceLiteral(literal, with: "{{\(newName)}}")
                }
            }
        }
    }

    private func field<A: Equatable>(_ part: WritableKeyPath<Auth, A?>, _ empty: A, _ key: WritableKeyPath<A, String>,
                                     placeholder: String = "") -> some View {
        VarField(text: Binding(get: { auth[keyPath: part]?[keyPath: key] ?? "" },
                               set: { v in update(part, empty) { $0[keyPath: key] = v } }),
                 placeholder: placeholder, font: fonts.codeNSFont)
    }

    private func update<A>(_ part: WritableKeyPath<Auth, A?>, _ empty: A, _ change: (inout A) -> Void) {
        var a = auth
        var value = a[keyPath: part] ?? empty
        change(&value)
        a[keyPath: part] = value
        auth = a
    }

    private func replaceLiteral(_ old: String, with new: String) {
        switch auth.type {
        case AuthType.basic: update(\.basic, BasicAuth()) { if $0.password == old { $0.password = new } }
        case AuthType.bearer: update(\.bearer, BearerAuth()) { if $0.token == old { $0.token = new } }
        case AuthType.apiKey: update(\.apiKey, APIKeyAuth()) { if $0.value == old { $0.value = new } }
        case AuthType.oauth2:
            update(\.oauth2, OAuth2Auth()) {
                if $0.clientSecret == old { $0.clientSecret = new }
                if $0.password == old { $0.password = new }
            }
        default: break
        }
    }
}

/// „Hodnota je uložena jako prostý text“ + popover s názvem nové tajné proměnné v aktivním prostředí.
private struct LiteralWarning: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    let projectID: String
    let value: String
    let suggested: String
    let converted: (String) -> Void

    @State private var asking = false
    @State private var name = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        let env = model.environments.active(projectID)
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(t("auth.literalWarning")).foregroundStyle(.secondary).fixedSize()
            Button(t("auth.convert")) {
                name = uniqueName(env)
                error = nil
                asking = true
            }
            .disabled(env == nil)
            .help(env == nil ? t("auth.convertNoEnv") : "")
            .popover(isPresented: $asking, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("auth.convertTitle", ["env": env?.name ?? ""])).font(.headline)
                    TextField(t("auth.convertName"), text: $name)
                        .textFieldStyle(.roundedBorder).frame(width: 260)
                        .onSubmit { Task { await convert(env) } }
                    if let error { Text(error).foregroundStyle(.red).font(fonts.small) }
                    HStack {
                        Spacer()
                        Button(t("common.cancel")) { asking = false }.keyboardShortcut(.cancelAction)
                        Button(t("auth.convertOK")) { Task { await convert(env) } }
                            .keyboardShortcut(.defaultAction).disabled(busy)
                    }
                }
                .padding(12)
            }
        }
        .font(fonts.small)
    }

    private func uniqueName(_ env: EnvironmentConfig?) -> String {
        let taken = Set(env?.vars.map(\.name) ?? [])
        var n = suggested, i = 2
        while taken.contains(n) { n = suggested + "\(i)"; i += 1 }
        return n
    }

    private func convert(_ env: EnvironmentConfig?) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard Resolver.isValidName(n) else { error = t("auth.convertNameInvalid"); return }
        guard env?.vars.contains(where: { $0.name == n }) != true else { error = t("auth.convertNameTaken"); return }
        busy = true
        defer { busy = false }
        do {
            try await model.environments.addSecret(projectID, name: n, value: value)
            asking = false
            converted(n)
        } catch {
            self.error = errorText(error)
        }
    }
}

/// Stav tokenu OAuth2 a akce Získat / Obnovit / Smazat (PLAN 8.5).
private struct OAuthPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appFonts) private var fonts
    let auth: OAuth2Auth
    let projectID: String
    let rel: String?

    @State private var info: TokenInfo?
    @State private var error: String?
    @State private var busy = false

    private var grant: String { auth.grantType.isEmpty ? OAuthParams.clientCredentials : auth.grantType }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(status).foregroundStyle(.secondary)
                Spacer().frame(width: 8)
                if grant == OAuthParams.authorizationCode {
                    if busy {
                        Button(t("common.cancel")) { Task { await model.runs.oauth.cancelLogin() } }
                    } else {
                        Button(t("auth.oauth.login")) {
                            run { p, o, c in _ = try await c.login(p, options: o) { url in NSWorkspace.shared.open(url) } }
                        }
                    }
                } else {
                    Button(t("auth.oauth.get")) { run { p, o, c in _ = try await c.fetchToken(p, options: o) } }
                        .disabled(busy)
                }
                Button(t("auth.oauth.refresh")) { run { p, o, c in _ = try await c.refresh(p, options: o) } }
                    .disabled(busy || info?.hasRefresh != true)
                Button(t("auth.oauth.clear")) { run { p, _, c in try await c.clearToken(p) } }
                    .disabled(busy || info == nil)
                if busy && grant == OAuthParams.authorizationCode {
                    Text(t("auth.oauth.waiting")).foregroundStyle(.secondary)
                }
                if busy { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).foregroundStyle(.red).font(fonts.small).textSelection(.enabled) }
        }
        .task(id: "\(auth.hashValue)|\(model.vars.revision)") { await reload() }
    }

    private var status: String {
        guard let info else { return t("auth.oauth.state.none") }
        guard let e = info.expiresAt else { return t("auth.oauth.state.noExpiry") }
        let when = e.formatted(date: .abbreviated, time: .standard)
        return info.isExpired() ? t("auth.oauth.state.expired", ["when": when]) : t("auth.oauth.state.valid", ["when": when])
    }

    private func reload() async {
        guard let (p, _) = try? await model.runs.oauthParams(auth, projectID: projectID, rel: rel) else { info = nil; return }
        info = await model.runs.oauth.tokenInfo(p)
    }

    private func run(_ action: @escaping (OAuthParams, HTTPEngine.Options, OAuthClient) async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let (p, o) = try await model.runs.oauthParams(auth, projectID: projectID, rel: rel)
                try await action(p, o, model.runs.oauth)
            } catch {
                self.error = errorText(error)
            }
            await reload()
        }
    }
}
