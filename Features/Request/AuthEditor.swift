import AppKit
import SwiftUI

/// Co by se zdědilo při `inherit` (platná auth nadřazené úrovně a popis zdroje).
struct InheritedAuth: Equatable {
    var auth: Auth
    var source: String

    /// Platná auth pro úroveň s `inherit` nad `folders` (od kořene) a projektem.
    @MainActor init(folders: [PrepareFolder], project: Auth) {
        let elem = AuthApply.effective(Auth(type: AuthType.inherit), folders: folders, project: project)
        auth = elem.auth
        if elem.source.hasPrefix(AuthApply.folderPrefix) {
            let rel = String(elem.source.dropFirst(AuthApply.folderPrefix.count))
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
        }, set: { val in
            auth.type = val
            if val == AuthType.oauth2 && auth.oauth2 == nil {
                var opt = OAuth2Auth()
                (opt.grantType, opt.clientAuth, opt.tokenPlacement, opt.autoRefresh) = (OAuthParams.clientCredentials, "header", "header", true)
                auth.oauth2 = opt
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
                                                  set: { val in update(\.apiKey, APIKeyAuth()) { $0.location = val } })) {
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
        let opt = auth.oauth2 ?? OAuth2Auth()
        grid {
            GridRow {
                Text(t("auth.oauth.grant")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { oauthGrant }, set: { val in update(\.oauth2, OAuth2Auth()) { $0.grantType = val } })) {
                    ForEach([OAuthParams.clientCredentials, OAuthParams.password], id: \.self) {
                        Text(t("auth.oauth.grant." + $0)).tag($0)
                    }
                }
                .labelsHidden().fixedSize()
            }
            row("auth.oauth.tokenURL", field(\.oauth2, OAuth2Auth(), \.tokenURL, placeholder: "{{baseUrl}}/oauth/token"))
            row("auth.oauth.clientID", field(\.oauth2, OAuth2Auth(), \.clientID))
            row("auth.oauth.clientSecret", field(\.oauth2, OAuth2Auth(), \.clientSecret), literal: opt.clientSecret, name: "clientSecret")
            row("auth.oauth.scope", field(\.oauth2, OAuth2Auth(), \.scope))
            if oauthGrant == OAuthParams.password {
                row("auth.username", field(\.oauth2, OAuth2Auth(), \.username))
                row("auth.password", field(\.oauth2, OAuth2Auth(), \.password), literal: opt.password, name: "password")
            }
            GridRow {
                Text(t("auth.oauth.clientAuth")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { opt.clientAuth == "body" ? "body" : "header" },
                                              set: { val in update(\.oauth2, OAuth2Auth()) { $0.clientAuth = val } })) {
                    Text(t("auth.oauth.clientAuth.header")).tag("header")
                    Text(t("auth.oauth.clientAuth.body")).tag("body")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            GridRow {
                Text(t("auth.oauth.placement")).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Picker("", selection: Binding(get: { opt.tokenPlacement == "query" ? "query" : "header" },
                                              set: { val in update(\.oauth2, OAuth2Auth()) { $0.tokenPlacement = val } })) {
                    Text(t("auth.location.header")).tag("header")
                    Text(t("auth.location.query")).tag("query")
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            if opt.tokenPlacement != "query" {
                row("auth.prefix", field(\.oauth2, OAuth2Auth(), \.headerPrefix, placeholder: "Bearer"))
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Toggle(t("auth.oauth.autoRefresh"), isOn: Binding(get: { opt.autoRefresh },
                                                                  set: { val in update(\.oauth2, OAuth2Auth()) { $0.autoRefresh = val } }))
            }
        }
        OAuthPanel(auth: opt, projectID: projectID, rel: oauthRel)
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
                               set: { val in update(part, empty) { $0[keyPath: key] = val } }),
                 placeholder: placeholder, font: fonts.codeNSFont)
    }

    private func update<A>(_ part: WritableKeyPath<Auth, A?>, _ empty: A, _ change: (inout A) -> Void) {
        var arg = auth
        var value = arg[keyPath: part] ?? empty
        change(&value)
        arg[keyPath: part] = value
        auth = arg
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
        var num = suggested, i = 2
        while taken.contains(num) { num = suggested + "\(i)"; i += 1 }
        return num
    }

    private func convert(_ env: EnvironmentConfig?) async {
        let num = name.trimmingCharacters(in: .whitespaces)
        guard Resolver.isValidName(num) else { error = t("auth.convertNameInvalid"); return }
        guard env?.vars.contains(where: { $0.name == num }) != true else { error = t("auth.convertNameTaken"); return }
        busy = true
        defer { busy = false }
        do {
            try await model.environments.addSecret(projectID, name: num, value: value)
            asking = false
            converted(num)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(status).foregroundStyle(.secondary)
                Spacer().frame(width: 8)
                Button(t("auth.oauth.get")) { run { par, opt, cur in _ = try await cur.fetchToken(par, options: opt) } }
                    .disabled(busy)
                Button(t("auth.oauth.refresh")) { run { par, opt, cur in _ = try await cur.refresh(par, options: opt) } }
                    .disabled(busy || info?.hasRefresh != true)
                Button(t("auth.oauth.clear")) { run { par, _, cur in try await cur.clearToken(par) } }
                    .disabled(busy || info == nil)
                if busy { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).foregroundStyle(.red).font(fonts.small).textSelection(.enabled) }
        }
        .task(id: "\(auth.hashValue)|\(model.vars.revision)") { await reload() }
    }

    private var status: String {
        guard let info else { return t("auth.oauth.state.none") }
        guard let elem = info.expiresAt else { return t("auth.oauth.state.noExpiry") }
        let when = elem.formatted(date: .abbreviated, time: .standard)
        return info.isExpired() ? t("auth.oauth.state.expired", ["when": when]) : t("auth.oauth.state.valid", ["when": when])
    }

    private func reload() async {
        guard let (par, _) = try? await model.runs.oauthParams(auth, projectID: projectID, rel: rel) else { info = nil; return }
        info = await model.runs.oauth.tokenInfo(par)
    }

    private func run(_ action: @escaping (OAuthParams, HTTPEngine.Options, OAuthClient) async throws -> Void) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let (par, opt) = try await model.runs.oauthParams(auth, projectID: projectID, rel: rel)
                try await action(par, opt, model.runs.oauth)
            } catch {
                self.error = errorText(error)
            }
            await reload()
        }
    }
}
