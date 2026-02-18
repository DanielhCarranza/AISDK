import Foundation
import SwiftUI

public enum LegacyMessage: Codable {
    case assistant(content: AssistantContent, name: String? = nil, toolCalls: [ChatCompletionResponse.ToolCall]? = nil)
    case system(content: SystemContent, name: String? = nil)
    case user(content: UserContent, name: String? = nil)
    case developer(content: DeveloperContent, name: String? = nil)
    case tool(content: String, name: String, toolCallId: String)

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case name
        case toolCallId = "tool_call_id"
        case toolCalls = "tool_calls"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .assistant(let content, let name, let toolCalls):
            try container.encode("assistant", forKey: .role)
            try container.encode(content, forKey: .content)
            if let name = name {
                try container.encode(name, forKey: .name)
            }
            if let toolCalls = toolCalls {
                var toolCallsContainer = container.nestedUnkeyedContainer(forKey: .toolCalls)
                for toolCall in toolCalls {
                    try toolCallsContainer.encode(toolCall)
                }
            }
        case .system(let content, let name):
            try container.encode("system", forKey: .role)
            try container.encode(content, forKey: .content)
            if let name = name {
                try container.encode(name, forKey: .name)
            }
        case .user(let content, let name):
            try container.encode("user", forKey: .role)
            try container.encode(content, forKey: .content)
            if let name = name {
                try container.encode(name, forKey: .name)
            }
        case .developer(let content, let name):
            try container.encode("developer", forKey: .role)
            try container.encode(content, forKey: .content)
            if let name = name {
                try container.encode(name, forKey: .name)
            }
        case .tool(let content, let name, let toolCallId):
            try container.encode("tool", forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encode(name, forKey: .name)
            try container.encode(toolCallId, forKey: .toolCallId)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)
        
        switch role {
        case "assistant":
            let content = try container.decode(AssistantContent.self, forKey: .content)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            let toolCalls = try container.decodeIfPresent([ChatCompletionResponse.ToolCall].self, forKey: .toolCalls)
            self = .assistant(content: content, name: name, toolCalls: toolCalls)
            
        case "system":
            let content = try container.decode(SystemContent.self, forKey: .content)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            self = .system(content: content, name: name)
            
        case "user":
            let content = try container.decode(UserContent.self, forKey: .content)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            self = .user(content: content, name: name)
            
        case "developer":
            let content = try container.decode(DeveloperContent.self, forKey: .content)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            self = .developer(content: content, name: name)
            
        case "tool":
            let content = try container.decode(String.self, forKey: .content)
            let name = try container.decode(String.self, forKey: .name)
            let toolCallId = try container.decode(String.self, forKey: .toolCallId)
            self = .tool(content: content, name: name, toolCallId: toolCallId)
            
        default:
            throw DecodingError.dataCorruptedError(forKey: .role, in: container, debugDescription: "Unknown role type")
        }
    }
}

public enum AssistantContent: Codable {
    case text(String)
    case parts([String])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let strings):
            try container.encode(strings)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let strings = try? container.decode([String].self) {
            self = .parts(strings)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Neither String nor [String] found")
        }
    }
}

public enum SystemContent: Codable {
    case text(String)
    case parts([String])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let strings):
            try container.encode(strings)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let strings = try? container.decode([String].self) {
            self = .parts(strings)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Neither String nor [String] found")
        }
    }
}

