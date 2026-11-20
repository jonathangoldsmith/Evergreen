import SwiftData
import SwiftUI

@main
struct TrackerPlusPlusApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        Theme.registerFonts()
        let container = Storage.container()
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .modelContainer(container)
    }
}
