import Foundation
import AppKit

/// Minimal sound design — subtle, optional, off by default
/// Per UX_DESIGN.md: "Default state is silence. Escalation is graduated. Never interrupts."
@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "soundEnabled") }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
    }

    /// Subtle click — when Claude finishes a response
    func playResponseComplete() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    /// Quiet chime — when a long-running operation completes AND window is not focused
    func playBackgroundComplete() {
        guard isEnabled else { return }
        guard !NSApp.isActive else { return } // Only when app is not focused
        NSSound(named: "Glass")?.play()
    }

    /// Muted notification — when a permission is needed
    func playPermissionNeeded() {
        guard isEnabled else { return }
        NSSound(named: "Purr")?.play()
    }

    /// Toggle sound on/off
    func toggle() {
        isEnabled.toggle()
    }
}
