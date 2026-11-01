import AppKit
import Foundation
import UserNotifications

/// Local reminders (IMPLEMENTATION.md §7.4, §10). Permission is asked the first time the reminder checkbox is
/// ticked, never at launch. Expiry dates come from the installs contract; without them nothing is scheduled.
enum Reminders {
    static let expiryCategory = "DUO_EXPIRY"

    private static var center: UNUserNotificationCenter? {
        // `swift run` is a bare executable with no bundle identifier; UserNotifications needs a bundle.
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    @MainActor static func requestAccess() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let renew = UNNotificationAction(identifier: "RENEW", title: Copy.notifExpiryAction, options: [.foreground])
        let category = UNNotificationCategory(identifier: expiryCategory, actions: [renew], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// One reminder per app, at expiry − 1 day, 10:00 local, re-scheduled whenever the installs change.
    @MainActor static func reschedule(installs: PhoneInstalls?, settings: SettingsStore) {
        guard let center else { return }
        center.removeAllPendingNotificationRequests()
        guard settings.reminder, let installs else { return }
        let calendar = Calendar.current
        for app in installs.apps {
            guard let expiry = app.expiresAt else { continue }
            guard let day = calendar.date(byAdding: .day, value: -1, to: expiry) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = 10
            components.minute = 0
            guard let fire = calendar.date(from: components), fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Duo Builder"
            content.body = Copy.notifExpiry(game: app.title, phone: installs.deviceName)
            content.categoryIdentifier = expiryCategory
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "expiry:" + app.bundleID, content: content, trigger: trigger))
        }
    }

    /// "“<Game> is on <phone>.”" only when the app is not frontmost (§6.11 optional completion notice).
    @MainActor static func notifyDone(game: String, phone: String) {
        guard let center, !NSApp.isActive else { return }
        let content = UNMutableNotificationContent()
        content.title = "Duo Builder"
        content.body = Copy.notifDone(game: game, phone: phone)
        center.add(UNNotificationRequest(identifier: "done:" + UUID().uuidString, content: content, trigger: nil))
    }
}
