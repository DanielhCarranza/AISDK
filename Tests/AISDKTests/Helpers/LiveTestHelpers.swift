//
//  LiveTestHelpers.swift
//  AISDKTests
//
//  Provider-failure observability for live integration tests.
//
//  Purpose: When a live test hits a broken provider (quota exhausted,
//  expired key, permission denied, payment required), most tests today
//  fail with generic XCTAssert errors that bury the real story. A human
//  then has to dig through raw HTTP codes to realize "oh, OpenAI is out
//  of funds again." This helper classifies those errors into loud labeled
//  messages, marks the provider broken once per run, and cleanly skips
//  downstream tests that depend on the same provider.
//
//  Usage (minimal, in existing live test catch blocks):
//
//      do {
//          response = try await client.execute(request: request)
//      } catch {
//          try LiveTestHelpers.handle(error, provider: .openAI)
//      }
//
//  Or as a wrapper:
//
//      let response = try await LiveTestHelpers.runLive(provider: .openAI) {
//          try await client.execute(request: request)
//      }
//

import Foundation
import XCTest
@testable import AISDK

// MARK: - Provider Identity

/// A live provider that can be tracked for runtime health in live tests.
public enum LiveTestProvider: String, Sendable, Hashable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"
    case openRouter = "OpenRouter"
    case liteLLM = "LiteLLM"
}

// MARK: - Failure Classification

/// Why a live provider call failed, in a way that matters to integration tests.
public enum LiveTestFailureKind: Sendable {
    /// Account is out of credits / over quota. Usually persistent for the run.
    case quotaExhausted(message: String)
    /// API key is invalid, revoked, or missing the right scopes.
    case authInvalid(message: String)
    /// Billing/payment action required (e.g. OpenRouter 402).
    case paymentRequired(message: String)
    /// Permission denied by policy (e.g. Gemini PERMISSION_DENIED).
    case permissionDenied(message: String)
    /// Hit a rate limit — probably transient.
    case rateLimited(message: String)
    /// Upstream overloaded (e.g. Anthropic 529, any 503).
    case serverOverloaded(message: String)
    /// Network error reaching the provider.
    case networkUnavailable(message: String)
    /// The requested model isn't available on this account/region.
    case modelUnavailable(message: String)

    public var emoji: String {
        switch self {
        case .quotaExhausted: return "💸"
        case .authInvalid: return "🔑"
        case .paymentRequired: return "💳"
        case .permissionDenied: return "🔒"
        case .rateLimited: return "⏱️"
        case .serverOverloaded: return "🔥"
        case .networkUnavailable: return "📡"
        case .modelUnavailable: return "🚫"
        }
    }

    public var label: String {
        switch self {
        case .quotaExhausted: return "QUOTA EXHAUSTED"
        case .authInvalid: return "AUTH INVALID"
        case .paymentRequired: return "PAYMENT REQUIRED"
        case .permissionDenied: return "PERMISSION DENIED"
        case .rateLimited: return "RATE LIMITED"
        case .serverOverloaded: return "SERVER OVERLOADED"
        case .networkUnavailable: return "NETWORK UNAVAILABLE"
        case .modelUnavailable: return "MODEL UNAVAILABLE"
        }
    }

    public var message: String {
        switch self {
        case .quotaExhausted(let m),
             .authInvalid(let m),
             .paymentRequired(let m),
             .permissionDenied(let m),
             .rateLimited(let m),
             .serverOverloaded(let m),
             .networkUnavailable(let m),
             .modelUnavailable(let m):
            return m
        }
    }

    /// Whether this failure should mark the provider broken for the rest of
    /// the run. Persistent billing/auth problems stay broken; transient rate
    /// limits and overloads do not.
    public var isPersistent: Bool {
        switch self {
        case .quotaExhausted, .authInvalid, .paymentRequired, .permissionDenied:
            return true
        case .rateLimited, .serverOverloaded, .networkUnavailable, .modelUnavailable:
            return false
        }
    }
}

// MARK: - Process-Wide Health Tracker

/// Tracks which live providers have been marked broken during the current
/// test run. When one test discovers a provider is unusable, every downstream
/// test using the same provider skips fast instead of repeating the same
/// 401/429 round-trip.
public final class LiveProviderHealth: @unchecked Sendable {
    public static let shared = LiveProviderHealth()

    private let lock = NSLock()
    private var broken: [LiveTestProvider: LiveTestFailureKind] = [:]

    private init() {}

    /// Mark a provider broken for the rest of this run. Idempotent — only the
    /// first call prints the banner. Noisy by design: the banner goes to
    /// stderr so it shows up above test framework output.
    public func markBroken(_ provider: LiveTestProvider, kind: LiveTestFailureKind) {
        lock.lock()
        let firstTime = broken[provider] == nil
        if firstTime {
            broken[provider] = kind
        }
        lock.unlock()

        guard firstTime else { return }
        let banner = """

        🚨 [\(provider.rawValue)] \(kind.emoji) \(kind.label) — \(truncate(kind.message, to: 200))
           → Marking \(provider.rawValue) broken for the rest of this run. Downstream \(provider.rawValue)-dependent tests will skip.

        """
        fputs(banner, stderr)
    }

    /// Returns the failure kind if this provider was marked broken.
    public func brokenKind(_ provider: LiveTestProvider) -> LiveTestFailureKind? {
        lock.lock()
        defer { lock.unlock() }
        return broken[provider]
    }

    /// Reset tracked state. Only used in unit tests for this helper itself.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        broken.removeAll()
    }

    private func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        return String(s.prefix(limit)) + "…"
    }
}

// MARK: - Helper API

public enum LiveTestHelpers {

