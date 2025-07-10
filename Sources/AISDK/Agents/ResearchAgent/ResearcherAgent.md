# ResearcherAgent PRD

## Overview

The ResearcherAgent is an AI-powered tool designed to perform systematic medical research on behalf of healthcare providers and patients. It automates the process of formulating research questions, gathering evidence, analyzing findings, and producing comprehensive reports with proper citations.

## Goals and Objectives

- **Automate medical research processes** to save time for healthcare providers and patients
- **Ensure evidence-based information** by systematically searching medical databases
- **Produce comprehensive research reports** with proper citations
- **Maintain transparency** in the research process by tracking sources and research progress
- **Provide a user-friendly interface** to initiate, monitor, and review research

## User Experience

1. User initiates research by providing a health topic or question
2. ResearcherAgent formulates research hypotheses and search queries
3. Agent searches medical databases and retrieves relevant evidence
4. Agent analyzes evidence, generates insights, and formulates follow-up queries
5. Process continues until sufficient evidence is gathered
6. Agent produces a final report with findings and citations
7. User can review the report and access original sources

## Feature Specifications

### 1. Research States

The ResearcherAgent operates in four distinct states:

- **Idle**: Agent is ready to begin new research
- **Start**: Research has been initiated, hypotheses and queries are being generated
- **Processing**: Agent is actively searching, retrieving, and analyzing evidence
- **Completed**: Research process is finished, and a final report is available

### 2. Research Tracking

- **Timer**: Tracks elapsed time since research began
- **Source Counter**: Counts the number of sources analyzed during research
- **Progress Indicator**: Shows current research state and progress through workflow

### 3. Research Tools

#### 3.1 StartResearch
- **Purpose**: Initialize research process and generate hypotheses and queries
- **Parameters**:
  - `topic`: The medical topic or question to research
  - `depth`: Desired research depth (basic, standard, comprehensive)
- **Output**: Initial hypotheses and search queries
- **State Transition**: Idle → Start

#### 3.2 SearchMedicalEvidence
- **Purpose**: Search medical databases for relevant evidence
- **Parameters**:
  - `query`: Search query for medical databases
  - `sources`: Types of sources to prioritize (studies, reviews, guidelines)
  - `timeframe`: How recent the evidence should be
- **Output**: List of relevant evidence items with metadata
- **State Transition**: Maintains Processing state

#### 3.3 ReadEvidence
- **Purpose**: Analyze and extract key information from medical evidence
- **Parameters**:
  - `read`: Expected findings from reading the evidence
- **Output**: summary of evidence
- **State Transition**: Maintains Processing state

#### 3.4 ReasonEvidence
- **Purpose**: Analyze evidence, identify patterns, and generate follow-up queries
- **Parameters**:
  - `think`: Reason about the evidence and findings
  - `evidenceSummaries`: Collection of evidence summaries to analyze
  - `currentHypotheses`: Current research hypotheses
- **Output**: Insights, patterns, and follow-up queries
- **State Transition**: Maintains Processing state

#### 3.5 SearchHealthProfile
- **Purpose**: Search user's health profile for relevant information to contextualize research
- **Parameters**:
  - `query`: What to Retrieve: Medical History, Medications, Journal Entries, etc.
- **Output**: Relevant health profile information
- **State Transition**: Maintains Processing state

#### 3.6 CompleteResearch
- **Purpose**: Finalize research and generate comprehensive report
- **Parameters**:
  - `insights`: Collection of insights from evidence analysis
  - `citations`: Sources to include in citations
  - `format`: Report format (brief, standard, detailed)
- **Output**: Final research report with citations
- **State Transition**: Processing → Completed

## Technical Specifications

### 1. Agent Configuration

- **Model**: OpenAI o3-mini
- **Mode**: Parallel tools
- **System Prompt**: Specialized prompt for medical research tasks

### 2. Tool Implementation

- **Tool Registry**: All research tools registered with ToolRegistry
- **Tool Execution**: Sequential and conditional execution based on research state
- **Tool Parameters**: Structured parameters with validation
- **Tool Outputs**: Structured outputs with metadata

### 3. Research Workflow

```
┌─────────┐    ┌─────────┐    ┌─────────────┐    ┌───────────┐
│   Idle  │ -> │  Start  │ -> │  Processing │ -> │ Completed │
└─────────┘    └─────────┘    └─────────────┘    └───────────┘
                                    ↑  │
                                    └──┘
                              (Iterative Process)
```

1. **Idle → Start**: Triggered by StartResearch tool execution
2. **Start → Processing**: Automatic after hypotheses generation
3. **Processing Loop**: Iterative process of searching, reading, and reasoning about evidence
4. **Processing → Completed**: Triggered by CompleteResearch tool execution

### 4. State Management

- **Central State Store**: Tracks current research state, timer, and source count
- **State Transitions**: Managed by tool executions
- **Persistence**: Research state persisted between sessions

## UI Components

### 1. ResearcherAgentDemoView

- **Main Interface**: Chat-like interface for interacting with ResearcherAgent
- **Research Status Card**:
  - Current research state (Idle, Start, Processing, Completed)
  - Timer showing elapsed research time
  - Source counter showing number of sources analyzed
  - Progress indicator
- **Message Display**: Shows conversation with agent and tool outputs
- **Input Area**: Text input for user queries and commands

### 2. Research Report View

- **Report Display**: Formatted research report in Markdown
- **Citations**: List of cited sources with links
- **Export Options**: Options to save or share report

## Implementation Plan

### Phase 1: Core Framework

1. **Task 1.1**: Define ResearcherAgent class and state management
   - Create base agent configuration with o3-mini model
   - Implement research state tracking (idle, start, processing, completed)
   - Add timer and source counter functionality

2. **Task 1.2**: Implement basic tool definitions
   - Define all required tools with parameters and outputs
   - Implement tool registry integration
   - Create mock tool implementations for demo

### Phase 2: UI Implementation

1. **Task 2.1**: Create ResearcherAgentDemoView
   - Implement chat-like interface similar to AgentDemoView
   - Add research status card with state, timer, and counter
   - Implement input and message display components

2. **Task 2.2**: Implement Research Report Display
   - Create Markdown rendering for research reports
   - Implement citation display and linking
   - Add export functionality

### Phase 3: Integration and Testing

1. **Task 3.1**: Integrate tools with demo view
   - Connect UI state to agent state
   - Implement tool execution from UI
   - Add real-time updates for research status

2. **Task 3.2**: Test with sample research scenarios
   - Create sample research topics
   - Test full research workflow
   - Optimize performance and UX

## Success Metrics

- **Completion Rate**: Percentage of research requests that complete successfully
- **Research Quality**: Accuracy and comprehensiveness of research reports
- **User Satisfaction**: User ratings and feedback on research reports
- **Performance**: Time to complete research and resource utilization

## Future Enhancements

- **Advanced Filtering**: More sophisticated filtering of evidence based on quality and relevance
- **Visualization**: Visual representations of research findings
- **Collaboration**: Ability to share and collaborate on research projects
- **Customization**: User-defined research templates and preferences
- **Integration**: Integration with electronic health records and medical databases 