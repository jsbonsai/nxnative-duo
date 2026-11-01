import AppKit
import SwiftUI

@main
struct DuoBuilderApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppActivation.self) private var activation

    var body: some Scene {
        WindowGroup("Duo Builder") {
            RootView()
                .environmentObject(model)
                .frame(width: 680, height: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Game…") { model.choosePackages() }.keyboardShortcut("o")
            }
        }
    }
}

/// `swift run` starts a bare executable, not a .app: without a regular activation policy macOS checks the
/// process in as background-only and the window never comes forward.
final class AppActivation: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfAsked() { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
