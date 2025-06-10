//
//  VoiceActivityDetector.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 01/10/24.
//

import Foundation
import AVFoundation
import Combine

// Protocol defining methods for notifying about voice activity changes
protocol VoiceActivityDetectorDelegate: AnyObject {
    func voiceActivityDetectorDidDetectSilence(_ detector: VoiceActivityDetector)
    func voiceActivityDetectorDidDetectAudio(_ detector: VoiceActivityDetector)
}

/// A class responsible for detecting voice activity and silence in audio input
final class VoiceActivityDetector: NSObject {
    // MARK: - Properties
    
    private let silenceThreshold: Float // Decibel level below which audio is considered silence
    private let silenceDuration: TimeInterval // Duration of silence required to trigger silence detection
    private var silenceTimer: Timer? // Timer to track sustained silence
    
    private var audioRecorder: AVAudioRecorder? // Used for monitoring audio levels without recording
    private var audioSession: AVAudioSession // Manages audio session settings
    
    weak var delegate: VoiceActivityDetectorDelegate? // Notified of voice activity changes
    
    private var isMonitoring: Bool = false // Indicates if VAD is currently active
    
    // MARK: - Initialization
    
    /// Initializes the VoiceActivityDetector with customizable silence parameters
    /// - Parameters:
    ///   - silenceThreshold: Decibel level for silence detection (default: -50.0)
    ///   - silenceDuration: Duration of silence required (default: 2.0 seconds)
    init(silenceThreshold: Float = -50.0, silenceDuration: TimeInterval = 3.0) {
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.audioSession = AVAudioSession.sharedInstance()
        super.init()
        setupAudioRecorder()
    }
    
    // MARK: - Setup
    
    /// Configures the audio recorder for monitoring audio levels
    private func setupAudioRecorder() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue
        ]
        
        do {
            // Using /dev/null as we don't need to save the audio, just monitor levels
            audioRecorder = try AVAudioRecorder(url: URL(fileURLWithPath: "/dev/null"),
                                               settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.delegate = self
        } catch {
            print("VoiceActivityDetector: Failed to set up audio recorder: \(error)")
        }
    }
    
    // MARK: - Monitoring Control
    
    /// Starts monitoring audio input for voice activity
    func startMonitoring() {
        guard !isMonitoring, let recorder = audioRecorder else { return }
        
        do {
            // Configure audio session for recording
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recorder.record()
            isMonitoring = true
            
            // Periodically check audio levels
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                self?.checkAudioLevel()
            }
        } catch {
            print("VoiceActivityDetector: Failed to start monitoring: \(error)")
        }
    }
    
    /// Stops monitoring audio input
    func stopMonitoring() {
        guard isMonitoring, let recorder = audioRecorder else { return }
        
        recorder.stop()
        isMonitoring = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceActivityDetector: Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Audio Level Checking
    
    /// Checks the current audio level and manages silence detection
    private func checkAudioLevel() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()
        let averagePower = recorder.averagePower(forChannel: 0)
        
        if averagePower < silenceThreshold {
            // Silence detected, start or continue silence timer
            if silenceTimer == nil {
                startSilenceTimer()
                delegate?.voiceActivityDetectorDidDetectSilence(self)
            }
        } else {
            // Audio detected, reset silence timer
            resetSilenceTimer()
            delegate?.voiceActivityDetectorDidDetectAudio(self)
        }
    }
    
    /// Starts the timer to track sustained silence
    private func startSilenceTimer() {
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
            self?.silenceTimerFired()
        }
    }
    
    /// Resets the silence timer when audio is detected
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    /// Called when sustained silence is detected for the specified duration
    private func silenceTimerFired() {
        delegate?.voiceActivityDetectorDidDetectSilence(self)
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceActivityDetector: AVAudioRecorderDelegate {
    /// Handles audio recorder encoding errors
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("VoiceActivityDetector: Audio recorder encoding error: \(error)")
        }
    }
}
