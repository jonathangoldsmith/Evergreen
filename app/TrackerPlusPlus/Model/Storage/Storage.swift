import Foundation
import SwiftData

enum Storage {
    private static let url = URL.applicationSupportDirectory.appending(path: "TrackerPlusPlus.store")

    /// Opens the store. If it can't be opened (a schema change SwiftData can't
    /// migrate on its own), it starts over: this is demo state, and the next
    /// tick rebuilds the screen.
    static func container() -> ModelContainer {
        let schema = Schema([Run.self, ActionRecord.self, LoggedWorkout.self])
        let configuration = ModelConfiguration(schema: schema, url: url)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path() + suffix))
        }
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Couldn't open the app's store: \(error)")
        }
    }
}
