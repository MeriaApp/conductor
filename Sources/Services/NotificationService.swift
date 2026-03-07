import Foundation
import UserNotifications
import AppKit

/// System notifications for background events and permission requests
/// Background events: only fires when app is not focused
/// Permission requests: fires always (actionable — approve/deny from notification)
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    // Notification categories
    static let permissionCategory = "PERMISSION_REQUEST"
    static let approveAction = "APPROVE_ACTION"
    static let denyAction = "DENY_ACTION"

    private var hasPermission = false

    /// Callback when a permission is approved/denied via notification action
    var onPermissionAction: ((String, Bool) -> Void)? // (requestId, approved)

    private init() {}

    /// Request notification permission and register action categories
    func requestPermission() {
        // Define actions for permission notifications
        let approveAction = UNNotificationAction(
            identifier: Self.approveAction,
            title: "Approve",
            options: []
        )
        let denyAction = UNNotificationAction(
            identifier: Self.denyAction,
            title: "Deny",
            options: [.destructive]
        )
        let permissionCategory = UNNotificationCategory(
            identifier: Self.permissionCategory,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([permissionCategory])
        center.delegate = NotificationDelegate.shared

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.hasPermission = granted
            }
        }
    }

    /// Send a system notification (only when app is not focused)
    func sendNotification(title: String, body: String) {
        guard hasPermission else { return }
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Send a permission request notification — fires even when app is focused
    /// Includes Approve/Deny action buttons
    func sendPermissionNotification(requestId: String, agentName: String, toolName: String, input: String, riskLevel: RiskLevel) {
        guard hasPermission else { return }

        let content = UNMutableNotificationContent()
        content.title = "Permission Needed — \(toolName)"
        content.subtitle = agentName
        content.body = truncateInput(input, maxLength: 120)
        content.categoryIdentifier = Self.permissionCategory
        content.sound = riskLevel == .critical ? .defaultCritical : .default
        content.userInfo = ["requestId": requestId]

        // Thread by agent so notifications group
        content.threadIdentifier = "permission-\(agentName)"

        let request = UNNotificationRequest(
            identifier: "perm-\(requestId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Send a completion notification (response done, agent finished, etc.)
    func sendCompletionNotification(title: String, body: String) {
        guard hasPermission else { return }
        guard !NSApp.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.threadIdentifier = "completion"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Remove permission notification when resolved in-app
    func removePermissionNotification(requestId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["perm-\(requestId)"]
        )
    }

    private func truncateInput(_ input: String, maxLength: Int) -> String {
        let clean = input.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if clean.count <= maxLength { return clean }
        return String(clean.prefix(maxLength - 1)) + "…"
    }
}

/// Handles notification interactions (click to focus, action buttons for permissions)
private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let requestId = userInfo["requestId"] as? String

        switch response.actionIdentifier {
        case NotificationService.approveAction:
            if let id = requestId {
                Task { @MainActor in
                    NotificationService.shared.onPermissionAction?(id, true)
                }
            }

        case NotificationService.denyAction:
            if let id = requestId {
                Task { @MainActor in
                    NotificationService.shared.onPermissionAction?(id, false)
                }
            }

        default:
            // Default tap — bring app to foreground
            NSApp.activate(ignoringOtherApps: true)
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier

        if category == NotificationService.permissionCategory {
            // Always show permission notifications (even when app is focused)
            completionHandler([.banner, .sound])
        } else {
            // Other notifications: only show when app is not active
            completionHandler([])
        }
    }
}
