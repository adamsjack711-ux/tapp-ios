import AVFoundation
import Combine
import Speech
import UIKit

@MainActor
final class VoiceTranscriber: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var permissionTask: Task<Void, Never>?
    private var hasInputTap = false
    private var audioSessionActive = false
    private var recordingID: UUID?
    private var recordingLimit: Task<Void, Never>?

    func start() {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        errorMessage = nil
        permissionTask = Task {
            defer { isStarting = false; permissionTask = nil }
            let speechAllowed = await requestSpeechPermission()
            guard !Task.isCancelled else { return }
            guard speechAllowed else {
                errorMessage = "Allow speech recognition in Settings to ask by voice. You can still type a request."
                return
            }
            let microphoneAllowed = await requestMicrophonePermission()
            guard !Task.isCancelled else { return }
            guard microphoneAllowed else {
                errorMessage = "Allow microphone access in Settings to ask by voice. You can still type a request."
                return
            }
            // System permission dialogs make the scene temporarily inactive.
            // Wait briefly for their dismissal; never start in the background.
            for _ in 0..<20 {
                if UIApplication.shared.applicationState == .active { break }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
            beginRecording()
        }
    }

    func stop() {
        permissionTask?.cancel()
        recordingLimit?.cancel(); recordingLimit = nil
        recordingID = nil
        audioEngine.stop()
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now. Please type your request."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device dictation isn’t available for this language right now. Please type; audio won’t be sent to a server."
            return
        }
        transcript = ""
        let identifier = UUID()
        recordingID = identifier

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioSessionActive = true

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorMessage = "No microphone input is available. Please type your request."
                stop()
                return
            }
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInputTap = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.recordingID == identifier else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            recordingLimit = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)); self?.stop() } catch { }
            }
        } catch {
            errorMessage = "Recording couldn’t start. \(error.localizedDescription)"
            stop()
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}
