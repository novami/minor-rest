import CryptoKit
import Foundation
import Network
import Synchronization

/// Lokální HTTP server pro přesměrování authorization code (`127.0.0.1:<port>/callback`).
final class OAuthCallbackServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "oauth-callback")
    let port: UInt16
    /// Parametry každého volání `/callback`.
    let callbacks: AsyncStream<[String: String]>
    private let sink: AsyncStream<[String: String]>.Continuation

    init(port: UInt16) async throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let l = try NWListener(using: params)
        (callbacks, sink) = AsyncStream.makeStream()
        let sink = sink, queue = queue
        l.newConnectionHandler = { c in
            c.start(queue: queue)
            Self.receive(c, Data(), sink)
        }
        let ready = AsyncStream<UInt16> { cont in
            l.stateUpdateHandler = { st in
                if case .ready = st { cont.yield(l.port?.rawValue ?? 0); cont.finish() }
                if case .failed = st { cont.yield(0); cont.finish() }
            }
        }
        l.start(queue: queue)
        var p: UInt16 = 0
        for await v in ready { p = v }
        guard p != 0 else {
            l.cancel()
            throw CoreError(.netError, "127.0.0.1:\(port)")
        }
        listener = l
        self.port = p
    }

    func stop() {
        listener.cancel()
        sink.finish()
    }

    private static func receive(_ c: NWConnection, _ buf: Data, _ sink: AsyncStream<[String: String]>.Continuation) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 14) { data, _, done, err in
            var buf = buf
            if let data { buf.append(data) }
            let text = String(decoding: buf, as: UTF8.self)
            if let end = text.range(of: "\r\n") {
                let parts = text[..<end.lowerBound].split(separator: " ")
                let target = parts.count > 1 ? String(parts[1]) : ""
                let comps = URLComponents(string: "http://127.0.0.1" + target)
                let ok = comps?.path == "/callback"
                if ok {
                    var q: [String: String] = [:]
                    for i in comps?.queryItems ?? [] { q[i.name] = i.value ?? "" }
                    sink.yield(q)
                }
                let html = ok ? "<!doctype html><meta charset=utf-8><title>MinorREST</title><body style=\"font-family:-apple-system,sans-serif;text-align:center;margin-top:20vh\"><h2>Hotovo, okno můžete zavřít.</h2><p>Done, you can close this window.</p></body>"
                    : "Not found"
                let body = Data(html.utf8)
                let head = "HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
            } else if done || err != nil {
                c.cancel()
            } else {
                receive(c, buf, sink)
            }
        }
    }
}

extension OAuthClient {
    /// Doba čekání na přihlášení v prohlížeči.
    public static let loginTimeout: Duration = .seconds(300)

    /// Authorization code (+ PKCE S256): otevře prohlížeč přes `open`, počká na `/callback`
    /// (max `timeout`, zrušitelné `cancelLogin()`), vymění code za token a uloží ho.
    @discardableResult
    public func login(_ p: OAuthParams, options: HTTPEngine.Options, timeout: Duration = OAuthClient.loginTimeout,
                      open: @escaping @Sendable (URL) -> Void) async throws -> TokenInfo {
        guard p.grantType == OAuthParams.authorizationCode else { throw CoreError(.oauthLoginRequired, p.grantType) }
        guard var url = URLComponents(string: p.authURL), url.scheme != nil, !p.tokenURL.isEmpty else {
            throw CoreError(.urlInvalid, "authUrl")
        }
        loginTask?.cancel()
        let task = Task { try await self.runLogin(p, options, timeout, open, url: &url) }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    public func cancelLogin() { loginTask?.cancel() }

    private func runLogin(_ p: OAuthParams, _ options: HTTPEngine.Options, _ timeout: Duration,
                          _ open: @Sendable (URL) -> Void, url: inout URLComponents) async throws -> TokenInfo {
        let server = try await OAuthCallbackServer(port: UInt16(clamping: max(p.redirectPort, 0)))
        defer { server.stop() }
        let redirect = "http://127.0.0.1:\(server.port)/callback"
        let state = Self.randomURLSafe(), verifier = Self.randomURLSafe()
        var q = [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: p.clientID),
                 URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "state", value: state)]
        if !p.scope.isEmpty { q.append(URLQueryItem(name: "scope", value: p.scope)) }
        if p.usePKCE {
            q += [URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
                  URLQueryItem(name: "code_challenge_method", value: "S256")]
        }
        url.queryItems = (url.queryItems ?? []) + q
        guard let authorize = url.url else { throw CoreError(.urlInvalid, "authUrl") }
        open(authorize)

        let cb = try await Self.waitForCallback(server, state: state, timeout: timeout)
        if let e = cb["error"] {
            throw CoreError(.oauthTokenError, e + (cb["error_description"].map { " – " + $0 } ?? ""))
        }
        guard let code = cb["code"], !code.isEmpty else { throw CoreError(.oauthTokenError, "code missing") }
        var form = [KV(name: "grant_type", value: "authorization_code"), KV(name: "code", value: code),
                    KV(name: "redirect_uri", value: redirect)]
        if p.usePKCE { form.append(KV(name: "code_verifier", value: verifier)) }
        return try await request(p, form, options, previousRefresh: "")
    }

    /// První volání `/callback` se správným `state`; jiné (cizí `state`) se ignoruje.
    private static func waitForCallback(_ s: OAuthCallbackServer, state: String,
                                        timeout: Duration) async throws -> [String: String] {
        let result = try await withThrowingTaskGroup(of: [String: String]?.self) { g in
            g.addTask {
                for await cb in s.callbacks where cb["state"] == state { return cb }
                return nil
            }
            g.addTask {
                try await Task.sleep(for: timeout)
                throw CoreError(.netTimeout, "oauth login")
            }
            defer { g.cancelAll() }
            return try await g.next() ?? nil
        }
        guard let result, !Task.isCancelled else { throw CoreError(.canceled) }
        return result
    }

    static func randomURLSafe() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
    }

    static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
