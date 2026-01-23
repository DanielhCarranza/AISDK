//
//  AIUsage+Legacy.swift
//  AISDK
//
//  Extension to convert legacy OpenAI ChatCompletionResponse.Usage to AIUsage
//  Kept in the Legacy adapters folder to avoid Core depending on provider models
//

import Foundation

// MARK: - Legacy Usage Conversion

public extension AIUsage {
    /// Create from legacy ChatCompletionResponse.Usage
    ///
    /// This initializer is placed in the Legacy adapters folder to avoid
    /// the Core models depending on OpenAI-specific API models.
    init(legacy usage: ChatCompletionResponse.Usage?) {
        self.init(
            promptTokens: usage?.promptTokens ?? 0,
            completionTokens: usage?.completionTokens ?? 0,
            reasoningTokens: usage?.completionTokensDetails?.reasoningTokens,
            cachedTokens: nil  // Legacy Usage doesn't track cached tokens
        )
    }
}
