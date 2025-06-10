//
//  SearchMedicalEvidenceTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Tool for searching medical databases for evidence
struct SearchMedicalEvidenceToolR: Tool {
    let name = "search_medical_evidence"
    let description = "Search medical databases for relevant evidence"
    
    /// Search query
    @Parameter(description: "Search query for medical evidence")
    var query: String = ""
    
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
         // Simulate finding research papers
        let sources = [
            ResearchSource(
                title: "Recent Advances in \(query) Research",
                url: URL(string: "https://medical-research.org/papers/123")!,
                publishDate: Date(),
                authors: ["Dr. Smith", "Dr. Johnson"],
                evidenceQuality: 0.85,
                relevanceScore: 0.9,
                sourceType: "systematic review"
            ),
            ResearchSource(
                title: "Clinical Outcomes of \(query) Treatments",
                url: URL(string: "https://medical-research.org/papers/456")!,
                publishDate: Date().addingTimeInterval(-7_776_000), // 90 days ago
                authors: ["Dr. Williams", "Dr. Brown"],
                evidenceQuality: 0.75,
                relevanceScore: 0.8,
                sourceType: "clinical trial"
            ),
            ResearchSource(
                title: "Recent Advances in \(query) Research",
                url: URL(string: "https://medical-research.org/papers/123")!,
                publishDate: Date(),
                authors: ["Dr. Smith", "Dr. Johnson"],
                evidenceQuality: 0.85,
                relevanceScore: 0.9,
                sourceType: "systematic review"
            )
        ]

        // Create metadata with the new sources
        let metadata = ResearchMetadata(
            topic: query,
            startTime: Date().addingTimeInterval(-60), // Simulate started 1 minute ago
            sources: sources,
            state: .processing(topic: query, startTime: Date().addingTimeInterval(-1200), sourceCount: sources.count),
            toolName: "search_medical_evidence",
            icon: "doc.text.magnifyingglass",
            colorName: "orange"
        )
        
        // Format the response
        let content = "Imagine you found some evidence about the query \(query) but continue with the tool `read_evidence` to read the evidence and `reason_evidence` to reason about the evidence."
        
        return (content: content, metadata: metadata)
    }
    

} 
