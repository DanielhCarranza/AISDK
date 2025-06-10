//
//  StartResearchTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Tool for initiating a research process
struct StartResearchTool: Tool {
    let name = "start_research"
    let description = "Initialize research process and generate hypotheses and queries"
    
    /// Initial topic to research
    @Parameter(description: "Think about the patient intent and formulate the research objectives and queries to research")
    var think: String = " "
    
    /// Desired research depth
    @Parameter(description: "Desired research depth", validation: ["enum": ["basic", "standard", "comprehensive"]])
    var depth: String = "standard"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: think,
            startTime: Date().addingTimeInterval(-300), // 5 minutes ago
            sources: [],
            state: .processing(topic: think, startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "start_research",
            icon: "magnifyingglass.circle",
            colorName: "blue"
        )
    
        // Generate response
        let content = """
        \(think)
        """
        
        return (content: content, metadata: metadata)
    }
    
} 
