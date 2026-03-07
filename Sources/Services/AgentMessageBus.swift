import Foundation

/// Shared message bus for inter-agent communication
/// Supports multiple subscriptions per agent and cleanup tokens
@MainActor
final class AgentMessageBus: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var unreadCount: Int = 0

    /// Each subscription has a unique ID for targeted cleanup
    private struct Subscription {
        let id: String
        let agentId: String
        let callback: (AgentMessage) -> Void
    }

    private var subscriptions: [Subscription] = []

    init() {}

    // MARK: - Publish

    /// Send a message to a specific agent or broadcast to all
    func send(_ message: AgentMessage) {
        messages.append(message)
        trimMessages()

        // Snapshot subscriptions to avoid mutation during iteration
        let current = subscriptions

        if let to = message.to {
            // Targeted: deliver to all subscriptions for this agentId
            for sub in current where sub.agentId == to {
                sub.callback(message)
            }
        } else {
            // Broadcast to all except sender
            for sub in current where sub.agentId != message.from {
                sub.callback(message)
            }
        }

        unreadCount += 1
    }

    /// Convenience: send a task to a specific agent
    func sendTask(from: String, to: String, task: String, context: [String: String] = [:]) {
        let msg = AgentMessage(
            from: from,
            to: to,
            type: .task,
            payload: task,
            context: context
        )
        send(msg)
    }

    /// Convenience: broadcast a result to all agents
    func broadcastResult(from: String, result: String, context: [String: String] = [:]) {
        let msg = AgentMessage(
            from: from,
            type: .result,
            payload: result,
            context: context
        )
        send(msg)
    }

    /// Convenience: request a review from a specific agent
    func requestReview(from: String, to: String, content: String) {
        let msg = AgentMessage(
            from: from,
            to: to,
            type: .review,
            payload: content
        )
        send(msg)
    }

    // MARK: - Subscribe

    /// Register a subscription. Returns a subscription ID for cleanup.
    @discardableResult
    func subscribe(agentId: String, callback: @escaping (AgentMessage) -> Void) -> String {
        let id = UUID().uuidString
        subscriptions.append(Subscription(id: id, agentId: agentId, callback: callback))
        return id
    }

    /// Remove a specific subscription by its ID
    func unsubscribe(subscriptionId: String) {
        subscriptions.removeAll { $0.id == subscriptionId }
    }

    /// Remove all subscriptions for an agent (used on agent stop)
    func unsubscribe(agentId: String) {
        subscriptions.removeAll { $0.agentId == agentId }
    }

    // MARK: - Query

    /// Get messages for a specific agent (sent to them or broadcast)
    func messagesFor(agentId: String) -> [AgentMessage] {
        messages.filter { $0.to == agentId || $0.to == nil }
    }

    /// Get messages between two specific agents
    func messagesBetween(agent1: String, agent2: String) -> [AgentMessage] {
        messages.filter {
            ($0.from == agent1 && $0.to == agent2) ||
            ($0.from == agent2 && $0.to == agent1)
        }
    }

    /// Mark all as read
    func markAllRead() {
        unreadCount = 0
    }

    // MARK: - Helpers

    private func trimMessages() {
        if messages.count > 500 {
            messages = Array(messages.suffix(500))
        }
    }
}
