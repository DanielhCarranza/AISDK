import Foundation

public enum LegacyAgentState: Equatable {
    case idle
    case thinking
    case executingTool(String)
    case responding
    case error(AIError)
    
    // MARK: - UI Helper Properties
    
    public var isProcessing: Bool {
        switch self {
        case .idle, .error:
            return false
        case .thinking, .executingTool, .responding:
            return true
        }
    }
    
    public var statusMessage: String {
        switch self {
        case .idle:
            return ""
        case .thinking:
            return "Thinking..."
        case .executingTool(let name):
            return "Executing \(name)..."
        case .responding:
            return "Formulating response..."
        case .error(let error):
            return error.detailedDescription
        }
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: LegacyAgentState, rhs: LegacyAgentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.thinking, .thinking),
             (.responding, .responding):
            return true
        case (.executingTool(let lhsTool), .executingTool(let rhsTool)):
            return lhsTool == rhsTool
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.detailedDescription == rhsError.detailedDescription
        default:
            return false
        }
    }
} 