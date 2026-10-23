import Foundation
import UserNotifications

/// Tenká vrstva nad systémovými oznámeními.
enum Notifications {
    enum Category: String {
        case notRunning = "reminder.notRunning"
        case longRunning = "reminder.longRunning"
        case missingNote = "reminder.missingNote"
    }

    enum Action {
        static let startLast = "action.startLast"
        static let stop = "action.stop"
        static let addNote = "action.addNote"
    }

    /// Volá se na hlavním vlákně po kliknutí na akci v oznámení.
    /// Parametry: identifikátor akce a kategorie oznámení.
    @MainActor static var actionHandler: ((String, String) -> Void)?

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        // Aplikace nemá ikonu v Docku a je často "aktivní", bez tohoto by se banner neukázal.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter, willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions { [.banner, .sound] }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
        ) async {
            let action = response.actionIdentifier
            let category = response.notification.request.content.categoryIdentifier
            await MainActor.run { Notifications.actionHandler?(action, category) }
        }
    }

    private static let delegate = Delegate()

    static func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.notRunning.rawValue,
                actions: [UNNotificationAction(identifier: Action.startLast, title: "Spustit časovač")],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.longRunning.rawValue,
                actions: [UNNotificationAction(identifier: Action.stop, title: "Zastavit")],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.missingNote.rawValue,
                actions: [UNNotificationAction(identifier: Action.addNote, title: "Doplnit poznámku")],
                intentIdentifiers: []
            ),
        ])
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, category: Category? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category.rawValue }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
