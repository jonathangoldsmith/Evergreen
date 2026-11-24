import Foundation
import SwiftData
import os

enum Storage {
    static let url = URL.applicationSupportDirectory.appending(path: "Evergreen.store")
    private static let log = Logger(subsystem: "com.evergreentraining.app", category: "storage")

    /// Set when the last launch couldn't open the store and set it aside.
    nonisolated(unsafe) private(set) static var setAsideFile: URL?

    /// Opens the store through the migration plan. If it still can't be
    /// opened, the old file is moved aside, never deleted, and a fresh store
    /// starts (eng review D5): a real person's swaps, injury month and unsent
    /// events may be in it.
    static func container(at url: URL = Storage.url) -> ModelContainer {
        if let container = try? open(at: url) { return container }
        let aside = setAside(url)
        setAsideFile = aside
        log.error("Couldn't open the store; set it aside at \(aside?.lastPathComponent ?? "nowhere", privacy: .public)")
        do {
            return try open(at: url)
        } catch {
            fatalError("Couldn't open the app's store: \(error)")
        }
    }

    static func open(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: EvergreenSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: EvergreenMigrationPlan.self, configurations: configuration)
    }

    /// Renames the store and its side files to "<name>-unreadable-<time>", so
    /// it can be recovered by hand. Returns the main file's new location.
    @discardableResult
    static func setAside(_ url: URL, now: Date = Date()) -> URL? {
        let stamp = Int(now.timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var moved: URL?
        for suffix in ["", "-shm", "-wal"] {
            // path(percentEncoded: false): "Application Support" has a space.
            let from = URL(filePath: url.path(percentEncoded: false) + suffix)
            guard FileManager.default.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            let to = folder.appending(path: "\(base)-unreadable-\(stamp).\(url.pathExtension)\(suffix)")
            do {
                try FileManager.default.moveItem(at: from, to: to)
                if suffix.isEmpty { moved = to }
            } catch {
                log.error("Couldn't set aside \(from.lastPathComponent, privacy: .public): \(error.localizedDescription)")
            }
        }
        return moved
    }
}
