// LogSetIntent.swift — spec §7.2. Add to the Xcode app target (NOT the package).
// Requires iOS 17+. The user assigns this intent to the Action Button via
// Settings → Action Button → Shortcut, or triggers it with "Hey Siri, log a set".

import AppIntents
import SwiftUI

struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Set"
    static var description = IntentDescription("Opens the voice capture overlay and starts listening for a set.")

    // MVP-safe path: foreground the app so the mic + on-device speech run
    // reliably. Background/locked capture is [OPEN B].
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // [OPEN A] policy — current choice: auto-start an "Untitled" session so
        // voice logging never dead-ends. Change to `.promptIfMissing` to ask.
        SessionCoordinator.shared.ensureActiveWorkout(policy: .autoStartUntitled)
        AppRouter.shared.presentVoiceCapture(autoRecord: true)
        return .result()
    }
}

struct GymLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSetIntent(),
            phrases: [
                "Log a set in \(.applicationName)",
                "Log my set in \(.applicationName)",
                "Record a set in \(.applicationName)",
            ],
            shortTitle: "Log a Set",
            systemImageName: "mic.fill"
        )
    }
}
