//
//  SpecStreamCompilerTests.swift
//  AISDKTests
//
//  Tests for SpecStreamCompiler patch application and JSONL processing
//

import Testing
import Foundation
@testable import AISDK

@Suite("SpecStreamCompiler")
struct SpecStreamCompilerTests {
    // MARK: - Element Patches

    @Test("Add element creates node")
    func addElement() {
        let compiler = SpecStreamCompiler()

        // Set root first
        let rootBatch = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: SpecValue("main")),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue([
                "type": SpecValue("Stack"),
                "props": SpecValue(["direction": SpecValue("vertical")])
            ]))
        ])

        let tree = compiler.apply(rootBatch)
        #expect(tree != nil)
        #expect(tree?.rootKey == "main")
        #expect(tree?.nodes["main"]?.type == "Stack")
        #expect(compiler.appliedPatchCount == 2)
    }

    @Test("Remove element deletes node")
    func removeElement() {
        let compiler = SpecStreamCompiler()

        // Add then remove
        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("hello")])
            ])),
            SpecPatch(op: .add, path: "/elements/extra", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("extra")])
            ]))
        ]))

        #expect(compiler.elementCount == 2)

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .remove, path: "/elements/extra")
        ]))

        #expect(compiler.elementCount == 1)
    }

    @Test("Replace element updates node")
    func replaceElement() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("old")])
            ]))
        ]))

        let tree = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .replace, path: "/elements/main", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("new")])
            ]))
        ]))

        #expect(tree?.nodes["main"]?.type == "Text")
    }

    @Test("Move element transfers between keys")
    func moveElement() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Stack"), "props": SpecValue([:] as [String: SpecValue])])),
            SpecPatch(op: .add, path: "/elements/oldKey", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])]))
        ]))

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .move, path: "/elements/newKey", from: "/elements/oldKey")
        ]))

        #expect(compiler.currentTree?.nodes["oldKey"] == nil)
        #expect(compiler.currentTree?.nodes["newKey"]?.type == "Text")
    }

    @Test("Copy element duplicates node")
    func copyElement() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])]))
        ]))

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .copy, path: "/elements/copied", from: "/elements/main")
        ]))

        #expect(compiler.currentTree?.nodes["main"] != nil)
        #expect(compiler.currentTree?.nodes["copied"]?.type == "Text")
    }

    // MARK: - State Patches

    @Test("Add state value")
    func addState() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])])),
            SpecPatch(op: .add, path: "/state/revenue", value: SpecValue(12345))
        ]))

        #expect(compiler.currentState.resolve(path: "/revenue")?.intValue == 12345)
    }

    @Test("Replace state value")
    func replaceState() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])])),
            SpecPatch(op: .add, path: "/state/revenue", value: SpecValue(100))
        ]))

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .replace, path: "/state/revenue", value: SpecValue(200))
        ]))

        #expect(compiler.currentState.resolve(path: "/revenue")?.intValue == 200)
    }

    @Test("Remove state value")
    func removeState() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])])),
            SpecPatch(op: .add, path: "/state/temp", value: SpecValue("data"))
        ]))

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .remove, path: "/state/temp")
        ]))

        #expect(compiler.currentState.resolve(path: "/temp") == nil)
    }

    // MARK: - Fault Tolerance

    @Test("Invalid patch is skipped")
    func invalidPatchSkipped() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])])),
            SpecPatch(op: .add, path: "/forbidden/x", value: "bad") // Disallowed path
        ]))

        #expect(compiler.appliedPatchCount == 2)
        #expect(compiler.skippedPatchCount == 1)
    }

    @Test("Remove nonexistent element is skipped")
    func removeNonexistent() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .remove, path: "/elements/ghost")
        ]))

        #expect(compiler.skippedPatchCount == 1)
    }

    @Test("Returns nil before root is set")
    func noRootReturnsNil() {
        let compiler = SpecStreamCompiler()

        let tree = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/x", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])]))
        ]))

        #expect(tree == nil)
    }

    // MARK: - JSONL Processing

    @Test("Process complete JSONL line")
    func processCompleteLine() {
        let compiler = SpecStreamCompiler()
        let json = """
        {"patches":[{"op":"add","path":"/root","value":"main"}]}

        """
        let batches = compiler.processChunk(json)
        #expect(batches.count == 1)
        #expect(batches[0].patches[0].op == .add)
    }

    @Test("Process partial JSONL across chunks")
    func processPartialChunks() {
        let compiler = SpecStreamCompiler()

        let part1 = """
        {"patches":[{"op":"add","path
        """
        let part2 = """
        ":"/root","value":"main"}]}

        """

        let batches1 = compiler.processChunk(part1)
        #expect(batches1.isEmpty) // Incomplete line

        let batches2 = compiler.processChunk(part2)
        #expect(batches2.count == 1)
    }

    @Test("Malformed JSONL line is skipped")
    func malformedLine() {
        let compiler = SpecStreamCompiler()
        let json = "not valid json\n"
        let batches = compiler.processChunk(json)
        #expect(batches.isEmpty)
        #expect(compiler.skippedPatchCount == 1)
    }

    @Test("Multiple JSONL lines in one chunk")
    func multipleLines() {
        let compiler = SpecStreamCompiler()
        let json = """
        {"patches":[{"op":"add","path":"/root","value":"main"}]}
        {"patches":[{"op":"add","path":"/elements/main","value":{"type":"Text","props":{}}}]}

        """
        let batches = compiler.processChunk(json)
        #expect(batches.count == 2)
    }

    @Test("Empty lines are skipped")
    func emptyLines() {
        let compiler = SpecStreamCompiler()
        let json = "\n\n{\"patches\":[{\"op\":\"add\",\"path\":\"/root\",\"value\":\"main\"}]}\n\n"
        let batches = compiler.processChunk(json)
        #expect(batches.count == 1)
    }

    // MARK: - Reset

    @Test("Reset clears all state")
    func reset() {
        let compiler = SpecStreamCompiler()

        _ = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "main"),
            SpecPatch(op: .add, path: "/elements/main", value: SpecValue(["type": SpecValue("Text"), "props": SpecValue([:] as [String: SpecValue])]))
        ]))

        compiler.reset()

        #expect(compiler.currentTree == nil)
        #expect(compiler.currentRoot == nil)
        #expect(compiler.elementCount == 0)
        #expect(compiler.appliedPatchCount == 0)
        #expect(compiler.skippedPatchCount == 0)
    }

    // MARK: - Init with Existing Tree

    @Test("Initialize with existing tree")
    func initWithTree() {
        let tree = UITree(
            rootKey: "main",
            nodes: ["main": UINode(key: "main", type: "Text", propsData: Data("{}".utf8))]
        )

        let compiler = SpecStreamCompiler(tree: tree)
        #expect(compiler.currentRoot == "main")
        #expect(compiler.elementCount == 1)
    }

    // MARK: - Progressive Build

    @Test("Build a UI progressively across multiple batches")
    func progressiveBuild() {
        let compiler = SpecStreamCompiler()

        // Batch 1: Set up root and container
        let tree1 = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: "dashboard"),
            SpecPatch(op: .add, path: "/elements/dashboard", value: SpecValue([
                "type": SpecValue("Stack"),
                "props": SpecValue(["direction": SpecValue("vertical")]),
                "children": SpecValue([SpecValue("header")])
            ])),
            SpecPatch(op: .add, path: "/elements/header", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("Dashboard")])
            ]))
        ]))

        #expect(tree1?.nodeCount == 2)

        // Batch 2: Add a metric
        let tree2 = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/revenue", value: SpecValue([
                "type": SpecValue("Metric"),
                "props": SpecValue(["label": SpecValue("Revenue")])
            ])),
            SpecPatch(op: .add, path: "/state/metrics", value: SpecValue([
                "revenue": SpecValue(12345)
            ]))
        ]))

        #expect(tree2?.nodeCount == 3)
        #expect(compiler.currentState.resolve(path: "/metrics/revenue")?.intValue == 12345)

        // Batch 3: Update the metric value
        let tree3 = compiler.apply(SpecPatchBatch(patches: [
            SpecPatch(op: .replace, path: "/state/metrics", value: SpecValue([
                "revenue": SpecValue(99999)
            ]))
        ]))

        #expect(tree3?.nodeCount == 3) // Same elements
        #expect(compiler.currentState.resolve(path: "/metrics/revenue")?.intValue == 99999)
    }
}
