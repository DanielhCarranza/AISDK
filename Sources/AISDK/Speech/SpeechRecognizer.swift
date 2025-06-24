import Foundation
import Speech
import AVFoundation
import SwiftUI

/// Native iOS Speech Recognition implementation for iOS 17+
/// Provides the same interface as SpeziSpeechRecognizer for drop-in replacement
#if os(iOS)
@available(iOS 17.0, *)
@Observable
public class SpeechRecognizer: NSObject {
    
    // MARK: - Public Properties
    private(set) var isRecording = false
    
    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    // Stream continuation for async results
    private var streamContinuation: AsyncThrowingStream<SFSpeechRecognitionResult, Error>.Continuation?
    
    // MARK: - Initialization
    public override init() {
        super.init()
        setupSpeechRecognizer()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Methods
    
    /// Starts speech recognition and returns an async stream of results
    /// - Returns: AsyncThrowingStream that yields SFSpeechRecognitionResult objects
    func start() -> AsyncThrowingStream<SFSpeechRecognitionResult, Error> {
        return AsyncThrowingStream { continuation in
            self.streamContinuation = continuation
            
            Task { @MainActor in
                do {
                    try await self.startRecording()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stop()
                }
            }
        }
    }
    
    /// Stops speech recognition
    func stop() {
        isRecording = false
        
        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Finish the stream
        streamContinuation?.finish()
        streamContinuation = nil
    }
    
    // MARK: - Private Methods
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer?.delegate = self
    }
    
    @MainActor
    private func startRecording() async throws {
        // Check if speech recognition is available
        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerNotAvailable
        }
        
        // Request authorization if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let newStatus = await requestSpeechAuthorization()
            guard newStatus == .authorized else {
                throw SpeechRecognitionError.authorizationDenied
            }
        }
        
        // Request microphone permission
        if #available(iOS 17.0, *) {
            let micStatus = AVAudioApplication.shared.recordPermission
            if micStatus != .granted {
                let granted = await requestMicrophonePermission()
                guard granted else {
                    throw SpeechRecognitionError.microphonePermissionDenied
                }
            }
        } else {
            let micStatus = AVAudioSession.sharedInstance().recordPermission
            if micStatus != .granted {
                let granted = await requestMicrophonePermissionLegacy()
                guard granted else {
                    throw SpeechRecognitionError.microphonePermissionDenied
                }
            }
        }
        
        // Cancel any previous task
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        // Configure audio session
        try configureAudioSession()
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.unableToCreateRequest
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                // Yield the result to the stream
                self.streamContinuation?.yield(result)
                
                // If this is the final result, finish the stream
                if result.isFinal {
                    self.streamContinuation?.finish()
                    Task { @MainActor in
                        self.stop()
                    }
                }
            }
            
            if let error = error {
                self.streamContinuation?.finish(throwing: error)
                Task { @MainActor in
                    self.stop()
                }
            }
        }
        
        // Start audio engine
        try startAudioEngine()
        
        isRecording = true
    }
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    @available(iOS 17.0, *)
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func requestMicrophonePermissionLegacy() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechRecognizer: SFSpeechRecognizerDelegate {
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available && isRecording {
            stop()
        }
    }
}

// MARK: - Error Types
public enum SpeechRecognitionError: LocalizedError {
    case recognizerNotAvailable
    case authorizationDenied
    case microphonePermissionDenied
    case unableToCreateRequest
    case audioEngineError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .authorizationDenied:
            return "Speech recognition authorization denied"
        case .microphonePermissionDenied:
            return "Microphone permission denied"
        case .unableToCreateRequest:
            return "Unable to create speech recognition request"
        case .audioEngineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        }
    }
}
#endif