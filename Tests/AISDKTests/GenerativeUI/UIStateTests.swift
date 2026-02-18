//
//  UIStateTests.swift
//  AISDKTests
//
//  Tests for UIState $path resolution and namespace isolation
//

import Testing
import Foundation
@testable import AISDK

@Suite("UIState")
struct UIStateTests {
    // MARK: - Basic Operations

    @Test("Empty state resolves nil")
    func emptyState() {
        let state = UIState()
        #expect(state.resolve(path: "/state/foo") == nil)
        #expect(state.isEmpty)
    }

    @Test("Set and get top-level value")
    func topLevelValue() {
        var state = UIState(values: ["state": SpecValue(["revenue": SpecValue(12345)])])
        #expect(state.resolve(path: "/state/revenue")?.intValue == 12345)
    }

    @Test("Set and get nested value")
    func nestedValue() {
        let state = UIState(values: [
            "state": SpecValue([
                "metrics": SpecValue([
                    "revenue": SpecValue(12345),
                    "users": SpecValue(42)
                ])
            ])
        ])
        #expect(state.resolve(path: "/state/metrics/revenue")?.intValue == 12345)
        #expect(state.resolve(path: "/state/metrics/users")?.intValue == 42)
    }

    @Test("Missing path returns nil")
    func missingPath() {
        let state = UIState(values: ["state": SpecValue(["x": SpecValue(1)])])
        #expect(state.resolve(path: "/state/nonexistent") == nil)
        #expect(state.resolve(path: "/state/x/deeper") == nil)
    }

    // MARK: - Namespace Isolation

    @Test("resolveSafe allows /state/ paths")
    func safePathsAllowed() {
        let state = UIState(values: [
            "state": SpecValue(["secret": SpecValue("allowed")])
        ])
        #expect(state.resolveSafe(path: "/state/secret")?.stringValue == "allowed")
    }

    @Test("resolveSafe rejects /app/ paths")
    func safePathsRejectApp() {
        let state = UIState(values: [
            "app": SpecValue(["apiKey": SpecValue("secret123")])
        ])
        // Direct resolve works (developer access)
        #expect(state.resolve(path: "/app/apiKey")?.stringValue == "secret123")
        // Safe resolve rejects (LLM access)
        #expect(state.resolveSafe(path: "/app/apiKey") == nil)
    }

    @Test("resolveSafe rejects arbitrary paths")
    func safePathsRejectArbitrary() {
        let state = UIState(values: ["other": SpecValue("data")])
        #expect(state.resolveSafe(path: "/other") == nil)
    }

    // MARK: - $cond Resolution

    @Test("Conditional resolves then for truthy")
    func condTruthy() {
        let state = UIState(values: [
            "state": SpecValue(["darkMode": SpecValue(true)])
        ])
        let result = state.resolveConditional([
            "$cond": SpecValue("/state/darkMode"),
            "then": SpecValue("dark"),
            "else": SpecValue("light")
        ])
        #expect(result?.stringValue == "dark")
    }

    @Test("Conditional resolves else for falsy")
    func condFalsy() {
        let state = UIState(values: [
            "state": SpecValue(["darkMode": SpecValue(false)])
        ])
        let result = state.resolveConditional([
            "$cond": SpecValue("/state/darkMode"),
            "then": SpecValue("dark"),
            "else": SpecValue("light")
        ])
        #expect(result?.stringValue == "light")
    }

    @Test("Conditional resolves else for missing path")
    func condMissing() {
        let state = UIState()
        let result = state.resolveConditional([
            "$cond": SpecValue("/state/missing"),
            "then": SpecValue("yes"),
            "else": SpecValue("no")
        ])
        #expect(result?.stringValue == "no")
    }

    @Test("Zero integer is falsy")
    func zeroIsFalsy() {
        let state = UIState(values: [
            "state": SpecValue(["count": SpecValue(0)])
        ])
        let result = state.resolveConditional([
            "$cond": SpecValue("/state/count"),
            "then": SpecValue("has items"),
            "else": SpecValue("empty")
        ])
        #expect(result?.stringValue == "empty")
    }

    @Test("Non-zero integer is truthy")
    func nonZeroIsTruthy() {
        let state = UIState(values: [
            "state": SpecValue(["count": SpecValue(5)])
        ])
        let result = state.resolveConditional([
            "$cond": SpecValue("/state/count"),
            "then": SpecValue("has items"),
            "else": SpecValue("empty")
        ])
        #expect(result?.stringValue == "has items")
    }

    // MARK: - Mutation

    @Test("setValue creates nested path")
    func setValueNested() {
        var state = UIState()
        state.setValue(at: "/metrics/revenue", to: SpecValue(999))
        #expect(state.resolve(path: "/metrics/revenue")?.intValue == 999)
    }

    @Test("removeValue removes entry")
    func removeValue() {
        var state = UIState(values: ["x": SpecValue(42)])
        state.removeValue(at: "/x")
        #expect(state["x"] == nil)
    }
}
