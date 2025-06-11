//
//  CreateChatCompletionRequest.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 29/12/24.
//


import Foundation

/// Matches the body for POST /v1/chat/completions
public struct ChatCompletionRequest: Encodable {
    // Required
    public let model: String
    public var messages: [Message]

    // Optional parameters
    public var store: Bool?
    public var reasoningEffort: String?
    public var metadata: [String: String]?
    public var frequencyPenalty: Double?
    public var logitBias: [String: Int]?
    public var logprobs: Bool?
    public var topLogprobs: Int?
    
    /// Deprecated in favor of `max_completion_tokens`, but still present in the YAML.
    public var maxTokens: Int?
    
    public var maxCompletionTokens: Int?
    public var n: Int?
    public var modalities: [String]?
    public var presencePenalty: Double?
    public var responseFormat: ResponseFormat?
    public var seed: Int?
    public var serviceTier: String?
    public var stop: [String]?
    public var stream: Bool?
    public var streamOptions: [String: AnyEncodable]?
    public var temperature: Double?
    public var topP: Double?
    public var tools: [ToolSchema]?
    public var toolChoice: ToolChoice?
    public var parallelToolCalls: Bool?
    
    /// Unique identifier for the end-user
    public var user: String?
    
    public init(model: String, 
               messages: [Message],
               store: Bool? = nil,
               reasoningEffort: String? = nil,
               metadata: [String: String]? = nil,
               frequencyPenalty: Double? = nil,
               logitBias: [String: Int]? = nil,
               logprobs: Bool? = nil,
               topLogprobs: Int? = nil,
               maxTokens: Int? = nil,
               maxCompletionTokens: Int? = nil,
               n: Int? = nil,
               modalities: [String]? = nil,
               presencePenalty: Double? = nil,
               responseFormat: ResponseFormat? = nil,
               seed: Int? = nil,
               serviceTier: String? = nil,
               stop: [String]? = nil,
               stream: Bool? = nil,
               streamOptions: [String: AnyEncodable]? = nil,
               temperature: Double? = 0.2,
               topP: Double? = nil,
               tools: [ToolSchema]? = nil,
               toolChoice: ToolChoice? = nil,
               parallelToolCalls: Bool? = nil,
               user: String? = nil) {
        self.model = model
        self.messages = messages
        self.store = store
        self.reasoningEffort = reasoningEffort
        self.metadata = metadata
        self.frequencyPenalty = frequencyPenalty
        self.logitBias = logitBias
        self.logprobs = logprobs
        self.topLogprobs = topLogprobs
        
        // Handle model-specific parameter adjustments
        if model.lowercased() == "o4-mini" {
            // For o4-mini, use maxCompletionTokens instead of maxTokens
            self.maxTokens = nil
            self.maxCompletionTokens = maxTokens ?? maxCompletionTokens
            
            // o3-mini doesn't support temperature
            self.temperature = nil
            
            // o3-mini doesn't support parallel_tool_calls
            self.parallelToolCalls = nil
        } else {
            self.maxTokens = maxTokens
            self.maxCompletionTokens = maxCompletionTokens
            self.temperature = temperature
            self.parallelToolCalls = parallelToolCalls
        }
        
        self.n = n
        self.modalities = modalities
        self.presencePenalty = presencePenalty
        self.responseFormat = responseFormat
        self.seed = seed
        self.serviceTier = serviceTier
        self.stop = stop
        self.stream = stream
        self.streamOptions = streamOptions
        self.topP = topP
        self.tools = tools
        self.toolChoice = toolChoice
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, store, metadata, logprobs, n, stop, stream, temperature, user, tools
        case reasoningEffort = "reasoning_effort"
        case frequencyPenalty = "frequency_penalty"
        case logitBias = "logit_bias"
        case topLogprobs = "top_logprobs"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case presencePenalty = "presence_penalty"
        case responseFormat = "response_format"
        case serviceTier = "service_tier"
        case streamOptions = "stream_options"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case topP = "top_p"
    }
}

/// Tools can be function definitions or other tool types.
public struct ToolSchema: Codable {
    /// Could be "function", etc.
    public let type: String
    
    /// The actual function definition (if `type` == "function").
    public let function: ToolFunction?
}

public struct ToolFunction: Codable {
    public let name: String
    public let description: String?
    public let parameters: Parameters
    public let strict: Bool
    
    public init(name: String, description: String? = nil, parameters: Parameters, strict: Bool = true) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}


