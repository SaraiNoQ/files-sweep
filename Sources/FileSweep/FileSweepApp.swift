import SwiftUI

@main
struct FileSweepApp: App {
    var body: some Scene {
        WindowGroup("FileSweep") { WorkspaceView() }
            .defaultSize(width: 1240, height: 820)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands { FileSweepCommands() }
    }
}
