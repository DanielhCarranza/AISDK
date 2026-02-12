//
//  LegacyLLM.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation


public protocol LegacyLLM {
    func sendChatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func sendChatCompletionStream(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error>
    func generateObject<T: Decodable>(request: ChatCompletionRequest) async throws -> T
}
