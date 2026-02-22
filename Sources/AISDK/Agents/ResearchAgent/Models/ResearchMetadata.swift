//
//  ResearchMetadata.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation
import SwiftUI

/// Metadata for tracking research progress and results
public struct ResearchMetadata: ToolMetadata {
    /// The topic being researched
    public let topic: String
    
    /// The start time of the research
    public let startTime: Date
    
    /// The end time of the research (if completed)
    public let endTime: Date?
    
    /// List of sources examined
    public let sources: [ResearchSource]
    
    /// Current state of the research
    public let state: ResearcherLegacyAgentState
    
    /// Any hypotheses generated
    public let hypotheses: [String]
    
    /// Research quality assessment
    public let qualityScore: Double?
    
    /// The tool that generated this metadata
    public let toolName: String?
    
    /// SF Symbol icon name for the current state or tool
    public let icon: String
    
    /// Color name associated with this research metadata
    public let colorName: String
    
    /// Computed property to get the SwiftUI Color
    public var color: Color {
        switch colorName {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink": return .pink
        case "indigo": return .indigo
        case "cyan": return .cyan
        case "mint": return .mint
        case "teal": return .teal
        case "gray", "grey": return .gray
        default: return .primary
        }
    }
    
    public init(
        topic: String,
        startTime: Date,
        endTime: Date? = nil,
        sources: [ResearchSource] = [],
        state: ResearcherLegacyAgentState,
        hypotheses: [String] = [],
        qualityScore: Double? = nil,
        toolName: String? = nil,
        icon: String? = nil,
        colorName: String? = nil
    ) {
        self.topic = topic
        self.startTime = startTime
        self.endTime = endTime
        self.sources = sources
        self.state = state
        self.hypotheses = hypotheses
        self.qualityScore = qualityScore
        self.toolName = toolName
        
        // Default icon based on state if not provided
        self.icon = icon ?? state.stateIcon
        
        // Default color based on state
        if let colorName = colorName {
            self.colorName = colorName
        } else {
            // Map state to color name
            switch state {
            case .idle: self.colorName = "gray"
            case .start: self.colorName = "blue"
            case .processing: self.colorName = "orange"
            case .completed: self.colorName = "green"
            }
        }
    }
    
    /// Creates a new metadata with updated sources
    public func addingSource(_ source: ResearchSource) -> ResearchMetadata {
        var updatedSources = self.sources
        updatedSources.append(source)
        
        return ResearchMetadata(
            topic: self.topic,
            startTime: self.startTime,
            endTime: self.endTime,
            sources: updatedSources,
            state: self.state,
            hypotheses: self.hypotheses,
            qualityScore: self.qualityScore,
            toolName: self.toolName,
            icon: self.icon,
            colorName: self.colorName
        )
    }
    
    /// Creates a new metadata with completed state
    public func completed() -> ResearchMetadata {
        return ResearchMetadata(
            topic: self.topic,
            startTime: self.startTime,
            endTime: Date(),
            sources: self.sources,
            state: .completed(topic: self.topic, startTime: self.startTime, endTime: Date(), sourceCount: self.sources.count),
            hypotheses: self.hypotheses,
            qualityScore: self.qualityScore,
            toolName: "complete_research",
            icon: "checkmark.circle.trianglebadge.exclamationmark",
            colorName: "green"
        )
    }
}

/// Represents a research source with citation information
public struct ResearchSource: Codable, Identifiable, Sendable {
    public var id: String { url.absoluteString }
    
    /// The title of the source
    public let title: String
    
    /// URL to the source
    public let url: URL
    
    /// Publication date
    public let publishDate: Date
    
    /// Authors of the publication
    public let authors: [String]
    
    /// Evidence quality rating (0-1)
    public let evidenceQuality: Double?
    
    /// Relevance score to the research topic (0-1)
    public let relevanceScore: Double?
    
    /// Type of source (study, review, etc)
    public let sourceType: String?
    
    public init(
        title: String,
        url: URL,
        publishDate: Date,
        authors: [String],
        evidenceQuality: Double? = nil,
        relevanceScore: Double? = nil,
        sourceType: String? = nil
    ) {
        self.title = title
        self.url = url
        self.publishDate = publishDate
        self.authors = authors
        self.evidenceQuality = evidenceQuality
        self.relevanceScore = relevanceScore
        self.sourceType = sourceType
    }
    
    /// Formats the source as a citation
    public func formattedCitation() -> String {
        let authorText = authors.isEmpty ? "" : authors.joined(separator: ", ") + ". "
        let year = Calendar.current.component(.year, from: publishDate)
        return "\(authorText)(\(year)). \(title). Retrieved from \(url.absoluteString)"
    }
} 
