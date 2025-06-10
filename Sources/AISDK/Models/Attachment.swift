import Foundation

enum AttachmentType: String, Codable {
    case image
    case pdf
    case audio
    case video
    case json
    case other
    
    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .audio: return "waveform"
        case .video: return "play.rectangle"
        case .json: return "curlybraces"
        case .other: return "doc"
        }
    }
    
    var mimeType: String {
        switch self {
        case .image: return "image/jpeg"
        case .pdf: return "application/pdf"
        case .audio: return "audio/mpeg"
        case .video: return "video/mp4"
        case .json: return "application/json"
        case .other: return "application/octet-stream"
        }
    }
    
    static func from(fileExtension: String) -> AttachmentType {
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

struct Attachment: Identifiable, Codable {
    let id: UUID
    let url: URL
    let name: String
    let type: AttachmentType
    let size: Int64?
    let createdAt: Date
    let content: String?
    
    init(url: URL, name: String, type: AttachmentType? = nil, size: Int64? = nil, content: String? = nil) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.type = type ?? AttachmentType.from(fileExtension: url.pathExtension)
        self.size = size
        self.createdAt = Date()
        self.content = content
    }
    
    init() {
        self.id = UUID()
        self.url = URL(string: "attachment://\(id)")!
        self.name = "Attachment"
        self.type = .other
        self.size = nil
        self.createdAt = Date()
        self.content = nil
    }
} 