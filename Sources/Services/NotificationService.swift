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
    private var permissionChecked = false

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

        // Check current settings immediately — if already authorized from a previous launch,
        // hasPermission is set before any notifications try to send (fixes the race condition)
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.hasPermission = settings.authorizationStatus == .authorized
                self?.permissionChecked = true
            }
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.hasPermission = granted
            }
        }
    }

    /// Send a system notification (only when app is not focused)
    func sendNotification(title: String, body: String) {
        ensurePermissionChecked()
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
        ensurePermissionChecked()
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
        ensurePermissionChecked()
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

    /// Send a critical notification that shows even when app IS focused (process death, unrecoverable errors)
    /// Skips hasPermission guard — always attempts to send. If not authorized, system silently drops it.
    /// This avoids the race where hasPermission is still false from the async auth callback.
    func sendCriticalNotification(title: String, body: String) {

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        content.interruptionLevel = .critical
        content.threadIdentifier = "critical"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Check permission status synchronously — fixes race where hasPermission is still false
    /// from the async requestAuthorization callback not having fired yet
    private func ensurePermissionChecked() {
        guard !permissionChecked else { return }
        permissionChecked = true
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.hasPermission = settings.authorizationStatus == .authorized
            }
        }
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

        let threadId = notification.request.content.threadIdentifier

        if category == NotificationService.permissionCategory || threadId == "critical" {
            // Always show permission + critical notifications (even when app is focused)
            completionHandler([.banner, .sound])
        } else {
            // Other notifications: only show when app is not active
            completionHandler([])
        }
    }
}
