import Foundation
import Network

/// Přijatý request v testovacím serveru.
struct TestRequest: Sendable {
    var method = ""
    var target = ""
    /// Hlavičky v pořadí přijetí.
    var headers: [(name: String, value: String)] = []
    var body = Data()

    func header(_ name: String) -> String? {
        let v = headers.filter { $0.name.lowercased() == name.lowercased() }.map(\.value)
        return v.isEmpty ? nil : v.joined(separator: ",")
    }
}

struct TestResponse: Sendable {
    var status = 200
    var headers: [(String, String)] = []
    var body = Data()
    /// Zpoždění před odpovědí (timeout, zrušení).
    var delay: Duration = .zero
}

/// Minimální HTTP/1.1 server nad `NWListener` (jedna odpověď na spojení, `Connection: close`).
final class TestHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (TestRequest) async -> TestResponse

    private let listener: NWListener
    private let queue = DispatchQueue(label: "test-http")
    private let handler: Handler
    private(set) var port: UInt16 = 0
    var url: String { "http://127.0.0.1:\(port)" }

    init(_ handler: @escaping Handler) async throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let ready = AsyncStream<UInt16> { cont in
            listener.stateUpdateHandler = { [listener] st in
                if case .ready = st { cont.yield(listener.port?.rawValue ?? 0); cont.finish() }
                if case .failed = st { cont.yield(0); cont.finish() }
            }
        }
        listener.start(queue: queue)
        for await p in ready { port = p }
    }

    func stop() { listener.cancel() }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, done, err in
            var buf = buf
            if let data { buf.append(data) }
            if let req = Self.parse(buf) {
                Task {
                    let res = await handler(req)
                    if res.delay > .zero { try? await Task.sleep(for: res.delay) }
                    self.respond(c, req, res)
                }
            } else if done || err != nil {
                c.cancel()
            } else {
                receive(c, buf)
            }
        }
    }

    private func respond(_ c: NWConnection, _ req: TestRequest, _ res: TestResponse) {
        var head = "HTTP/1.1 \(res.status) \(HTTPURLResponse.localizedString(forStatusCode: res.status))\r\n"
        for (n, v) in res.headers { head += "\(n): \(v)\r\n" }
        head += "Content-Length: \(res.body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        if req.method != "HEAD" { out.append(res.body) }
        c.send(content: out, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
    }

    /// Úplný request z bufferu (Content-Length nebo chunked), jinak nil.
    static func parse(_ buf: Data) -> TestRequest? {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: buf[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var r = TestRequest(method: String(first[0]), target: String(first[1]))
        for l in lines.dropFirst() {
            guard let i = l.firstIndex(of: ":") else { continue }
            r.headers.append((String(l[..<i]), l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)))
        }
        let rest = buf[end.upperBound...]
        if let n = r.header("Content-Length").flatMap({ Int($0) }) {
            guard rest.count >= n else { return nil }
            r.body = Data(rest.prefix(n))
        } else if r.header("Transfer-Encoding")?.lowercased() == "chunked" {
            guard let body = dechunk(Data(rest)) else { return nil }
            r.body = body
        }
        return r
    }

    private static func dechunk(_ d: Data) -> Data? {
        var out = Data(), i = d.startIndex
        while let le = d[i...].range(of: Data("\r\n".utf8)) {
            guard let n = Int(String(decoding: d[i..<le.lowerBound], as: UTF8.self), radix: 16) else { return nil }
            if n == 0 { return out }
            let start = le.upperBound
            guard d.distance(from: start, to: d.endIndex) >= n + 2 else { return nil }
            out.append(d[start..<d.index(start, offsetBy: n)])
            i = d.index(start, offsetBy: n + 2)
        }
        return nil
    }
}

/// Odpověď s metodou, hlavičkami a tělem requestu (`Echo-<název>`).
@Sendable func echo(_ r: TestRequest) -> TestResponse {
    var h: [(String, String)] = [("X-Method", r.method), ("X-Target", r.target)]
    for (n, v) in r.headers { h.append(("Echo-" + n, v)) }
    return TestResponse(headers: h, body: r.body)
}