    /// Classify an error thrown from a live provider call. Returns nil if the
    /// error doesn't look like a provider-health issue — callers should
    /// re-throw those errors so they fail their test loudly (real bugs).
    public static func classify(_ error: Error, provider: LiveTestProvider) -> LiveTestFailureKind? {
        // Path 1: structured ProviderError from the SDK's own client adapters.
        if let providerError = error as? ProviderError {
            return classifyProviderError(providerError, provider: provider)
        }

        // Path 2: fallback string match for errors that didn't flow through
        // ProviderError (e.g. URLSession errors, raw decoding errors from a
        // provider response body that failed to parse). Keep this narrow —
        // we only match high-confidence signals.
        let description = String(describing: error).lowercased()
        if description.contains("insufficient_quota") || description.contains("insufficient quota") {
            return .quotaExhausted(message: String(describing: error))
        }
        if description.contains("permission_denied") || description.contains("permission denied") {
            return .permissionDenied(message: String(describing: error))
        }
        if description.contains("resource_exhausted") {
            return .quotaExhausted(message: String(describing: error))
        }
        if description.contains("payment required") || description.contains("402") {
            return .paymentRequired(message: String(describing: error))
        }
        return nil
    }

    private static func classifyProviderError(_ error: ProviderError, provider: LiveTestProvider) -> LiveTestFailureKind? {
        switch error {
        case .authenticationFailed(let message):
            // Some providers fold "insufficient_quota" into 401/403 bodies.
            let lower = message.lowercased()
            if lower.contains("quota") || lower.contains("billing") || lower.contains("insufficient") {
                return .quotaExhausted(message: message)
            }
            return .authInvalid(message: message)

        case .rateLimited(let retryAfter):
            // NOTE: OpenAI maps insufficient_quota to HTTP 429 with no Retry-After
            // in the current adapter. We can't distinguish rate limit from quota
            // from the ProviderError alone (body is discarded at line 452 of
            // OpenAIClientAdapter.swift). This is a known lossy classification;
            // the roadmap issue tracks tightening it by preserving the raw body.
            let msg = retryAfter.map { "retry after \(Int($0))s" } ?? "no Retry-After header — may actually be quota"
            return .rateLimited(message: msg)

        case .serverError(let statusCode, let message):
            if statusCode == 529 || statusCode == 503 {
                return .serverOverloaded(message: "HTTP \(statusCode): \(message)")
            }
            // 402 Payment Required is rare in serverError but handle it.
            if statusCode == 402 {
                return .paymentRequired(message: message)
            }
            // Other 5xx are real server bugs — don't mask as a health issue.
            return nil

        case .modelNotFound(let message):
            return .modelUnavailable(message: message)

        case .networkError(let message):
            return .networkUnavailable(message: message)

        case .providerSpecific(let code, let message):
            let combined = (code + " " + message).lowercased()
            if combined.contains("quota") || combined.contains("insufficient") {
                return .quotaExhausted(message: "\(code): \(message)")
            }
            if combined.contains("resource_exhausted") {
                return .quotaExhausted(message: "\(code): \(message)")
            }
            if combined.contains("permission_denied") || combined.contains("forbidden") {
                return .permissionDenied(message: "\(code): \(message)")
            }
            return nil

        case .unknown(let message):
            // OpenRouter's adapter maps non-standard status codes to .unknown
            // with an "HTTP <code>: ..." message. This is the only path where
            // we see HTTP 402 (payment required) today.
            let lower = message.lowercased()
            if lower.contains("402") || lower.contains("payment required") {
                return .paymentRequired(message: message)
            }
            if lower.contains("insufficient_quota") || lower.contains("insufficient quota") {
                return .quotaExhausted(message: message)
            }
            if lower.contains("permission_denied") {
                return .permissionDenied(message: message)
            }
            return nil

        case .invalidRequest, .timeout, .parseError, .contentFiltered, .unsupportedModality:
            return nil
        }
    }

    /// Handle a live-test error: classify it, print a loud labeled message,
    /// mark the provider broken if the failure is persistent, and skip the
    /// current test. Unclassified errors are re-thrown so real bugs fail loud.
    ///
    /// Returns `Never` — this function always either throws XCTSkip (known
    /// provider health issue) or re-throws the original error (real bug).
    public static func handle(
        _ error: Error,
        provider: LiveTestProvider,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Never {
        guard let kind = classify(error, provider: provider) else {
            // Not a recognized health issue — let the test fail as usual.
            throw error
        }

        // Loud, per-failure line (in addition to the once-per-run banner below).
        fputs(
            "\n\(kind.emoji) [\(provider.rawValue)] \(kind.label) — \(kind.message)\n",
            stderr
        )

        if kind.isPersistent {
            LiveProviderHealth.shared.markBroken(provider, kind: kind)
        }

        throw XCTSkip(
            "\(provider.rawValue) unavailable (\(kind.label)): \(kind.message)",
            file: file,
            line: line
        )
    }

    /// Skip the current test early if the given provider was already marked
    /// broken earlier in this run. Cheap to call at the top of every live test.
    public static func skipIfProviderBroken(
        _ provider: LiveTestProvider,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        guard let kind = LiveProviderHealth.shared.brokenKind(provider) else { return }
        throw XCTSkip(
            "\(provider.rawValue) already marked broken this run (\(kind.label)) — skipping downstream test",
            file: file,
            line: line
        )
    }

    /// Convenience: run a block against a live provider, skipping fast if the
    /// provider is already known broken and classifying errors through `handle`.
    public static func runLive<T>(
        provider: LiveTestProvider,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () async throws -> T
    ) async throws -> T {
        try skipIfProviderBroken(provider, file: file, line: line)
        do {
            return try await block()
        } catch {
            try handle(error, provider: provider, file: file, line: line)
        }
    }
}
