//
//  ResearcherLegacyAgentState.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation
import SwiftUI

/// Represents the current state of the research process
public enum ResearcherLegacyAgentState: Equatable, Codable {
    case idle
    case start(topic: String, startTime: Date)
    case processing(topic: String, startTime: Date, sourceCount: Int)
    case completed(topic: String, startTime: Date, endTime: Date, sourceCount: Int)
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type, topic, startTime, endTime, sourceCount
    }
    
    private enum StateType: String, Codable {
        case idle, start, processing, completed
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .idle:
            try container.encode(StateType.idle, forKey: .type)
            
        case .start(let topic, let startTime):
            try container.encode(StateType.start, forKey: .type)
            try container.encode(topic, forKey: .topic)
            try container.encode(startTime, forKey: .startTime)
            
        case .processing(let topic, let startTime, let sourceCount):
            try container.encode(StateType.processing, forKey: .type)
            try container.encode(topic, forKey: .topic)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(sourceCount, forKey: .sourceCount)
            
        case .completed(let topic, let startTime, let endTime, let sourceCount):
            try container.encode(StateType.completed, forKey: .type)
            try container.encode(topic, forKey: .topic)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(endTime, forKey: .endTime)
            try container.encode(sourceCount, forKey: .sourceCount)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StateType.self, forKey: .type)
        
        switch type {
        case .idle:
            self = .idle
            
        case .start:
            let topic = try container.decode(String.self, forKey: .topic)
            let startTime = try container.decode(Date.self, forKey: .startTime)
            self = .start(topic: topic, startTime: startTime)
            
        case .processing:
            let topic = try container.decode(String.self, forKey: .topic)
            let startTime = try container.decode(Date.self, forKey: .startTime)
            let sourceCount = try container.decode(Int.self, forKey: .sourceCount)
            self = .processing(topic: topic, startTime: startTime, sourceCount: sourceCount)
            
        case .completed:
            let topic = try container.decode(String.self, forKey: .topic)
            let startTime = try container.decode(Date.self, forKey: .startTime)
            let endTime = try container.decode(Date.self, forKey: .endTime)
            let sourceCount = try container.decode(Int.self, forKey: .sourceCount)
            self = .completed(topic: topic, startTime: startTime, endTime: endTime, sourceCount: sourceCount)
        }
    }
    
    // MARK: - Helper Properties
    
    /// Whether the agent is in idle state
    public var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
    
    /// Whether the agent is actively researching
    public var isResearching: Bool {
        switch self {
        case .idle, .completed:
            return false
        case .start, .processing:
            return true
        }
    }
    
    /// The elapsed time since research began
    public var elapsedTime: TimeInterval? {
        switch self {
        case .idle:
            return nil
        case .start(_, let startTime), .processing(_, let startTime, _):
            return Date().timeIntervalSince(startTime)
        case .completed(_, let startTime, let endTime, _):
            return endTime.timeIntervalSince(startTime)
        }
    }
    
    /// The number of sources analyzed so far
    public var sourceCount: Int {
        switch self {
        case .idle, .start:
            return 0
        case .processing(_, _, let count):
            return count
        case .completed(_, _, _, let count):
            return count
        }
    }
    
    /// The topic being researched
    public var topic: String? {
        switch self {
        case .idle:
            return nil
        case .start(let topic, _), .processing(let topic, _, _), .completed(let topic, _, _, _):
            return topic
        }
    }
    
    /// Whether the research is completed
    public var isCompleted: Bool {
        if case .completed = self {
            return true
        }
        return false
    }
    
    // MARK: - UI Helper Properties
    
    /// Returns a human-readable description of the current state
    public var description: String {
        switch self {
        case .idle:
            return "Ready to start research"
        case .start(let topic, _):
            return "Starting research on: \(topic)"
        case .processing(let topic, _, let count):
            return "Researching: \(topic) (Sources: \(count))"
        case .completed(let topic, _, _, let count):
            return "Research complete: \(topic) (Sources: \(count))"
        }
    }
    
    /// Returns a color representing the current state
    public var stateColor: Color {
        switch self {
        case .idle:
            return .gray
        case .start:
            return .blue
        case .processing:
            return .orange
        case .completed:
            return .green
        }
    }
    
    /// Returns an icon representing the current state
    public var stateIcon: String {
        switch self {
        case .idle:
            return "doc.text.magnifyingglass"
        case .start:
            return "arrow.triangle.turn.up.right.circle"
        case .processing:
            return "doc.text.magnifyingglass"
        case .completed:
            return "checkmark.circle"
        }
    }
} 