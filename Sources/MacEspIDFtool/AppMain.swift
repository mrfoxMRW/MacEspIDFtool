import SwiftUI

@main
struct MacEspIDFtoolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .help) {
                Text("MacEspIDFtool · ESP-IDF 日志抓取工具")
                Divider()
                Text("开发者：Tonan海棠 for MRWmrfox")
                Text("Copyright © 2026 Tonan海棠 for MRWmrfox. All rights reserved.")
            }
        }
    }
}
