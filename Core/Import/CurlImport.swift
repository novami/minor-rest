import Foundation

/// Import příkazu cURL do requestu (kap. 6): vlastní shell tokenizér + podmnožina přepínačů.
nonisolated enum CurlImport {
    /// `true` pokud text vypadá jako příkaz cURL (nabídka importu při vložení do URL baru).
    static func looksLikeCurl(_ text: String) -> Bool {
        let txt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return txt.hasPrefix("curl ") || txt.hasPrefix("curl\t") || txt.hasPrefix("curl\\")
    }

    static func parse(_ text: String) throws(CoreError) -> (Request, warnings: [String]) {
        let tokens = try tokenize(text)
        guard tokens.first == "curl" else { throw CoreError(.curlInvalid, "curl") }
        var st = CurlState()
        var i = 1
        var onlyArgs = false
        while i < tokens.count {
            let tok = tokens[i]
            if onlyArgs || !tok.hasPrefix("-") || tok == "-" {
                st.positional(tok)
            } else if tok == "--" {
                onlyArgs = true
            } else if tok.hasPrefix("--") {
                try parseLong(tok, tokens, &i, &st)
            } else {
                try parseShort(tok, tokens, &i, &st)
            }
            i += 1
        }
        return try st.build()
    }

    /// Hodnota přepínače v dalším tokenu (`i` se posune na ni).
    private static func nextValue(_ flag: String, _ tokens: [String], _ i: inout Int) throws(CoreError) -> String {
        guard i + 1 < tokens.count else { throw CoreError(.curlInvalid, flag) }
        i += 1
        return tokens[i]
    }

    private static func parseLong(
        _ tok: String, _ tokens: [String], _ i: inout Int, _ st: inout CurlState
    ) throws(CoreError) {
        var name = tok
        var inline: String?
        if let eq = tok.firstIndex(of: "=") {
            name = String(tok[..<eq])
            inline = String(tok[tok.index(after: eq)...])
        }
        guard longWithValue.contains(name) else {
            st.apply(name, nil)
            return
        }
        if let inline {
            st.apply(name, inline)
        } else {
            st.apply(name, try nextValue(name, tokens, &i))
        }
    }

    /// Sdružené krátké přepínače: `-sSL`, `-XPOST`, `-H'…'`.
    private static func parseShort(
        _ tok: String, _ tokens: [String], _ i: inout Int, _ st: inout CurlState
    ) throws(CoreError) {
        let chars = Array(tok.dropFirst())
        var key = 0
        while key < chars.count {
            let flag = "-" + String(chars[key])
            if shortWithValue.contains(chars[key]) {
                let rest = String(chars[(key + 1)...])
                if rest.isEmpty {
                    st.apply(flag, try nextValue(flag, tokens, &i))
                } else {
                    st.apply(flag, rest)
                }
                return
            }
            st.apply(flag, nil)
            key += 1
        }
    }

    // MARK: - Přepínače

    static let shortWithValue: Set<Character> = [
        "X", "H", "d", "F", "u", "A", "b", "m", "e", "o", "T", "w", "x", "c", "D", "K", "E", "z", "Y", "y"
    ]
    static let longWithValue: Set<String> = [
        "--request", "--header", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode", "--form",
        "--form-string",
        "--user", "--user-agent", "--cookie", "--max-time", "--max-redirs", "--url", "--referer", "--output",
        "--upload-file",
        "--write-out", "--proxy", "--cookie-jar", "--config", "--cert", "--key", "--cacert", "--connect-timeout",
        "--retry",
        "--limit-rate", "--resolve", "--interface", "--oauth2-bearer", "--proxy-user", "--dump-header", "--json"
    ]
    static let ignored: Set<String> = [
        "-s", "-S", "-v", "-i", "-f", "-g", "-#", "-N", "-O", "-J", "-Z", "-q", "-4", "-6",
        "--silent", "--show-error", "--verbose", "--include", "--fail", "--globoff", "--compressed", "--no-buffer",
        "--http1.0", "--http1.1",
        "--http2", "--http2-prior-knowledge", "--http3", "--tcp-nodelay", "--no-keepalive", "--tlsv1.2", "--tlsv1.3",
        "--ipv4", "--ipv6",
        "--location-trusted", "--remote-name", "--progress-bar", "--fail-with-body", "--raw", "--path-as-is",
        "--no-progress-meter"
    ]

    static func tokenize(_ text: String) throws(CoreError) -> [String] {
        var tokenizer = ShellTokenizer(text)
        return try tokenizer.run()
    }
}
