import Foundation

public enum AttachmentType: String, Codable {
    case image
    case pdf
    case audio
    case video
    case json
    case medicalRecord
    case other
    
    public var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .audio: return "waveform"
        case .video: return "play.rectangle"
        case .json: return "curlybraces"
        case .medicalRecord: return "heart.text.square"
        case .other: return "doc"
        }
    }
    
    public var mimeType: String {
        switch self {
        case .image: return "image/jpeg"
        case .pdf: return "application/pdf"
        case .audio: return "audio/mpeg"
        case .video: return "video/mp4"
        case .json: return "application/json"
        case .medicalRecord: return "application/json"
        case .other: return "application/octet-stream"
        }
    }
    
    public static func from(fileExtension: String) -> AttachmentType {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic": return .image
        case "pdf": return .pdf
        case "mp3", "wav", "m4a": return .audio
        case "mp4", "mov", "m4v": return .video
        case "json": return .json
        default: return .other
        }
    }
}

public struct Attachment: Identifiable, Codable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let type: AttachmentType
    public let size: Int64?
    public let createdAt: Date
    public let content: String?
    public let medicalRecordData: Data?
    
    public init(url: URL, name: String, type: AttachmentType? = nil, size: Int64? = nil, content: String? = nil) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.type = type ?? AttachmentType.from(fileExtension: url.pathExtension)
        self.size = size
        self.createdAt = Date()
        self.content = content
        self.medicalRecordData = nil
    }
    
    public init() {
        self.id = UUID()
        self.url = URL(string: "attachment://\(id)")!
        self.name = "Attachment"
        self.type = .other
        self.size = nil
        self.createdAt = Date()
        self.content = nil
        self.medicalRecordData = nil
    }
    
    /// Creates an attachment from a medical record
    public init<T: MedicalRecordContent>(medicalRecord: T) {
        self.id = UUID()
        self.url = URL(string: "medical-record://\(medicalRecord.id)")!
        self.name = medicalRecord.name
        self.type = .medicalRecord
        self.size = nil
        self.createdAt = Date()
        self.content = medicalRecord.summary
        
        // Serialize the medical record to Data
        let encoder = JSONEncoder()
        self.medicalRecordData = try? encoder.encode(medicalRecord)
    }
    
    /// Retrieves the medical record from this attachment
    public func getMedicalRecord<T: MedicalRecordContent>(as type: T.Type) -> T? {
        guard let data = medicalRecordData else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }
    
    /// Gets the LegacyLLM context string for the medical record
    public func getLLMContext<T: MedicalRecordContent>(as type: T.Type) -> String? {
        return getMedicalRecord(as: type)?.toLLMContext()
    }
} 