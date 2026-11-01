import AppKit
import SwiftUI
import UserNotifications

@main
struct DuoBuilderApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppActivation.self) private var activation

    var body: some Scene {
        WindowGroup("Duo Builder") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.setup)
                .environmentObject(model.phones)
                .environmentObject(model.installs)
                .environmentObject(model.library)
                .environmentObject(model.settings)
                .frame(width: 720, height: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 560)
        .commands { DuoCommands(model: model) }
    }
}

/// `swift run` starts a bare executable, not a .app: without a regular activation policy macOS checks the
/// process in as background-only and the window never comes forward.
final class AppActivation: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.runIfAsked() { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension AppActivation: UNUserNotificationCenterDelegate {
    /// The expiry reminder's "Renew" action opens "On this iPhone" (§7.4).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "RENEW" || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            NotificationCenter.default.post(name: .duoOpenRenew, object: nil)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let duoOpenRenew = Notification.Name("DuoBuilder.openRenew")
}
