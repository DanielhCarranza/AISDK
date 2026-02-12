import Foundation

/// Protocol defining the essential properties and behavior for medical record content
/// that can be attached to messages and converted to LegacyLLM context.
public protocol MedicalRecordContent: Codable {
    /// Unique identifier for the medical record
    var id: String { get }
    
    /// Display name of the medical record
    var name: String { get }
    
    /// Type of medical record as a string (for flexibility across implementations)
    var recordType: String { get }
    
    /// Brief summary of the medical record content
    var summary: String { get }
    
    /// SF Symbol name for UI display
    var icon: String { get }
    
    /// Human-readable display name for the record type
    var displayName: String { get }
    
    /// Converts the medical record to a formatted string for LegacyLLM context
    /// This method allows each implementation to control how the record appears to the AI
    func toLLMContext() -> String
} 