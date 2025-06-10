//
//  TestWearableBiomarkersTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving wearable device biomarker data
struct TestWearableBiomarkersTool: Tool {
    let name = "get_wearable_data"
    let description = "Retrieve health biomarker data from wearable devices"
    
    /// Time period for data retrieval
    @Parameter(description: "Time period for data retrieval", validation: ["enum": ["day", "week", "month", "year"]])
    var timePeriod: String = "week"
    
    /// Specific metrics to retrieve
    @Parameter(description: "Specific biomarkers to retrieve (comma-separated)")
    var metrics: String = "all"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Wearable Biomarkers: \(metrics) over \(timePeriod)",
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Wearable Data Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_wearable_data",
            icon: "heart.text.square",
            colorName: "red"
        )
        
        // Generate response with XML-like tags
        let content = """
        <wearable_data>
            <summary>
                Wearable data for the past \(timePeriod). Metrics: \(metrics == "all" ? "All biomarkers" : metrics)
            </summary>
            
            <heart_rate>
                <average>72 bpm</average>
                <min>58 bpm</min>
                <max>142 bpm</max>
                <trend>Stable with slight decrease during sleep hours</trend>
                <readings>
                    <reading timestamp="2023-12-01T08:00:00">68 bpm</reading>
                    <reading timestamp="2023-12-01T12:00:00">78 bpm</reading>
                    <reading timestamp="2023-12-01T16:00:00">84 bpm</reading>
                    <reading timestamp="2023-12-01T20:00:00">72 bpm</reading>
                    <reading timestamp="2023-12-02T00:00:00">62 bpm</reading>
                </readings>
            </heart_rate>
            
            <heart_rate_variability>
                <average>45 ms</average>
                <min>32 ms</min>
                <max>68 ms</max>
                <trend>Increasing during rest periods, indicating good recovery</trend>
            </heart_rate_variability>
            
            <step_count>
                <daily_average>8,240 steps</daily_average>
                <highest_day>12,546 steps (Tuesday)</highest_day>
                <lowest_day>5,872 steps (Sunday)</lowest_day>
            </step_count>
            
            <sleep>
                <average_duration>7h 12m</average_duration>
                <deep_sleep_percentage>22%</deep_sleep_percentage>
                <rem_percentage>18%</rem_percentage>
                <sleep_efficiency>89%</sleep_efficiency>
                <notable>Consistent sleep schedule with good efficiency</notable>
            </sleep>
            
            <blood_oxygen>
                <average>98%</average>
                <min>96%</min>
                <max>99%</max>
            </blood_oxygen>
            
            <stress_score>
                <average>28 (Low)</average>
                <max>65 (Medium) on Monday morning</max>
                <trend>Decreasing through the week</trend>
            </stress_score>
        </wearable_data>
        """
        
        return (content: content, metadata: metadata)
    }
} 