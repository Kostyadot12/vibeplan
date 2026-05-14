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
        // Don't bother building the notification if user already declined.
        if authorized == false { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
