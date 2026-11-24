import MinorLog
import os

/// Loggery aplikace; do logu nikdy hlavičky Authorization/Cookie ani těla požadavků a odpovědí.
enum AppLog {
    static let app = Log.logger("App")
    static let secrets = Log.logger("Secrets")
}
