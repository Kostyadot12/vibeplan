import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter so RealtimeClient can post
/// system notifications when tasks involving the current user change upstream.
@MainActor
enum Notifier {
    private static var authorized: Bool? = nil

    static func requestAuthorizationIfNeeded() async {
        if authorized != nil { return }
        do {
            authorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        if authorized == false { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Schedule a one-shot notification at a specific date.
    /// `identifier` is stable per-task so we can replace if the task moves.
    static func schedule(title: String, body: String, at date: Date, identifier: String) {
        if authorized == false { return }
        if date <= Date() { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Replace any pending notification with this id.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.add(req, withCompletionHandler: nil)
    }

    static func cancel(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func reminderId(forTaskServerId sid: String) -> String { "reminder.\(sid)" }
}
