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

    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition isn't available here"
            case .noAudioInput:
                return "No microphone on this device"
            }
        }
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    /// Guards inputNode access in finish(): touching the input node when no tap
    /// was ever installed raises an ObjC exception on mic-less simulators.
    private var tapInstalled = false

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
        guard let recognizer, recognizer.isAvailable else { throw SpeechError.recognizerUnavailable }
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
        // Mic-less environments (Simulator, Appetize) report a 0 Hz format;
        // installTap would then raise an ObjC exception `try` cannot catch.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.request = nil
            throw SpeechError.noAudioInput
        }
        // Defensive: installing over an existing tap is an uncatchable ObjC
        // exception; removing a nonexistent tap is a documented no-op.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        tapInstalled = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
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
        do {
            try audioEngine.start()
        } catch {
            finish()   // releases the tap/session/task so a retry can't double-install
            throw error
        }
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

    /// Idempotent teardown: releases whatever capture resources exist, in any
    /// state. Dismissing the sheet mid-permission-request, after a failed
    /// start, or mid-listening all funnel through here safely.
    private func finish() {
        let wasListening = state == .listening
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil; request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
        guard wasListening else { return }
        let final = liveTranscript
        if !final.isEmpty { onFinalTranscript?(final) }
    }
}
