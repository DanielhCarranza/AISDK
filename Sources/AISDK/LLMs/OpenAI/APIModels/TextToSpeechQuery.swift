//
//  TextToSpeechQuery.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 28/09/24.
//

import Foundation
import Alamofire
import Combine
import AudioToolbox

// MARK: - Speech Formats

enum SpeechFormat: String, Codable, CaseIterable {
    case mp3
    case aac
    
    var fileType: AudioFileTypeID {
        switch self {
        case .mp3: return kAudioFileMP3Type
        case .aac: return kAudioFileAAC_ADTSType
        }
    }
}

// MARK: - Speech Voices

enum SpeechVoice: String, Codable, CaseIterable {
    case alloy
    case echo
    case fable
    case onyx
    case nova
    case shimmer
}

// MARK: - Speech Models

enum SpeechModel: String, Codable, CaseIterable {
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"
}

// MARK: - TextToSpeech Query

struct TextToSpeechQuery: Codable {
    let input: String
    let model: SpeechModel = .tts1HD
    let voice: SpeechVoice = .alloy
    let format: SpeechFormat = .mp3
    let stream: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case model
        case voice
        case format = "response_format"
        case stream
        case input
    }
}
