import AppKit
import UserNotifications

@MainActor
final class WorkbenchNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkbenchNotifications()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func enable() async -> Bool {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { WorkbenchStore.shared.errorMessage = error.localizedDescription; return false }
    }
    func post(title: String, body: String, threadID: String? = nil, test: Bool = false) async {
        let preferences = WorkbenchStore.shared.preferences
        guard test || (preferences.notificationsEnabled && (!preferences.notifyInBackgroundOnly || !NSApp.isActive)) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if preferences.notificationSound { content.sound = .default }
        if let threadID { content.userInfo = ["threadID": threadID] }
        do {
            try await UNUserNotificationCenter.current().add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
        } catch { if test { WorkbenchStore.shared.errorMessage = error.localizedDescription } }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let threadID = response.notification.request.content.userInfo["threadID"] as? String
        await MainActor.run {
            if let threadID { WorkbenchStore.shared.selectThread(threadID) }
            WorkbenchWindows.showMain()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