public enum UserContent: Codable {
    case text(String)
    case parts([Part])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let parts):
            try container.encode(parts)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let parts = try? container.decode([Part].self) {
            self = .parts(parts)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Neither String nor [Part] found")
        }
    }

    public enum Part: Codable {
        case text(String)
        case imageURL(ImageSource, detail: ImageDetail = .auto)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        private enum ImageKeys: String, CodingKey {
            case url
            case detail
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case .text(let textValue):
                try container.encode("text", forKey: .type)
                try container.encode(textValue, forKey: .text)

            case .imageURL(let source, let detail):
                try container.encode("image_url", forKey: .type)
                var imageContainer = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                
                // Encode the URL based on the source type
                switch source {
                case .url(let url):
                    try imageContainer.encode(url.absoluteString, forKey: .url)
                case .base64(let data):
                    let base64String = data.base64EncodedString()
                    try imageContainer.encode("data:\(source.mimeType);base64,\(base64String)", forKey: .url)
                }
                
                // Always encode detail since it's non-optional
                try imageContainer.encode(detail, forKey: .detail)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            switch type {
            case "text":
                let text = try container.decode(String.self, forKey: .text)
                self = .text(text)
                
            case "image_url":
                let imageContainer = try container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
                let urlString = try imageContainer.decode(String.self, forKey: .url)
                let detail = try imageContainer.decode(ImageDetail.self, forKey: .detail)
                
                if urlString.hasPrefix("data:") {
                    // Handle base64 data
                    let parts = urlString.split(separator: ",", maxSplits: 1)
                    guard parts.count == 2,
                          let data = Data(base64Encoded: String(parts[1])) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .imageURL,
                            in: container,
                            debugDescription: "Invalid base64 data"
                        )
                    }
                    self = .imageURL(.base64(data), detail: detail)
                } else {
                    // Handle URL
                    guard let url = URL(string: urlString) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .imageURL,
                            in: container,
                            debugDescription: "Invalid URL"
                        )
                    }
                    self = .imageURL(.url(url), detail: detail)
                }
                
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown type"
                )
            }
        }
    }

    public enum ImageDetail: String, Codable {
        case auto
        case low
        case high
    }
}

public enum ImageSource {
        case url(URL)
        case base64(Data)
        
        internal var mimeType: String {
            switch self {
            case .base64(let data):
                // Detect mime type from data header
                let header = data.prefix(16).map { String(format: "%02hhx", $0) }.joined()
                switch header {
                case let str where str.hasPrefix("ffd8"): return "image/jpeg"
                case let str where str.hasPrefix("89504e47"): return "image/png"
                case let str where str.hasPrefix("47494638"): return "image/gif"
                default: return "image/jpeg"  // Default to JPEG
                }
            case .url:
                return "image/jpeg"  // Not used for URLs
            }
        }
        
        // Basic resize function that works with raw Data
        public func resizedIfNeeded(maxDimension: CGFloat = 2000) -> ImageSource {
            switch self {
            case .url:
                return self // Don't resize URLs
            case .base64:
                return self // Basic version doesn't resize
            }
        }
}
// // UIKit-specific extensions in separate file
// #if canImport(UIKit)
// import UIKit

// public extension UserContent.ImageSource {
//     static func from(uiImage: UIImage, quality: CGFloat = 0.8) -> Self? {
//         guard let imageData = uiImage.jpegData(compressionQuality: quality) else {
//             return nil
//         }
//         return .base64(imageData)
//     }
    
//     func resizedIfNeeded(maxDimension: CGFloat = 2000) -> Self {
//         switch self {
//         case .url:
//             return self
//         case .base64(let data):
//             guard let uiImage = UIImage(data: data),
//                   max(uiImage.size.width, uiImage.size.height) > maxDimension else {
//                 return self
//             }
            
//             let scale = maxDimension / max(uiImage.size.width, uiImage.size.height)
//             let newSize = CGSize(width: uiImage.size.width * scale,
//                                height: uiImage.size.height * scale)
            
//             UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
//             uiImage.draw(in: CGRect(origin: .zero, size: newSize))
//             guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext(),
//                   let resizedData = resizedImage.jpegData(compressionQuality: 0.8) else {
//                 UIGraphicsEndImageContext()
//                 return self
//             }
//             UIGraphicsEndImageContext()
            
//             return .base64(resizedData)
//         }
//     }
// }
// #endif

public enum DeveloperContent: Codable {
    case text(String)
    case parts([String])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let strings):
            try container.encode(strings)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let strings = try? container.decode([String].self) {
            self = .parts(strings)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Neither String nor [String] found")
        }
    }
} 
