import Foundation


/// Source metadata for attributing information
struct Source: ToolMetadata {
    let title: String
    let content: String?
    let url: String
    let evidenceType: String
    
    enum CodingKeys: String, CodingKey {
        case title
        case content
        case url
        case evidenceType = "evidence_type"
    }
    
    init(title: String, content: String? = nil, url: String, evidenceType: String) {
        self.title = title
        self.content = content
        self.url = url
        self.evidenceType = evidenceType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        url = try container.decode(String.self, forKey: .url)
        evidenceType = try container.decode(String.self, forKey: .evidenceType)
    }
}

struct Sources: ToolMetadata {
    let results: [Source]
}

/// Medical evidence metadata with sources and confidence information
struct MedicalEvidence: ToolMetadata {
    public let sources: [Source]
    public let evidenceLevel: String
    public let confidenceScore: Double?
    public let lastUpdated: Date
    
    public init(sources: [Source], evidenceLevel: String, confidenceScore: Double? = nil, lastUpdated: Date = Date()) {
        self.sources = sources
        self.evidenceLevel = evidenceLevel
        self.confidenceScore = confidenceScore
        self.lastUpdated = lastUpdated
    }
}


// MARK: - Medical Evidence Search Tool
struct SearchMedicalEvidenceTool: Tool {
    let name = "search_medical_evidence"
    let description = "Search for medical evidence and research about a specific health topic"
    
    private let aiService = AIService()
    
    init() {
    }
    
    @Parameter(description: "Health topic or medical condition to search for")
    var query: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?)  {
        let sources = try await aiService.searchMedicalEvidence(query: query)
        
        let content = """
        Medical Evidence Search Results for "\(query)":
        
        Found \(sources.results.count) relevant sources:
        \(sources.results.enumerated().map { index, source in
            """
            
            \(index + 1). \(source.title)
               Type: \(source.evidenceType)
               URL: \(source.url)
            """
        }.joined(separator: "\n"))
        """
        
        return (content: content, metadata: sources)
    }
}

// MARK: - Journal Entry Tool
struct LogJournalEntryTool: Tool {
    let name = "log_journal"
    let description = "Records health events, observations, triggers, symptoms, mood, and activities, nutrition, and medication"

    // Use a static journal instance to prevent deallocation
    private static let journal = Journal()
    
    init() {}
    
    @Parameter(description: "Entry to log. For example: 'I had a headache today'")
    var entry: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Create a new journal entry
        let journalEntry = JournalEntry(
            content: entry
        )

        if !entry.isEmpty {
            // Use the async version and await its completion
            try await Self.journal.saveAsync(entry: journalEntry, mediaData: nil, mediaType: nil)
            print("✅ Journal entry async save completed successfully")
        } else {
            return (content: "No entry provided and nothing was saved", metadata: nil)
        }   
        
        let timestamp = Date().formatted(date: .long, time: .shortened)
        
        let content = """
        Journal Entry Logged - \(timestamp)
        
        Entry: \(journalEntry.content)
        
        Entry has been saved to your health journal.
        Continue with your conversation.
        """
        
        return (content: content, metadata: nil)
    }
}

// MARK: - General Search Tool
struct GeneralSearchTool: Tool {
    let name = "general_search"
    let description = "Perform general web searches for non-medical queries"
    
    init() {}
    
    @Parameter(description: "Search query")
    var query: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        let content = """
        General Search Results for "\(query)":
        
        Top 3 relevant results:
        1. Understanding \(query) - Overview and basics
        2. Latest updates about \(query)
        3. Popular discussions about \(query)
        
        Note: This is simulated data. In production, this would return real search results \
        from a search engine API.
        """
        
        return (content: content, metadata: nil)
    }
}

// MARK: - Health Event Management Tool
struct ManageHealthEventTool: Tool {
    let name = "manage_health_event"
    let description = """
    Creates and manages significant health events in user's timeline.
    
    When to use:
    • Recording medical procedures
    • Logging significant health changes
    • Marking important health milestones
    • Documenting diagnoses
    • Tracking treatment changes
    """
    
    init() {}
    
    @Parameter(description: "Type of event", validation: ["enum": ["procedure", "diagnosis", "milestone", "change", "other"]])
    var eventType: String = "other"
    
    @Parameter(description: "Title of the health event")
    var title: String = ""
    
    @Parameter(description: "Date of the event (YYYY-MM-DD format)")
    var date: String = ""
    
    @Parameter(description: "Detailed description of the event")
    var eventDescription: String = ""
    
    @Parameter(description: "Healthcare provider involved (if applicable)")
    var provider: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let timestamp = Date().formatted(date: .long, time: .shortened)
        
        let content = """
        Health Event Recorded - \(timestamp)
        
        Type: \(eventType.capitalized)
        Title: \(title)
        Date: \(date)
        Provider: \(provider.isEmpty ? "Not specified" : provider)
        Description: \(eventDescription)
        
        ✅ Event has been added to your health timeline.

        Continue with your conversation.
        """
        
        return (content: content, metadata: nil)
    }
}

// MARK: - Health Report Management Tool
struct ManageHealthReportTool: Tool {
    let name = "manage_health_report"
    let description = """
    Generates or retrieves comprehensive health reports.
    
    When to use:
    • Preparing for doctor visits
    • Regular health reviews
    • Tracking long-term progress
    • Analyzing health trends
    • Summarizing health events
    """
    
    init() {}
    
    @Parameter(description: "Type of report operation", validation: ["enum": ["create", "get"]])
    var reportType: String = "create"
    
    @Parameter(description: "Start date for report range (YYYY-MM-DD format)")
    var startDate: String = ""
    
    @Parameter(description: "End date for report range (YYYY-MM-DD format)")
    var endDate: String = ""
    
    @Parameter(description: "Context or focus area for the report (e.g., 'medication', 'symptoms', 'all')")
    var context: String = "all"
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        
        let timestamp = Date().formatted(date: .long, time: .shortened)
        let operation = reportType == "create" ? "Generated" : "Retrieved"
        
        let content = """
        Health Report \(operation) - \(timestamp)
        
        Time Range: \(startDate) to \(endDate)
        Focus Area: \(context.capitalized)
        
        Summary:
        • Health Events: 5 significant events recorded
        • Journal Entries: 12 entries analyzed
        • Trends Identified: 3 patterns noted
        
        Note: This is simulated data. In production, this would generate a detailed \
        report based on actual health records and journal entries.
        
        Continue with your conversation.
        """
        
        return (content: content, metadata: nil)
    }
}

/// Think Tool - Allows the AI to document its reasoning process without affecting the database
struct ThinkTool: Tool {
    let name = "think"
    let description = "Use the tool to think about something. It will not obtain new information or change the database, but just append the thought to the log. Use it when complex reasoning or some cache memory is needed."
    
    init() {}
    
    @Parameter(description: "Your thoughts")
    var thought: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {

        let content = """
        Thinking: \(thought)
        """
        
        return (content: content, metadata: nil)
    }
} 
