import Foundation
import JavaScriptCore

/// Runs the memory bundle (memory-agent, built to Resources/Memory/memory-phone.js)
/// in JavaScriptCore. A sync rolls the person's memory and, when an Amplitude
/// key is set, hands the staged events to the sink and acknowledges them.
/// Memory lives in Application Support/Memory, one folder per person.
actor MemoryEngine {
    struct Report: Sendable, Equatable {
        /// Events Amplitude accepted during this sync.
        var sent = 0
        /// Events still waiting in the outbox.
        var pending = 0
        /// What went wrong, if anything; the bundle's error names only.
        var problem: String?
    }

    private let context: JSContext
    private let root: String
    private let secret: String
    private var running = false
    /// Midnights already rolled as completed days, so each day's `memory_rolled` is staged once per launch.
    private var rolledDays: Set<String> = []

    /// Nil when the bundle is missing or doesn't load.
    init?(root: URL, secret: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "memory-phone", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              (try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)) != nil,
              let resolved = MemoryFiles.realpath(root.path)["v"] as? String,
              let context = JSContext()
        else { return nil }
        // The store refuses paths that leave the person's folder, so give it the real path (/var is a symlink on a phone).
        self.root = resolved
        self.secret = secret
        self.context = context
        Self.installHost(in: context)
        context.evaluateScript(script)
        guard context.exception == nil, context.objectForKeyedSubscript("memoryRoll")?.isObject == true else { return nil }
    }

    /// The memory folder in Application Support, with this install's id secret.
    static func standard() -> MemoryEngine? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return MemoryEngine(root: support.appending(path: "Memory"), secret: IdSecret.load())
    }

    /// The person's opaque user id: the same HMAC the bundle uses for its own ids.
    func userId(_ personaKey: String) -> String {
        "usr_" + MemoryFiles.hmac(secret, "usr\u{0}persona|\(personaKey)").prefix(16)
    }

    /// Delivers what's waiting, rolls yesterday (once) and today so far, and
    /// delivers what those staged. Without a sink, memory still rolls and no
    /// events are staged. A sync already in progress makes this one a no-op.
    func sync(_ input: MemoryInput, sink: (any EventSink)?) async -> Report {
        guard !running else { return Report() }
        running = true
        defer { running = false }

        let user = userId(input.personaKey)
        setSending(sink != nil)
        var report = Report()

        if let sink, !(await drain(user, sink, into: &report)) { return finish(user, report) }

        let midnight = input.timestamp(input.midnight)
        if !rolledDays.contains("\(user)|\(midnight)") {
            let rolled = roll(user, snapshot: input.snapshot(exportDate: input.midnight), now: midnight, into: &report)
            if rolled { rolledDays.insert("\(user)|\(midnight)") }
            if let sink, !(await drain(user, sink, into: &report)) { return finish(user, report) }
        }

        if input.now > input.midnight {
            _ = roll(user, snapshot: input.snapshot(exportDate: input.now), now: input.timestamp(input.now), into: &report)
            if let sink { _ = await drain(user, sink, into: &report) }
        }
        return finish(user, report)
    }

    // MARK: Steps

    private func roll(_ user: String, snapshot: [String: Any], now: String, into report: inout Report) -> Bool {
        let answer = call("memoryRoll", ["root": root, "user": user, "snapshot": snapshot, "now": now])
        if answer["ok"] as? Bool != true {
            report.problem = answer["error"] as? String ?? "memory roll failed"
            return false
        }
        if let stageError = answer["stageError"] as? String { report.problem = stageError }
        return true
    }

    /// Sends the outbox in batches of 500 and acknowledges each accepted batch.
    /// False when a batch wasn't accepted: it stays in the outbox for next time.
    private func drain(_ user: String, _ sink: any EventSink, into report: inout Report) async -> Bool {
        let flushed = call("memoryFlush", ["root": root, "user": user])
        guard let events = flushed["events"] as? [[String: Any]] else {
            report.problem = flushed["error"] as? String ?? "memory flush failed"
            return false
        }
        for start in stride(from: 0, to: events.count, by: 500) {
            let batch = Array(events[start..<min(start + 500, events.count)])
            guard let data = try? JSONSerialization.data(withJSONObject: batch), await sink.send(batch: data) else {
                report.problem = "Amplitude didn't accept the events"
                return false
            }
            let acked = call("memoryAck", ["root": root, "user": user, "acked": batch.compactMap { $0["insert_id"] as? String }])
            guard acked["ok"] as? Bool == true else {
                report.problem = acked["error"] as? String ?? "memory ack failed"
                return false
            }
            report.sent += batch.count
        }
        return true
    }

    private func finish(_ user: String, _ report: Report) -> Report {
        var report = report
        report.pending = (call("memoryFlush", ["root": root, "user": user])["events"] as? [Any])?.count ?? 0
        return report
    }

    // MARK: JavaScriptCore

    /// The bundle only stages events when `memoryIO` has an id secret.
    private func setSending(_ on: Bool) {
        guard let io = context.objectForKeyedSubscript("memoryIO") else { return }
        if on {
            io.setValue(secret, forProperty: "idSecret")
        } else {
            io.deleteProperty("idSecret")
        }
    }

    /// Calls one of the bundle's six functions: one JSON string in, one out.
    private func call(_ name: String, _ args: [String: Any]) -> [String: Any] {
        guard let function = context.objectForKeyedSubscript(name),
              let json = try? JSONSerialization.data(withJSONObject: args),
              let text = String(data: json, encoding: .utf8),
              let out = function.call(withArguments: [text])?.toString(),
              let answer = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        else { return ["ok": false, "error": "\(name) failed"] }
        return answer
    }

    /// Sets `globalThis.memoryIO` (memory-agent/docs/PHONE.md) on top of `MemoryFiles`.
    private static func installHost(in context: JSContext) {
        guard let host = JSValue(newObjectIn: context) else { return }
        func set(_ name: String, _ block: Any) {
            host.setObject(block, forKeyedSubscript: name as NSString)
        }
        let one: [(String, @convention(block) (String) -> [String: Any])] = [
            ("readFile", { MemoryFiles.readFile($0) }), ("fsyncFile", { MemoryFiles.fsyncFile($0) }),
            ("fsyncDir", { MemoryFiles.fsyncDir($0) }), ("remove", { MemoryFiles.remove($0) }),
            ("mkdir", { MemoryFiles.mkdir($0) }), ("lstat", { MemoryFiles.lstat($0) }),
            ("realpath", { MemoryFiles.realpath($0) }), ("readdir", { MemoryFiles.readdir($0) }),
        ]
        for (name, block) in one { set(name, unsafeBitCast(block, to: AnyObject.self)) }
        let two: [(String, @convention(block) (String, String) -> [String: Any])] = [
            ("writeFile", { MemoryFiles.writeFile($0, $1) }), ("rename", { MemoryFiles.rename($0, $1) }),
        ]
        for (name, block) in two { set(name, unsafeBitCast(block, to: AnyObject.self)) }
        let sha256: @convention(block) (String) -> String = { MemoryFiles.sha256($0) }
        let hmac: @convention(block) (String, String) -> String = { MemoryFiles.hmac($0, $1) }
        set("sha256", unsafeBitCast(sha256, to: AnyObject.self))
        set("hmac", unsafeBitCast(hmac, to: AnyObject.self))
        context.setObject(host, forKeyedSubscript: "__memoryHost" as NSString)
        context.evaluateScript("""
        (() => {
          const h = globalThis.__memoryHost;
          const r = (x) => {
            if (x.e !== undefined) { const error = new Error(x.e); error.code = x.e; throw error; }
            return x.v;
          };
          globalThis.memoryIO = {
            platform: 'posix',
            readFile: (p) => r(h.readFile(p)),
            writeFile: (p, t) => { r(h.writeFile(p, t)); },
            fsyncFile: (p) => { r(h.fsyncFile(p)); },
            fsyncDir: (p) => { r(h.fsyncDir(p)); },
            rename: (a, b) => { r(h.rename(a, b)); },
            remove: (p) => { r(h.remove(p)); },
            mkdir: (p) => { r(h.mkdir(p)); },
            lstat: (p) => r(h.lstat(p)),
            realpath: (p) => r(h.realpath(p)),
            readdir: (p) => r(h.readdir(p)),
            sha256: (t) => h.sha256(t),
            hmac: (s, d) => h.hmac(s, d),
          };
        })();
        """)
    }
}
