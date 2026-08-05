// SpeechService.swift — spec §7.3. Add to the Xcode app target.
// Wraps SFSpeechRecognizer: permissions, on-device-only recognition,
// contextual gym vocabulary, and trailing-silence auto-stop (~1.2s).
//
// Info.plist keys required:
//   NSSpeechRecognitionUsageDescription — "Used to transcribe your spoken sets."
//   NSMicrophoneUsageDescription        — "Used to hear you log a set."

import Foundation
import Speech
import AVFoundation
import GymLogCore

@MainActor
final class SpeechService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle, requestingPermission, listening, denied, error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var liveTranscript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?

    /// Trailing silence before auto-stop (spec: ~1.2s).
    var silenceWindow: TimeInterval = 1.2
    /// Gym vocabulary bias, fed from the catalog.
    var contextualStrings: [String] = ExerciseCatalog.seed.contextualStrings
    /// Called with the final transcript when capture ends.
    var onFinalTranscript: ((String) -> Void)?

    // MARK: Permissions

    func requestPermissions() async -> Bool {
        state = .requestingPermission
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        if !(speechOK && micOK) { state = .denied }
        return speechOK && micOK
    }

    // MARK: Capture

    func startListening() throws {
        guard state != .listening else { return }
        liveTranscript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Privacy + offline: on-device only (server fallback is an opt-in pref).
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.liveTranscript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal { self.finish() }
                }
                if error != nil { self.finish() }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening
        resetSilenceTimer()
    }

    /// Press-and-hold release, or manual stop.
    func stopListening() { finish() }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceWindow, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func finish() {
        guard state == .listening else { return }
        silenceTimer?.invalidate()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil; request = nil
        state = .idle
        let final = liveTranscript
        if !final.isEmpty { onFinalTranscript?(final) }
    }
}
