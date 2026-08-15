// VoiceCaptureView.swift — implements mockups B1–B5 from
// `GymLog Mockups.dc.html`: listening waveform (B1), parsed chip with
// Re-record / Log it (B2), "Did you mean…" suggestion capsules (B3),
// error with heard-echo (B4), and the partial-parse state (B5) that shows
// the chip with a dashed "? reps" and KEEPS LISTENING for the missing slot.

import SwiftUI
import GymLogCore

struct VoiceCaptureView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @StateObject private var speech = SpeechService()
    @Environment(\.dismiss) private var dismiss

    let autoRecord: Bool
    @AppStorage("confirmMode") private var confirmFirst = false

    private enum Phase {
        case listening
        case confirm(SetDraft, ExerciseMatch)
        case suggestions(SetDraft, [ExerciseDefinition], heard: String)
        case awaitingReps(SetDraft, ExerciseMatch)      // B5
        case error(message: String, heard: String?)
        case idle
    }
    @State private var phase: Phase = .idle
    @State private var heardTranscript = ""

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            switch phase {
            case .listening:      listeningView
            case .confirm(let d, let m):        confirmView(d, m)
            case .suggestions(let d, let s, let heard): suggestionsView(d, s, heard)
            case .awaitingReps(let d, let m):   awaitingRepsView(d, m)
            case .error(let msg, let heard):    errorView(msg, heard)
            case .idle:           idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GymTheme.background)
        .task {
            speech.onFinalTranscript = handle(transcript:)
            if autoRecord { await startListening() }
        }
        .onDisappear { speech.stopListening() }
    }

    // MARK: B1 — Listening

    private var listeningView: some View {
        VStack(spacing: 0) {
            Text("LISTENING")
                .font(.system(size: 13, weight: .semibold))
                .kerning(1)
                .foregroundStyle(GymTheme.accent)
                .opacity(0.9)
                .padding(.top, 30)
                .phaseAnimator([0.35, 0.9]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.8) }

            WaveformView(barCount: 12, maxHeight: 60)
                .padding(.top, 28)

            Text(speech.liveTranscript.isEmpty ? " " : "“\(speech.liveTranscript)”")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.top, 34)
                .padding(.horizontal, 24)

            Spacer()
            Text("Release to parse · swipe down to cancel")
                .font(.system(size: 13))
                .foregroundStyle(GymTheme.textTertiary)
                .padding(.bottom, 24)
        }
    }

    // MARK: B2 — Parsed chip (confirm-first)

    private func confirmView(_ draft: SetDraft, _ match: ExerciseMatch) -> some View {
        VStack(spacing: 0) {
            Text("GOT IT")
                .font(.system(size: 13, weight: .semibold))
                .kerning(1)
                .foregroundStyle(GymTheme.textTertiary)
                .padding(.top, 30)

            ParsedChipView(title: chipTitle(match), draft: draft)
                .padding(.top, 34)

            Text("“\(heardTranscript)”")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(GymTheme.textFaint)
                .padding(.top, 14)

            Spacer()
            HStack(spacing: 12) {
                Button("Re-record") { Task { await startListening() } }
                    .buttonStyle(SheetSecondaryButtonStyle())
                Button("Log it") {
                    coordinator.commit(draft, match)
                    haptic()
                    dismiss()
                }
                .buttonStyle(SheetPrimaryButtonStyle(flex: 1.4))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: B3 — Did you mean…

    private func suggestionsView(_ draft: SetDraft, _ suggestions: [ExerciseDefinition],
                                 _ heard: String) -> some View {
        VStack(spacing: 0) {
            Text("Did you mean…")
                .font(.system(size: 19, weight: .bold))
                .padding(.top, 28)
            Text("Heard: “\(heard)”")
                .font(.system(size: 13))
                .italic()
                .foregroundStyle(GymTheme.textTertiary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, ex in
                    Button {
                        coordinator.commit(draft, .matched(ex))
                        haptic()
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text(ex.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                            if let w = draft.weight, let r = draft.reps {
                                Text("\(ParsedChipView.trim(w)) \(draft.unit?.rawValue ?? "lb") × \(r)")
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(i == 0 ? GymTheme.accentBright : GymTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(i == 0 ? GymTheme.accent.opacity(0.08) : .clear)
                                .overlay(Capsule().strokeBorder(
                                    i == 0 ? GymTheme.accent.opacity(0.55) : Color.primary.opacity(0.16),
                                    lineWidth: 1.5))
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()
            Button("None of these — try again") { Task { await startListening() } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(GymTheme.accent)
                .padding(.bottom, 24)
        }
    }

    // MARK: B5 — Partial parse: chip with "? reps", keep listening

    private func awaitingRepsView(_ draft: SetDraft, _ match: ExerciseMatch) -> some View {
        VStack(spacing: 0) {
            Text("Got the weight — how many reps?")
                .font(.system(size: 21, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                .padding(.horizontal, 24)

            ParsedChipView(title: chipTitle(match), draft: draft,
                           emphasized: true, missingReps: true)
                .padding(.top, 28)

            WaveformView(barCount: 6, maxHeight: 32)
                .padding(.top, 30)
            Text("Listening for the rest…")
                .font(.system(size: 13))
                .foregroundStyle(GymTheme.textTertiary)
                .padding(.top, 12)

            Spacer()
            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.5))
                .padding(.bottom, 24)
        }
    }

    // MARK: B4 — Error

    private func errorView(_ message: String, _ heard: String?) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06)).frame(width: 64, height: 64)
                Image(systemName: "mic.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary.opacity(0.35))
            }
            .padding(.top, 36)

            Text(message)
                .font(.system(size: 21, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .padding(.horizontal, 24)

            if let heard, !heard.isEmpty {
                Text("Heard: “\(heard)”")
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(GymTheme.textTertiary)
                    .padding(.top, 10)
            }

            Spacer()
            Button("Try again") { Task { await startListening() } }
                .buttonStyle(SheetPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private var idleView: some View {
        VStack {
            Spacer()
            Button { Task { await startListening() } } label: {
                ZStack {
                    Circle()
                        .fill(GymTheme.accent.opacity(0.15))
                        .overlay(Circle().strokeBorder(GymTheme.accent.opacity(0.4), lineWidth: 1.5))
                        .frame(width: 76, height: 76)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(GymTheme.accent)
                }
            }
            Text("Tap to start listening")
                .font(.system(size: 13))
                .foregroundStyle(GymTheme.textTertiary)
                .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: Flow

    private func startListening() async {
        guard await speech.requestPermissions() else {
            phase = .error(message: "Microphone access needed",
                           heard: nil)
            return
        }
        do {
            try speech.startListening()
            withAnimation(.snappy) { phase = .listening }
        } catch let e as SpeechService.SpeechError {
            phase = .error(message: e.errorDescription ?? "Couldn't start the mic", heard: nil)
        } catch {
            phase = .error(message: "Couldn't start the mic — try again", heard: nil)
        }
    }

    private func handle(transcript: String) {
        heardTranscript = transcript

        // B5 continuation: we were waiting for reps only.
        if case .awaitingReps(var draft, let match) = phase {
            let normalized = NumberNormalizer.normalize(transcript)
            if let reps = normalized.split(separator: " ").compactMap({ Int($0) }).first {
                draft.reps = reps
                finishWith(draft, match)
            } else {
                phase = .error(message: "Didn't catch a rep count — try again",
                               heard: transcript)
            }
            return
        }

        let result = coordinator.preview(transcript)
        switch result {
        case .valid(let draft, .unresolved(let spoken, let sugg), _):
            withAnimation(.snappy) { phase = .suggestions(draft, sugg, heard: spoken) }

        case .valid(let draft, let match, _):
            if confirmFirst {
                withAnimation(.snappy) { phase = .confirm(draft, match) }
            } else {
                finishWith(draft, match)
            }

        case .invalid(.missingReps, _):
            // B5: salvage the weight, keep listening for reps.
            if let partial = partialDraft(from: transcript) {
                withAnimation(.snappy) { phase = .awaitingReps(partial.0, partial.1) }
                Task { try? speech.startListening() }
            } else {
                phase = .error(message: "Didn't catch that — try again", heard: transcript)
            }

        case .invalid(let problem, let raw):
            withAnimation(.snappy) {
                phase = .error(message: errorMessage(problem), heard: raw)
            }
        }
    }

    private func finishWith(_ draft: SetDraft, _ match: ExerciseMatch) {
        coordinator.commit(draft, match)
        haptic()
        dismiss()
    }

    /// Re-parse permissively to salvage a weight-only draft for the B5 flow.
    private func partialDraft(from transcript: String) -> (SetDraft, ExerciseMatch)? {
        var prefs = coordinator.prefs
        prefs.allowWeightOnlyDraft = true
        let result = coordinator.parser.parse(
            transcript,
            currentExerciseName: coordinator.currentExercise?.exerciseName,
            prefs: prefs)
        if case .valid(let d, let m, _) = result, d.weight != nil, d.reps == nil {
            return (d, m)
        }
        return nil
    }

    private func errorMessage(_ p: ParseProblem) -> String {
        switch p {
        case .ambiguousNumbers: return "Which one is the weight?\nSay “pounds” or “for”"
        case .missingWeight: return "How much weight?"
        case .noExerciseContext: return "Which exercise?\nSay the name with your first set"
        default: return "Didn't catch that — try again"
        }
    }

    private func chipTitle(_ match: ExerciseMatch) -> String {
        switch match {
        case .matched(let ex): return ex.name
        case .inherit: return coordinator.currentExercise?.exerciseName ?? "Current"
        case .unresolved(let spoken, _): return spoken
        case .missing: return "—"
        }
    }

    private func haptic() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Sheet buttons (52pt, radius 16 — mockup B2/B4)

struct SheetPrimaryButtonStyle: ButtonStyle {
    var flex: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(GymTheme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(GymTheme.accent)
                    .shadow(color: GymTheme.accent.opacity(0.25), radius: 10, y: 6)
            )
            .layoutPriority(flex)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SheetSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
