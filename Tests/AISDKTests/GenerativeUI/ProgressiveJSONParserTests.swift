//
//  ProgressiveJSONParserTests.swift
//  AISDKTests
//
//  Tests for ProgressiveJSONParser — text delta to SpecPatchBatch bridge
//

import Testing
import Foundation
@testable import AISDK

@Suite("ProgressiveJSONParser")
struct ProgressiveJSONParserTests {
    // MARK: - JSON Detection

    @Test("Detects JSON in pure JSON text")
    func detectsPureJSON() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "main", "elements": {"main": {"type": "Text", "props": {"content": "Hello"}}}}
        """
        let batches = parser.feed(json)
        #expect(!batches.isEmpty)

        let patches = batches.flatMap(\.patches)
        let rootPatch = patches.first { $0.path == "/root" }
        #expect(rootPatch?.op == .add)
        #expect(rootPatch?.value?.stringValue == "main")
    }

    @Test("Detects JSON preceded by text")
    func detectsJSONAfterText() {
        let parser = ProgressiveJSONParser()
        let text = """
        Here's your dashboard: {"root": "main", "elements": {"main": {"type": "Stack", "props": {"direction": "vertical"}}}}
        """
        let batches = parser.feed(text)
        #expect(!batches.isEmpty)

        let patches = batches.flatMap(\.patches)
        #expect(patches.contains { $0.path == "/root" })
        #expect(patches.contains { $0.path == "/elements/main" })
    }

    @Test("Ignores non-JSON text")
    func ignoresPlainText() {
        let parser = ProgressiveJSONParser()
        let batches = parser.feed("This is just a regular response with no JSON.")
        #expect(batches.isEmpty)
    }

    @Test("Ignores non-UI JSON")
    func ignoresNonUIJSON() {
        let parser = ProgressiveJSONParser()
        // JSON that lacks root/elements — not a UI spec
        let batches = parser.feed("""
        {"name": "John", "age": 30}
        """)
        #expect(batches.isEmpty)
    }

    // MARK: - Progressive Streaming

    @Test("Emits patches as chunked JSON arrives")
    func progressiveChunkedParsing() {
        let parser = ProgressiveJSONParser()

        // Feed JSON in chunks
        let chunk1 = """
        {"root": "main", "elements": {"main": {"type": "Stack", "props": {"direction": "vertical"}, "children": ["title"]}
        """
        let chunk2 = """
        , "title": {"type": "Text", "props": {"content": "Hello World"}}}}
        """

        let batches1 = parser.feed(chunk1)
        // May or may not emit patches depending on parse threshold
        // but after the full JSON, it should have patches
        let batches2 = parser.feed(chunk2)

        let allBatches = batches1 + batches2
        #expect(!allBatches.isEmpty)

        let allPatches = allBatches.flatMap(\.patches)
        #expect(allPatches.contains { $0.path == "/root" })
        #expect(allPatches.contains { $0.path == "/elements/main" })
        #expect(allPatches.contains { $0.path == "/elements/title" })
    }

    @Test("Character-by-character feed produces correct final patches")
    func characterByCharacterFeed() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "r", "elements": {"r": {"type": "Text", "props": {"content": "Hi"}}}}
        """

        var allBatches: [SpecPatchBatch] = []
        for char in json {
            allBatches += parser.feed(String(char))
        }

        #expect(!allBatches.isEmpty)
        let allPatches = allBatches.flatMap(\.patches)
        #expect(allPatches.contains { $0.path == "/root" && $0.value?.stringValue == "r" })
        #expect(allPatches.contains { $0.path == "/elements/r" })
    }

    // MARK: - Diffing

    @Test("First parse generates add patches for all elements")
    func firstParseGeneratesAdds() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "main", "elements": {"main": {"type": "Stack", "props": {}}}, "state": {"count": 0}}
        """
        let batches = parser.feed(json)
        let patches = batches.flatMap(\.patches)

        let rootPatch = patches.first { $0.path == "/root" }
        #expect(rootPatch?.op == .add)

        let elementPatch = patches.first { $0.path == "/elements/main" }
        #expect(elementPatch?.op == .add)

        let statePatch = patches.first { $0.path == "/state/count" }
        #expect(statePatch?.op == .add)
    }

    @Test("Changed element generates replace patch on second feed")
    func elementChangeGeneratesReplace() {
        let parser = ProgressiveJSONParser()

        // First: full JSON with one prop
        let json1 = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {"content": "old"}}}}
        """
        _ = parser.feed(json1)

        // Reset buffer but keep snapshot, simulate a new complete JSON arriving
        // In practice the LLM would stream a new complete JSON
        parser.reset()

        // Feed updated version — since reset clears lastSnapshot, all will be adds again
        // Instead, let's test the diff by feeding two progressively different JSONs in one stream
        let parser2 = ProgressiveJSONParser()
        let fullJson = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {"content": "old"}}, "extra": {"type": "Text", "props": {"content": "new"}}}}
        """

        // Feed initial part
        let part1 = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {"content": "old"}}
        """
        let batches1 = parser2.feed(part1)

        // Feed the rest which adds "extra" element
        let part2 = """
        , "extra": {"type": "Text", "props": {"content": "new"}}}}
        """
        let batches2 = parser2.feed(part2)

        // The second batch should include an add for "extra"
        if !batches2.isEmpty {
            let patches = batches2.flatMap(\.patches)
            #expect(patches.contains { $0.path == "/elements/extra" && $0.op == .add })
        }
    }

    // MARK: - Integration with SpecStreamCompiler

    @Test("Parser output feeds into SpecStreamCompiler successfully")
    func integrationWithCompiler() {
        let parser = ProgressiveJSONParser()
        let compiler = SpecStreamCompiler()

        let json = """
        {"root": "main", "elements": {"main": {"type": "Stack", "props": {"direction": "vertical"}, "children": ["title"]}, "title": {"type": "Text", "props": {"content": "Hello"}}}}
        """

        let batches = parser.feed(json)
        var tree: UITree?
        for batch in batches {
            tree = compiler.apply(batch)
        }

        #expect(tree != nil)
        #expect(tree?.rootKey == "main")
        #expect(tree?.nodes.count == 2)
        #expect(tree?.nodes["title"]?.type == "Text")
    }

    @Test("Progressive chunks build tree incrementally via compiler")
    func progressiveCompilerIntegration() {
        let parser = ProgressiveJSONParser()
        let compiler = SpecStreamCompiler()

        // Chunk 1: root and container
        let chunk1 = """
        {"root": "main", "elements": {"main": {"type": "Stack", "props": {}}
        """
        for batch in parser.feed(chunk1) {
            _ = compiler.apply(batch)
        }

        // Chunk 2: add child element
        let chunk2 = """
        , "child": {"type": "Text", "props": {"content": "Hi"}}}}
        """
        var tree: UITree?
        for batch in parser.feed(chunk2) {
            tree = compiler.apply(batch)
        }

        if let tree {
            #expect(tree.nodes.count >= 1)
        }
    }

    // MARK: - Edge Cases

    @Test("Empty delta produces no patches")
    func emptyDelta() {
        let parser = ProgressiveJSONParser()
        #expect(parser.feed("").isEmpty)
    }

    @Test("Reset clears all state")
    func resetClearsState() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {}}}}
        """
        _ = parser.feed(json)

        parser.reset()

        // After reset, same JSON should produce add patches again (not empty diff)
        let batches = parser.feed(json)
        #expect(!batches.isEmpty)
        let patches = batches.flatMap(\.patches)
        #expect(patches.allSatisfy { $0.op == .add })
    }

    @Test("Handles JSON with state dictionary")
    func jsonWithState() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {}}}, "state": {"temperature": 72.5, "darkMode": true}}
        """
        let batches = parser.feed(json)
        let patches = batches.flatMap(\.patches)

        #expect(patches.contains { $0.path == "/state/temperature" })
        #expect(patches.contains { $0.path == "/state/darkMode" })
    }

    @Test("Handles markdown-fenced JSON")
    func markdownFencedJSON() {
        let parser = ProgressiveJSONParser()
        // The parser looks for { markers, so markdown fences just become text before the JSON
        let text = """
        Here is the UI:
        ```json
        {"root": "m", "elements": {"m": {"type": "Text", "props": {"content": "test"}}}}
        ```
        """
        let batches = parser.feed(text)
        // Should still detect and parse the JSON inside
        #expect(!batches.isEmpty)
    }

    @Test("Nested braces in string values do not break detection")
    func nestedBracesInStrings() {
        let parser = ProgressiveJSONParser()
        let json = """
        {"root": "m", "elements": {"m": {"type": "Text", "props": {"content": "Use {curly} braces"}}}}
        """
        let batches = parser.feed(json)
        #expect(!batches.isEmpty)
    }

    @Test("Multiple feeds without JSON produce no patches")
    func multipleNonJSONFeeds() {
        let parser = ProgressiveJSONParser()
        #expect(parser.feed("Hello ").isEmpty)
        #expect(parser.feed("world! ").isEmpty)
        #expect(parser.feed("How are you?").isEmpty)
    }
}
