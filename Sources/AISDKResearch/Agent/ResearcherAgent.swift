//
//  ResearcherAgent.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation
import Combine
import SwiftUI

/// A specialized agent for conducting medical research
@Observable
class ResearcherAgent {
    // MARK: - Properties
    
    /// The underlying agent for LLM interaction
    private let agent: ExperimentalResearchAgent
    
    /// The current state of the research process
    var state: ResearcherAgentState = .idle
    
    /// Timer for tracking research duration
    private var researchTimer: Timer?
    
    /// Publisher for timer updates (1-second intervals)
    var elapsedSeconds: Int = 0
    
    /// Metadata tracker for research progress
    private let metadataTracker = MetadataTracker()
    
    /// The messages in the current conversation
    var messages: [ChatMessage] = []
    
    /// Whether the agent is currently streaming a response
    var isStreaming: Bool = false
    
    /// Track accumulated sources during research
    private var accumulatedSources: [ResearchSource] = []
    
    // MARK: - Initialization
    
    /// Initializes a new ResearcherAgent
    public init() {
        // Define research-specific tools
        let researchTools: [Tool.Type] = [
            StartResearchTool.self,
            SearchMedicalEvidenceToolR.self,
            ReadEvidenceTool.self,
            ReasonEvidenceTool.self,
            SearchHealthProfileTool.self,
            CompleteResearchTool.self,
            // New specialized health data tools
            TestWearableBiomarkersTool.self,
            TestLabResultsTool.self,
            TestMedicalRecordsTool.self,
            TestHealthJournalTool.self,
            TestMedicalHistoryTool.self,
            TestTreatmentHistoryTool.self
            // TestQuestionnaireTool.self
        ]
        
        // Initialize the specialized prompt for research with updated instructions
        let researchInstructions = """
        You are a medical research assistant specialized in conducting evidence-based research.
        Your goal is to help users find accurate, up-to-date medical information through systematic research.
        
        Follow these research principles:
        1. Formulate clear research questions and hypotheses
        2. Search for high-quality evidence from reputable sources
        3. Evaluate evidence for quality, relevance, and applicability
        4. Synthesize findings into clear, actionable insights
        5. Present information with appropriate citations
        6. Acknowledge limitations and gaps in current knowledge

        Today is \(Date().formatted(date: .long, time: .omitted))

        ## Research Process
        Follow this systematic research workflow:
        1. START: Use `start_research` to formulate research questions and hypotheses
        2. DATA RETRIEVAL: Gather all relevant information from:
           - `search_medical_evidence` to find relevant medical literature
           - `get_health_profile` for overview of patient health data
           - For detailed patient data, use specialized data tools (see Tools section)
        3. READ: Use `read_evidence` to analyze individual sources in depth
        4. REASON: Use `reason_evidence` to synthesize findings and determine next steps
        5. REPEAT: Continue gathering evidence as needed
        6. COMPLETE: Use `complete_research` to prepare the final report

        ## Tools
        General Research Tools:
        - `start_research`: Initialize research, formulate questions and hypotheses
        - `search_medical_evidence`: Find published medical evidence and literature
        - `read_evidence`: Analyze and extract key information from sources
        - `reason_evidence`: Synthesize findings, identify patterns, and plan next steps
        - `get_health_profile`: Get an overview of the patient's health profile
        - `complete_research`: Finalize research and generate comprehensive report

        Specialized Health Data Tools:
        - `get_wearable_data`: Retrieve biomarker data from wearable devices (heart rate, HRV, sleep, etc.)
        - `get_lab_results`: Access laboratory test results and imaging reports 
        - `get_medical_records`: Retrieve clinical notes and visit summaries
        - `get_health_journal`: Access personal health journal entries (symptoms, nutrition, activities)
        - `get_medical_history`: Retrieve comprehensive medical history
        - `get_treatment_history`: Access medication and treatment history
        - `get_questionnaire_data`: Retrieve health assessment questionnaires and surveys
        
        ## When to Use Specialized Tools
        
        - Use `get_wearable_data` when:
          * Investigating physiological patterns or trends
          * Correlating symptoms with biometric measurements
          * Evaluating sleep quality, activity levels, or stress
          * Parameters: timePeriod (day/week/month/year), metrics (specific or "all")
        
        - Use `get_lab_results` when:
          * Reviewing diagnostic test results
          * Monitoring disease markers or treatment efficacy
          * Evaluating trends in biomarkers over time
          * Parameters: resultType (blood/imaging/pathology/all), timeframe
        
        - Use `get_medical_records` when:
          * Analyzing provider assessments and treatment plans
          * Reviewing specialist consultations
          * Understanding clinical reasoning
          * Parameters: recordType, specialty (optional)
        
        - Use `get_health_journal` when:
          * Investigating symptom patterns and triggers
          * Evaluating lifestyle factors (diet, exercise, sleep)
          * Understanding subjective experiences
          * Parameters: entryType, count (number of entries)
        
        - Use `get_medical_history` when:
          * Reviewing diagnoses and their progression
          * Assessing family history and risk factors
          * Evaluating surgical history
          * Parameters: historyType, bodySystem (optional)
        
        - Use `get_treatment_history` when:
          * Reviewing medication history and efficacy
          * Evaluating treatment adherence
          * Assessing therapeutic interventions
          * Parameters: treatmentType, status
        
        - Use `get_questionnaire_data` when:
          * Reviewing mental health assessments
          * Evaluating quality of life measures
          * Analyzing self-reported health data
          * Parameters: questionnaireType, timeContext

        ## Examples
        <examples>
        User: "Can you research the relationship between sleep quality and blood sugar control in diabetes?"
        
        Assistant: I'll research the relationship between sleep quality and blood sugar control in diabetes.
        
        [Uses start_research to formulate questions]
        
        To thoroughly investigate this topic, I should examine both medical evidence and patient-specific data. Let me check if there's relevant wearable data that might show patterns.
        
        [Uses get_wearable_data with parameters: timePeriod="month", metrics="sleep,heart_rate,blood_oxygen"]
        
        Now I'll examine whether your recent lab results show any blood glucose patterns.
        
        [Uses get_lab_results with parameters: resultType="blood", timeframe="recent"]
        
        Let me also check your health journal to see if you've noted any correlations between sleep and glucose readings.
        
        [Uses get_health_journal with parameters: entryType="all", count="20"]
        
        Now I'll search for medical evidence about this relationship.
        
        [Uses search_medical_evidence with query about sleep and diabetes]
        
        [Uses read_evidence to analyze findings]
        
        [Uses reason_evidence to synthesize conclusions]
        
        User: "I've been having more headaches lately. Can you research potential causes based on my health data?"
        
        Assistant: I'll research potential causes for your recent increase in headaches.
        
        [Uses start_research to formulate approach]
        
        First, let me look at your recent health journal entries to understand the headache patterns.
        
        [Uses get_health_journal with parameters: entryType="symptoms", count="15"]
        
        Let me check if there are any patterns in your wearable data that might correlate with headaches.
        
        [Uses get_wearable_data with parameters: timePeriod="week", metrics="stress,sleep,heart_rate"]
        
        I should also review your medical history for relevant conditions.
        
        [Uses get_medical_history with parameters: historyType="all"]
        
        Let me check your recent medical records for any insights.
        
        [Uses get_medical_records with parameters: recordType="all"]
        
        Now I'll search for medical evidence about potential headache triggers.
        
        [Uses search_medical_evidence with query about headache causes]
        
        [Uses reason_evidence to synthesize findings into practical recommendations]
        </examples>

        For each step, clearly explain what you're doing to the user. Present intermediate findings as you go.

        ## Final Report
        When the research is completed, generate a comprehensive report that includes:
        - Executive summary with key findings
        - Background and context for the research question
        - Methodology used to gather evidence
        - Detailed presentation of findings with analysis
        - Synthesis of information across sources
        - Practical implications and recommendations
        - Limitations and areas for further research
        - Complete citations for all sources
        
        Format the report in well-structured markdown with clear headings, bullet points where appropriate,
        and tables if relevant. The report should be accessible to the general reader while maintaining
        scientific accuracy.

        ## Output Language
        - The report should be in the language of the original question
        """
        
        // Initialize agent with o3-mini model and research tools
        do {
            self.agent = try ExperimentalResearchAgent(
                model: AgenticModels.o3mini,
                tools: researchTools,
                instructions: researchInstructions
            )
        } catch {
            fatalError("Failed to initialize researcher agent: \(error)")
        }
        
        // Add metadata tracker
        agent.addCallbacks(metadataTracker)
        
        // Add initial welcome message
        let welcomeMessage = ChatMessage(message: .assistant(content: .text("""
        Hello! I'm Cony, your personal health companion. How can I help you today?
        """)))
        
        messages.append(welcomeMessage)
        
        // Set up state change handling
        agent.onStateChange = { [weak self] agentState in
            DispatchQueue.main.async {
                // Handle agent state changes if needed
                print("Agent state changed: \(agentState)")
            }
        }
    }
    
