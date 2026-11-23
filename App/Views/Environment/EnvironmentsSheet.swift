import MinorRESTCore
import SwiftUI

/// Okno Prostředí (⌘E): záložky Prostředí | Proměnné projektu | Globální (PLAN 8.5). Úpravy se drží
/// v konceptu a uloží se najednou; tajné hodnoty se čtou z Keychain při otevření.
struct EnvironmentsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appFonts) private var fonts

    private struct Draft: Identifiable {
        let id = UUID()
        var env: EnvironmentConfig
    }

    private enum Tab: Hashable { case envs, project, globals }

    @State private var tab = Tab.envs
    @State private var original: EnvironmentsStore.Editable?
    @State private var drafts: [Draft] = []
    @State private var projectVars: [Var] = []
    @State private var globals: [Var] = []
    @State private var selection: UUID?
    @State private var reveal = false
    @State private var saving = false
    @State private var error: String?

    private var projectID: String { model.projects.activeID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                Text(t("envs.tab.envs")).tag(Tab.envs)
                Text(t("envs.tab.project")).tag(Tab.project)
                Text(t("envs.tab.globals")).tag(Tab.globals)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if original == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch tab {
                case .envs: environments
                case .project: single(t("envs.projectHint"), $projectVars, allowSecret: false)
                case .globals: single(t("envs.globalsHint"), $globals, allowSecret: true)
                }
            }

            if let error { Text(error).foregroundStyle(.red).font(fonts.small).textSelection(.enabled) }
            HStack {
                Toggle(t("envs.reveal"), isOn: $reveal).toggleStyle(.checkbox)
                if original?.readOnly == true { Text(t("project.readOnly")).foregroundStyle(.secondary) }
                Spacer()
                Button(t("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(t("common.save")) { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(original == nil || saving || !isDirty)
            }
        }
        .padding(16)
        .frame(width: 760, height: 520)
        .task { await load() }
    }

    // MARK: - Záložka Prostředí

    private var environments: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                List(selection: $selection) {
                    ForEach(drafts) { d in Text(d.env.name.isEmpty ? t("envs.newName") : d.env.name).tag(d.id) }
                }
                .frame(width: 190)
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }.help(t("envs.add"))
                    Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }
                        .help(t("envs.duplicate")).disabled(selectedIndex == nil)
                    Button { remove() } label: { Image(systemName: "minus") }
                        .help(t("envs.delete")).disabled(selectedIndex == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
            if let i = selectedIndex {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(t("envs.name"), text: $drafts[i].env.name).textFieldStyle(.roundedBorder)
                    ScrollView { VarsEditor(vars: $drafts[i].env.vars, allowSecret: true, reveal: reveal) }
                }
            } else {
                Text(t("envs.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func single(_ hint: String, _ vars: Binding<[Var]>, allowSecret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(fonts.small).foregroundStyle(.secondary)
            ScrollView { VarsEditor(vars: vars, allowSecret: allowSecret, reveal: reveal) }
        }
    }

    // MARK: - Akce

    private var selectedIndex: Int? { drafts.firstIndex { $0.id == selection } }

    private func add() {
        drafts.append(Draft(env: EnvironmentConfig(name: t("envs.newName"))))
        selection = drafts.last?.id
    }

    private func duplicate() {
        guard let i = selectedIndex else { return }
        var e = drafts[i].env
        e.id = ""
        e.name = t("envs.copyName", ["name": e.name])
        drafts.insert(Draft(env: e), at: i + 1)
        selection = drafts[i + 1].id
    }

    private func remove() {
        guard let i = selectedIndex else { return }
        drafts.remove(at: i)
        selection = drafts.isEmpty ? nil : drafts[min(i, drafts.count - 1)].id
    }

    private var edited: EnvironmentsStore.Editable {
        .init(environments: drafts.map(\.env), projectVars: projectVars.filter { !$0.name.isEmpty },
              globals: globals.filter { !$0.name.isEmpty }, readOnly: original?.readOnly ?? false)
    }

    private var isDirty: Bool {
        guard let o = original else { return false }
        let e = edited
        return e.environments != o.environments || e.projectVars != o.projectVars || e.globals != o.globals
    }

    private func load() async {
        do {
            let data = try await model.environments.loadEditable(projectID)
            original = data
            drafts = data.environments.map { Draft(env: $0) }
            projectVars = data.projectVars
            globals = data.globals
            selection = model.environments.active(projectID).flatMap { a in drafts.first { $0.env.id == a.id }?.id }
                ?? drafts.first?.id
        } catch {
            self.error = errorText(error)
        }
    }

    private func save() async {
        guard let original else { return }
        saving = true
        defer { saving = false }
        var edited = edited
        edited.environments = edited.environments.map { e in
            var e = e
            e.vars = e.vars.filter { !$0.name.isEmpty }
            return e
        }
        do {
            try await model.environments.saveEditable(projectID, original: original, edited: edited)
            dismiss()
        } catch {
            self.error = errorText(error)
        }
    }
}

/// Tabulka proměnných `zapnuto / název / hodnota / 🔒 / smazat`; psaní do posledního řádku přidá nový.
/// Tajná hodnota se zobrazuje jako `••••`, dokud není zapnuto „Zobrazit hodnoty“.
struct VarsEditor: View {
    @Environment(\.appFonts) private var fonts
    @Binding var vars: [Var]
    var allowSecret: Bool
    var reveal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 16, height: 1)
                Text(t("kv.name")).frame(maxWidth: .infinity, alignment: .leading)
                Text(t("kv.value")).frame(maxWidth: .infinity, alignment: .leading)
                if allowSecret { Color.clear.frame(width: 20, height: 1) }
                Color.clear.frame(width: 16, height: 1)
            }
            .font(fonts.small).foregroundStyle(.secondary)
            ForEach(0...vars.count, id: \.self) { row($0) }
        }
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let ghost = i >= vars.count
        let b = binding(i)
        HStack(spacing: 6) {
            Toggle("", isOn: b.enabled).labelsHidden().toggleStyle(.checkbox)
                .frame(width: 16).opacity(ghost ? 0 : 1).disabled(ghost)
            TextField("", text: b.name, prompt: ghost ? Text(t("kv.name")) : nil)
                .textFieldStyle(.roundedBorder).font(fonts.code)
            Group {
                if b.wrappedValue.secret && !reveal {
                    SecureField("", text: b.value).textFieldStyle(.roundedBorder).font(fonts.code)
                } else {
                    TextField("", text: b.value, prompt: ghost ? Text(t("kv.value")) : nil)
                        .textFieldStyle(.roundedBorder).font(fonts.code)
                }
            }
            if allowSecret {
                Toggle(isOn: b.secret) { Image(systemName: b.wrappedValue.secret ? "lock.fill" : "lock.open") }
                    .toggleStyle(.button).buttonStyle(.borderless)
                    .frame(width: 20).opacity(ghost ? 0 : 1).disabled(ghost)
                    .help(t("envs.secret"))
            }
            Button { vars.remove(at: i) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .frame(width: 16).opacity(ghost ? 0 : 1).disabled(ghost)
                .help(t("kv.delete"))
        }
        .opacity(b.wrappedValue.enabled || ghost ? 1 : 0.55)
    }

    /// Duch řádek se stane skutečným při prvním zápisu (stejný index → pole neztratí fokus).
    private func binding(_ i: Int) -> Binding<Var> {
        Binding(get: { i < vars.count ? vars[i] : Var() }, set: { v in
            if i < vars.count { vars[i] = v } else if v != Var() { vars.append(v) }
        })
    }
}
