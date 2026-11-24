import CoreServices
import Foundation

/// Sleduje adresáře projektů přes FSEvents (jeden rekurzivní stream na projekt).
/// `onChange` dostane ID projektu a změněné cesty vůči kořeni (nil = rozsah neznámý, načíst vše);
/// volá se na vlastní sériové frontě.
nonisolated final class ProjectWatcher: @unchecked Sendable {
    typealias OnChange = @Sendable (_ projectID: String, _ rels: [String]?) -> Void

    /// Doba, po kterou se změny slučují do jednoho hlášení.
    static let latency: CFTimeInterval = 0.3

    private final class Box {
        let id: String
        let root: String
        let onChange: OnChange
        init(id: String, root: String, onChange: @escaping OnChange) {
            self.id = id
            self.root = root
            self.onChange = onChange
        }
    }

    private let lock = NSLock()
    private var streams: [String: FSEventStreamRef] = [:]
    private let queue = DispatchQueue(label: "minorrest.watcher")
    private let onChange: OnChange
    private let ignoreSelf: Bool

    /// `ignoreSelf` potlačí změny provedené tímto procesem (vlastní zápisy aplikace); testy ho vypínají.
    init(ignoreSelf: Bool = true, onChange: @escaping OnChange) {
        self.ignoreSelf = ignoreSelf
        self.onChange = onChange
    }

    deinit {
        for stream in streams.values { Self.stop(stream) }
    }

    /// Začne sledovat kořen projektu; už sledovaný projekt nejdřív odebere.
    func add(id: String, root: URL) {
        remove(id: id)
        // FSEvents hlásí kanonické cesty (/private/tmp …)
        let path = FileIO.realPath(root.path)
        let box = Unmanaged.passRetained(Box(id: id, root: path, onChange: onChange))
        var context = FSEventStreamContext(
            version: 0, info: box.toOpaque(), retain: nil,
            release: { info in info.map { Unmanaged<Box>.fromOpaque($0).release() } },
            copyDescription: nil)
        var flags =
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        if ignoreSelf { flags |= kFSEventStreamCreateFlagIgnoreSelf }
        guard
            let stream = FSEventStreamCreate(
                nil, Self.callback, &context, [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, FSEventStreamCreateFlags(flags))
        else {
            box.release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.withLock { streams[id] = stream }
    }

    /// Přestane sledovat projekt.
    func remove(id: String) {
        if let stream = lock.withLock({ streams.removeValue(forKey: id) }) { Self.stop(stream) }
    }

    private static func stop(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
        let rescan = UInt32(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagRootChanged)
        var rels: [String] = []
        for i in 0..<count {
            if flags[i] & rescan != 0 {
                box.onChange(box.id, nil)
                return
            }
            if i < paths.count, let rel = relativePath(root: box.root, path: paths[i]), !rels.contains(rel) {
                rels.append(rel)
            }
        }
        if !rels.isEmpty { box.onChange(box.id, rels) }
    }

    /// Cesta vůči kořeni projektu; nil pro cesty mimo projekt, samotný kořen
    /// a skryté položky (`.git`, `.responses`, dočasné `.tmp-*`, `.DS_Store` …).
    static func relativePath(root: String, path: String) -> String? {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rel = String(path.dropFirst(prefix.count))
        let segments = rel.split(separator: "/", omittingEmptySubsequences: false)
        guard !rel.isEmpty, !segments.contains(where: { $0.isEmpty || $0.hasPrefix(".") }) else { return nil }
        return rel
    }
}
