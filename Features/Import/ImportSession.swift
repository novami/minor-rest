import Foundation
import Observation

/// Stav průvodce importem OpenAPI / Swagger: zdroj → náhled → cíl.
@MainActor @Observable
final class ImportSession: Identifiable {
    enum Step { case source, preview }
    enum Target { case newProject, existing }

    let id = UUID()
    var step = Step.source
    var urlText = ""
    var spec: APISpec?
    var grouping = ImportOptions.Grouping.tag
    var target = Target.newProject
    var name = ""
    var location = Workspace.defaultProjectsDirectory
    var busy = false
    var error: String?

    var options: ImportOptions { ImportOptions(grouping: grouping, otherFolder: t("import.other")) }
    var preview: ImportPreview? { spec.map { OpenAPIImport.preview($0, options: options) } }

    /// Načte soubor nebo URL a přejde na náhled; chyba zůstane ve formuláři.
    func load(_ source: URL) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let loaded = try await OpenAPIImport.load(source: source)
            spec = loaded
            name = loaded.title
            step = .preview
        } catch {
            self.error = errorText(error)
        }
    }

    func loadURLText() async {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = URL(string: text)?.scheme?.lowercased()
        guard let url = URL(string: text), scheme == "http" || scheme == "https" else {
            error = errorText(code: "IMPORT_FETCH")
            return
        }
        await load(url)
    }

    /// Provede import; vrací počet requestů, nebo `nil` při chybě (text v `error`).
    func run(_ model: AppModel) async -> Int? {
        guard let spec else { return nil }
        busy = true
        error = nil
        defer { busy = false }
        let options = options
        do {
            switch target {
            case .newProject:
                let (name, dir, secrets) = (name, location, model.environments.secrets)
                let result = try await Task.detached {
                    try OpenAPIImport.importProject(spec, name: name, in: dir, options: options, secrets: secrets)
                }.value
                guard await model.projects.adopt(URL(fileURLWithPath: result.project.path)) else { return nil }
                model.environments.select(result.project.id, result.environmentID)
                return result.requestCount
            case .existing:
                let project = try await model.projects.project(model.projects.activeID)
                let result = try await Task.detached {
                    try OpenAPIImport.importFolder(spec, into: project, options: options)
                }.value
                await model.tree.reload()
                return result.requestCount
            }
        } catch {
            self.error = errorText(error)
            return nil
        }
    }
}
