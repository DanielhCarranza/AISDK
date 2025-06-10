//
//  TestHealthJournalTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving personal health journal entries
struct TestHealthJournalTool: Tool {
    let name = "get_health_journal"
    let description = "Retrieve personal health journal entries including symptoms, nutrition, and activities"
    
    /// Type of journal entries to retrieve
    @Parameter(description: "Type of entries to retrieve", validation: ["enum": ["symptoms", "nutrition", "activities", "mood", "all"]])
    var entryType: String = "all"
    
    /// Number of entries to retrieve
    @Parameter(description: "Number of recent entries to retrieve")
    var count: String = "10"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Health Journal: \(entryType) (last \(count) entries)",
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Health Journal Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_health_journal",
            icon: "book.closed",
            colorName: "teal"
        )
        
        // Generate response with XML-like tags
        let content = """
        <health_journal>
            <summary>
                Personal health journal entries. Type: \(entryType), Count: \(count)
            </summary>
            
            <entry date="2023-11-15" type="symptoms">
                <content>Felt unusually tired today despite adequate sleep. Minor headache in the afternoon that went away after taking a break from screen. Blood sugar reading before dinner: 142 mg/dL.</content>
                <tags>fatigue, headache, blood sugar</tags>
                <severity>mild</severity>
            </entry>
            
            <entry date="2023-11-12" type="nutrition">
                <content>Breakfast: Oatmeal with berries and nuts. Lunch: Grilled chicken salad with olive oil dressing. Dinner: Baked salmon with steamed vegetables. Snacks: Apple, handful of almonds. Water intake: ~2.5 liters.</content>
                <metrics>
                    <calories>1850</calories>
                    <carbs>160g</carbs>
                    <protein>110g</protein>
                    <fat>70g</fat>
                </metrics>
                <notes>Felt satisfied with meals today. No cravings for sweets.</notes>
            </entry>
            
            <entry date="2023-11-10" type="activities">
                <content>Morning walk: 30 minutes at moderate pace. Light stretching session in the afternoon. Took the stairs instead of elevator at work.</content>
                <metrics>
                    <steps>8240</steps>
                    <active_minutes>45</active_minutes>
                    <calories_burned>320</calories_burned>
                </metrics>
                <notes>Energy level improved after morning walk. BP after exercise: 125/80.</notes>
            </entry>
            
            <entry date="2023-11-08" type="mood">
                <content>Started the day feeling positive. Mild stress in the afternoon due to work deadline. Evening was relaxed after completing tasks.</content>
                <mood_score>7/10</mood_score>
                <stress_level>4/10</stress_level>
                <coping_strategies>Deep breathing, short walk, listening to calming music</coping_strategies>
            </entry>
            
            <entry date="2023-11-05" type="symptoms">
                <content>Mild indigestion after dinner. Possibly related to new spicy food tried. No other symptoms noted.</content>
                <tags>indigestion, digestive</tags>
                <severity>mild</severity>
                <duration>approximately 2 hours</duration>
            </entry>
            
            <patterns>
                <pattern>Fatigue tends to increase on days with less physical activity</pattern>
                <pattern>Blood sugar readings are lower on days with morning exercise</pattern>
                <pattern>Mood scores correlate positively with protein intake and sleep quality</pattern>
            </patterns>
        </health_journal>
        """
        
        return (content: content, metadata: metadata)
    }
} 