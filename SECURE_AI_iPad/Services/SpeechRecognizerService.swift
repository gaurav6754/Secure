import Foundation
import Speech
import AVFoundation

struct VoiceLanguageOption: Identifiable, Hashable {
    let id: String // BCP-47 locale ID
    let label: String

    static let supported: [VoiceLanguageOption] = [
        .init(id: "en-IN", label: "English (India)"),
        .init(id: "hi-IN", label: "Hindi (हिन्दी)"),
        .init(id: "bn-IN", label: "Bengali (বাংলা)"),
        .init(id: "mr-IN", label: "Marathi (मराठी)"),
        .init(id: "ta-IN", label: "Tamil (தமிழ்)"),
        .init(id: "te-IN", label: "Telugu (తెలుగు)"),
        .init(id: "gu-IN", label: "Gujarati (ગુજરાતી)"),
        .init(id: "kn-IN", label: "Kannada (ಕನ್ನಡ)"),
        .init(id: "ml-IN", label: "Malayalam (മലയാളം)"),
        .init(id: "pa-IN", label: "Punjabi (ਪੰਜਾਬੀ)"),
        .init(id: "ur-IN", label: "Urdu (اردو)")
    ]
}

@MainActor
final class SpeechRecognizerService: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String? = nil

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func toggleRecording(localeIdentifier: String, onTextUpdate: @escaping (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(localeIdentifier: localeIdentifier, onTextUpdate: onTextUpdate)
        }
    }

    func startRecording(localeIdentifier: String, onTextUpdate: @escaping (String) -> Void) {
        errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self else { return }
                guard authStatus == .authorized else {
                    self.errorMessage = "Speech recognition permission denied. Enable it in iPad Settings > SECURE AI."
                    return
                }
                self.beginAudioSession(localeIdentifier: localeIdentifier, onTextUpdate: onTextUpdate)
            }
        }
    }

    private func beginAudioSession(localeIdentifier: String, onTextUpdate: @escaping (String) -> Void) {
        stopRecording()

        let locale = Locale(identifier: localeIdentifier)
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer unavailable for \(localeIdentifier)."
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        self.transcript = text
                        onTextUpdate(text)
                    }
                    if error != nil || (result?.isFinal == true) {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            errorMessage = "Microphone error: \(error.localizedDescription)"
            stopRecording()
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}
