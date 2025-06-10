//
//  SuggestedQuestion.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 09/01/25.
//

import Foundation

// Define single question model
struct SuggestedQuestion: JSONSchemaModel, Identifiable, Equatable {
    // Add id for Identifiable conformance
    let id = UUID()
    
    @Field(description: "Follow-up question the patient may ask")
    var question: String = ""
    
    init() {}
    
    // Custom coding keys to exclude id from JSON
    private enum CodingKeys: String, CodingKey {
        case question
    }
    
    // Implement Equatable
    static func == (lhs: SuggestedQuestion, rhs: SuggestedQuestion) -> Bool {
        lhs.id == rhs.id && lhs.question == rhs.question
    }
}

// Define questions collection model
struct SuggestedQuestions: JSONSchemaModel {
    @Field(description: "List of follow-up questions the patient may ask")
    var questions: [SuggestedQuestion] = []

    init() {}
}

// Create request for suggested questions
let suggestionsRequest = ChatCompletionRequest(
    model: "gpt-4",
    messages: [
        .system(content: .text("""
            You are a helpful medical assistant. Generate relevant follow-up questions \
            based on the conversation context.

            Instructions:
            - Generate 2 follow-up questions
            - Each question should be a single short sentence (max 8 words)
            - Each question should be relevant to the conversation context
            - Each question should be a question the patient may ask
            """))
    ],
    responseFormat: .jsonSchema(
        name: "suggested_questions",
        description: "Follow-up questions the patient may ask given the conversation context",
        schemaBuilder: SuggestedQuestions.schema()
            .title("Suggested Questions")
            .description("A list of relevant follow-up questions"),
        strict: true
    )
)

// Get suggested questions
// do {
//     let suggestions: SuggestedQuestions = try await openAIProvider.generateObject(
//         request: suggestionsRequest
//     )
    
//     // Use the suggested questions
//     print("Suggested follow-up questions:")
//     suggestions.questions.forEach { suggestion in
//         print("• \(suggestion.question)")
//     }
// } catch {
//     print("Error generating suggestions: \(error)")
// }