public struct Parameters: Codable {
    public let type: String
    public let properties: [String: PropertyDefinition]
    public let required: [String]?
    public var additionalProperties: Bool
    
    public init(type: String, properties: [String: PropertyDefinition], required: [String]? = nil, additionalProperties: Bool = false) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }
}

public struct PropertyDefinition: Codable {
    public let type: String
    public let description: String?
    
    // Basic validations
    public let minimum: Double?
    public let maximum: Double?
    public let exclusiveMinimum: Bool?
    public let exclusiveMaximum: Bool?
    public let multipleOf: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let pattern: String?
    public let format: String?
    
    // Array validations
    public let minItems: Int?
    public let maxItems: Int?
    public let uniqueItems: Bool?
    // Make items indirect to avoid recursive type
    public let items: IndirectPropertyDefinition?
    
    // Object validations
    public let required: [String]?
    // Make properties indirect to avoid recursive type
    public let properties: [String: IndirectPropertyDefinition]?
    
    // Enum values
    public let enumValues: [String]?
    
    public init(
        type: String,
        description: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Bool? = nil,
        exclusiveMaximum: Bool? = nil,
        multipleOf: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        format: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil,
        items: PropertyDefinition? = nil,
        required: [String]? = nil,
        properties: [String: PropertyDefinition]? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.minimum = minimum
        self.maximum = maximum
        self.exclusiveMinimum = exclusiveMinimum
        self.exclusiveMaximum = exclusiveMaximum
        self.multipleOf = multipleOf
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
        self.format = format
        self.minItems = minItems
        self.maxItems = maxItems
        self.uniqueItems = uniqueItems
        self.items = items.map(IndirectPropertyDefinition.init)
        self.required = required
        self.properties = properties.map { dict in
            dict.mapValues(IndirectPropertyDefinition.init)
        }
        self.enumValues = enumValues
    }
    
    enum CodingKeys: String, CodingKey {
        case type, description
        case minimum, maximum
        case exclusiveMinimum = "exclusive_minimum"
        case exclusiveMaximum = "exclusive_maximum"
        case multipleOf = "multiple_of"
        case minLength = "min_length"
        case maxLength = "max_length"
        case pattern, format
        case minItems = "min_items"
        case maxItems = "max_items"
        case uniqueItems = "unique_items"
        case items, required, properties
        case enumValues = "enum"
    }
}

// Indirect wrapper to break recursive type
public final class IndirectPropertyDefinition: Codable {
    public let value: PropertyDefinition
    
    public init(_ value: PropertyDefinition) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        self.value = try PropertyDefinition(from: decoder)
    }
    
    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Describes how the model should call tools.
public enum ToolChoice: Encodable {
    case none
    case auto
    case required
    case function(FunctionChoice)
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .none:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")
        case .required:
            var container = encoder.singleValueContainer()
            try container.encode("required")
        case .function(let fc):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("function", forKey: .type)
            try container.encode(fc, forKey: .function)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case function
    }
    
    public struct FunctionChoice: Encodable {
        public let name: String
        
        public init(name: String) {
            self.name = name
        }
    }
}

/// Helper to wrap any Swift Encodable as an `Encodable` property.
public struct AnyEncodable: Encodable {
    private let encodable: Encodable
    public init(_ encodable: Encodable) {
        self.encodable = encodable
    }
    public func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}

public enum ResponseFormat: Encodable {
    case text
    case jsonObject
    case jsonSchema(
        name: String,
        description: String? = nil,
        schemaBuilder: any SchemaBuilding,
        strict: Bool? = nil
    )
    
    private enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
    
    private enum SchemaKeys: String, CodingKey {
        case name
        case description
        case schema
        case strict
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text:
            try container.encode("text", forKey: .type)
            
        case .jsonObject:
            try container.encode("json_object", forKey: .type)
            
        case .jsonSchema(let name, let description, let schemaBuilder, let strict):
            try container.encode("json_schema", forKey: .type)
            var nestedContainer = container.nestedContainer(keyedBy: SchemaKeys.self, forKey: .jsonSchema)
            try nestedContainer.encode(name, forKey: .name)
            try nestedContainer.encodeIfPresent(description, forKey: .description)
            let schema = schemaBuilder.build()
            try nestedContainer.encode(AnyEncodable(schema), forKey: .schema)
            try nestedContainer.encodeIfPresent(strict, forKey: .strict)
        }
    }
}
