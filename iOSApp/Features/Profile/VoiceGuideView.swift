// VoiceGuideView.swift — in-app tutorial for the three voice entry points:
// the hold-to-log mic, the Action Button shortcut, and Siri. Linked from
// Profile → Help. Content mirrors what LogSetIntent actually registers.

import SwiftUI
import GymLogCore

struct VoiceGuideView: View {
    var body: some View {
        List {
            Section {
                GuideRow(icon: "mic.fill",
                         title: "Hold the mic button",
                         detail: "On the Workout tab, press and hold the big mic bar, say your set, then release. GymLog parses it and logs it instantly — no typing.")
                GuideRow(icon: "quote.bubble",
                         title: "Say it naturally",
                         detail: "Weight and reps in any order, with the exercise name on the first set:")
                VStack(alignment: .leading, spacing: 8) {
                    ExamplePhrase("“Bench press one thirty five for eight”")
                    ExamplePhrase("“Two twenty five, five reps, squat”")
                    ExamplePhrase("“Same weight for six”  — reuses the current exercise")
                    ExamplePhrase("“One eighty five for three, RPE eight”")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Logging a set by voice")
            } footer: {
                Text("After the first set of an exercise you can skip its name — GymLog keeps logging to the current exercise until you say a new one.")
            }

            Section {
                GuideRow(icon: "1.circle.fill",
                         title: "Open iPhone Settings",
                         detail: "Go to Settings → Action Button. (The Action Button is on iPhone 15 Pro and later, replacing the mute switch.)")
                GuideRow(icon: "2.circle.fill",
                         title: "Choose Shortcut",
                         detail: "Swipe to the Shortcut option, tap “Choose a Shortcut…”, and pick “Log a Set” under GymLog.")
                GuideRow(icon: "3.circle.fill",
                         title: "Press to log, anywhere",
                         detail: "From now on, pressing the Action Button opens GymLog with the mic already listening — mid-workout, no unlocking menus.")
            } header: {
                Text("Action Button setup")
            } footer: {
                Text("No Action Button on your iPhone? Add “Log a Set” to your Home Screen or Lock Screen via the Shortcuts app instead.")
            }

            Section {
                GuideRow(icon: "waveform",
                         title: "Just ask Siri",
                         detail: "Say “Hey Siri, log a set in GymLog”. Siri opens the app listening for your set. “Log my set in GymLog” and “Record a set in GymLog” work too.")
            } header: {
                Text("Siri")
            } footer: {
                Text("The phrases become available automatically after the first launch of GymLog — no Shortcuts setup required.")
            }

            Section {
                GuideRow(icon: "checkmark.bubble",
                         title: "Confirm before saving",
                         detail: "Off by default: sets auto-commit with an easy Undo. Turn it on in Settings → Voice logging to review each parsed set before it saves.")
                GuideRow(icon: "arrow.uturn.backward",
                         title: "Fixing mistakes",
                         detail: "Tap “Undo last set” right after a bad parse, or long-press any set row to edit its numbers.")
            } header: {
                Text("Good to know")
            }
        }
        .navigationTitle("Voice logging guide")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GymTheme.accent)
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(GymTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ExamplePhrase: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(GymTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(GymTheme.accent.opacity(0.08)))
    }
}
