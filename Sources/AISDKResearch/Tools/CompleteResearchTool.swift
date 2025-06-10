//
//  CompleteResearchTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Tool for finalizing research and generating a report
struct CompleteResearchTool: Tool {
    let name = "complete_research"
    let description = "Finalize research and proceed to generate comprehensive report with citations"
    
    /// Collection of insights from evidence analysis
    @Parameter(description: "Collection of insights from evidence analysis", validation: ["enum": ["yes", "no"]])
    var completeResearch: String = "no"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate report generation
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create completed research metadata
        let metadata = ResearchMetadata(
            topic: completeResearch,
            startTime: Date().addingTimeInterval(-1800), // Started 30 minutes ago
            endTime: Date(),
            sources: [
                ResearchSource(
                    title: "Comprehensive Analysis of Medical Research",
                    url: URL(string: "https://medical-research.org/papers/final")!,
                    publishDate: Date(),
                    authors: ["Research Assistant"],
                    evidenceQuality: 0.95,
                    relevanceScore: 1.0,
                    sourceType: "report"
                )
            ],
            state: .completed(
                topic: completeResearch, 
                startTime: Date().addingTimeInterval(-1800),
                endTime: Date(),
                sourceCount: 43
            ),
            hypotheses: [],
            toolName: "complete_research",
            icon: "checkmark.circle.trianglebadge.exclamationmark",
            colorName: "green"
        )
        
        // Generate a direct markdown report
        let content = "Proceed to generate a report with the evidence we gather"
        
        return (content: content, metadata: metadata)
    }
    


} 