    deinit {
        stopResearchTimer()
    }
    
    // MARK: - Public Methods
    
    /// Sends a message to the agent and receives a streamed response
    /// - Parameter content: The content of the message to send
    public func sendMessage(_ content: String) {
        let userMessage = ChatMessage(message: .user(content: .text(content)))
        messages.append(userMessage)
        
        // Start streaming response
        isStreaming = true
        
        Task {
            do {
                var accumulatedMetadata = [ToolMetadata]()
                
                // Stream the response
                for try await message in agent.sendStream(userMessage) {
                    await MainActor.run {
                        // Skip hidden messages (used for agent control)
                        if message.hidden {
                            return
                        }
                        
                        // Update last message if it's pending, or add a new one
                        if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                            messages[lastIndex] = message
                        } else {
                            var pendingMessage = message
                            pendingMessage.isPending = true
                            messages.append(pendingMessage)
                        }
                        
                        // Check for metadata and update research state
                        if let metadata = message.metadata as? ResearchMetadata {
                            accumulatedMetadata.append(metadata)
                            updateResearchState(with: metadata)
                            
                            // Keep track of sources for progress indication
                            if !metadata.sources.isEmpty {
                                // Add any new sources
                                for source in metadata.sources {
                                    if !accumulatedSources.contains(where: { $0.id == source.id }) {
                                        accumulatedSources.append(source)
                                    }
                                }
                                
                                // Update state with current source count
                                if case let .processing(topic, startTime, _) = state {
                                    state = .processing(topic: topic, startTime: startTime, sourceCount: accumulatedSources.count)
                                }
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    // Finalize the last message
                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                        messages[lastIndex].isPending = false
                    }
                    
                    isStreaming = false
                    metadataTracker.reset()
                    
                    // If research was completed, update state with final source count
                    if case .completed = state {
                        state = .completed(
                            topic: state.topic ?? "Unknown", 
                            startTime: Date().addingTimeInterval(-Double(elapsedSeconds)), 
                            endTime: Date(), 
                            sourceCount: accumulatedSources.count
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    print("Error in sendMessage: \(error.localizedDescription)")
                    isStreaming = false
                    
                    // Add error message to conversation
                    let errorMessage = ChatMessage(message: .assistant(content: .text("Sorry, there was an error during the research process. Please try again.")))
                    messages.append(errorMessage)
                }
            }
        }
    }
    
    /// Starts a new research process on the given topic
    /// - Parameter topic: The research topic
    public func startResearch(topic: String) {
        // Reset accumulated sources for new research
        accumulatedSources = []
        
        // Update state to starting
        state = .start(topic: topic, startTime: Date())
        
        // Start the research timer
        startResearchTimer()
        
        // // Add message explaining the research process
        // let processMessage = ChatMessage(message: .assistant(content: .text("""
        // 🔍 **Starting Research on: \(topic)**
        
        // I'll conduct a systematic research process:
        // 1. Formulate research questions and hypotheses
        // 2. Search for relevant medical evidence
        // 3. Analyze the evidence in depth
        // 4. Synthesize findings into actionable insights
        // 5. Produce a comprehensive report with citations
        
        // This process will take a few moments. I'll share my findings with you at each step.
        // """)))
        
        // messages.append(processMessage)
        
        // Send a message to start research
        sendMessage("\(topic)")
    }
    
    /// Cancels the current research process
    public func cancelResearch() {
        stopResearchTimer()
        
        // If in a researching state, update to idle
        if state.isResearching {
            state = .idle
        }
    }
    
    // MARK: - Private Methods
    
    /// Updates the research state based on metadata
    /// - Parameter metadata: The research metadata
    private func updateResearchState(with metadata: ResearchMetadata) {
        // Simply use the state from the metadata directly
        state = metadata.state
        
        // Start or stop the timer based on the state
        switch metadata.state {
        case .start:
            startResearchTimer()
        case .completed:
            stopResearchTimer()
        default:
            break
        }
    }
    
    /// Starts the research timer
    private func startResearchTimer() {
        // Stop any existing timer
        stopResearchTimer()
        
        // Reset elapsed time
        elapsedSeconds = 0
        
        // Create a new timer that fires every second
        researchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update elapsed time
            self.elapsedSeconds += 1
        }
    }
    
    /// Stops the research timer
    private func stopResearchTimer() {
        researchTimer?.invalidate()
        researchTimer = nil
    }
    
    /// Formats the elapsed time as a string
    /// - Returns: Formatted time string (HH:MM:SS)
    public func formattedElapsedTime() -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
} 
