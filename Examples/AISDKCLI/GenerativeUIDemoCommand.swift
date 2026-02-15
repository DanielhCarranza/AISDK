//
//  GenerativeUIDemoCommand.swift
//  AISDKCLI
//
//  Standalone demos for GenerativeUI subsystems.
//  Run with: swift run AISDKCLI generative-ui-demo
//

import Foundation
import AISDK

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Entry Point

func runGenerativeUIDemo() async {
    print("""

    \(ANSIStyles.bold(ANSIStyles.cyan("=========================================")))
    \(ANSIStyles.bold("  GenerativeUI Demo Suite"))
    \(ANSIStyles.bold(ANSIStyles.cyan("=========================================")))

    """)

    // Demo 1: SpecStream progressive rendering
    runSpecStreamDemo()

    // Demo 2: UITool execution & metadata
    #if canImport(SwiftUI)
    await runUIToolDemo()
    #else
    print(ANSIStyles.warning("Demo 2: Skipped (SwiftUI not available on this platform)"))
    #endif

    // Demo 3: Bidirectional state change
    await runStateChangeDemo()

    print("\n\(ANSIStyles.bold(ANSIStyles.green("All 3 demos completed successfully.")))\n")
}

// MARK: - Demo 1: SpecStream Progressive Rendering

private func runSpecStreamDemo() {
    print(ANSIStyles.bold("Demo 1: SpecStream Progressive Rendering"))
    print(String(repeating: "-", count: 50))
    print("")

    let compiler = SpecStreamCompiler()
    let renderer = TerminalUIRenderer()

    // Step 1: Set root and add Card container
    let batch1 = SpecPatchBatch(patches: [
        SpecPatch(op: .add, path: "/root", value: SpecValue("dashboard")),
        SpecPatch(op: .add, path: "/elements/dashboard", value: SpecValue([
            "type": SpecValue("Card"),
            "props": SpecValue([
                "title": SpecValue("Demo Dashboard"),
            ]),
            "children": SpecValue([
                SpecValue("heading"),
                SpecValue("revenue"),
                SpecValue("refresh_btn"),
            ]),
        ])),
    ])
    printStep(1, "Set root + Card container", compiler: compiler, batch: batch1, renderer: renderer)

    // Step 2: Add headline text
    let batch2 = SpecPatchBatch(patches: [
        SpecPatch(op: .add, path: "/elements/heading", value: SpecValue([
            "type": SpecValue("Text"),
            "props": SpecValue([
                "content": SpecValue("Sales Overview"),
                "style": SpecValue("headline"),
            ]),
        ])),
    ])
    printStep(2, "Add headline text", compiler: compiler, batch: batch2, renderer: renderer)

    // Step 3: Add revenue text
    let batch3 = SpecPatchBatch(patches: [
        SpecPatch(op: .add, path: "/elements/revenue", value: SpecValue([
            "type": SpecValue("Text"),
            "props": SpecValue([
                "content": SpecValue("Revenue: $12,345"),
            ]),
        ])),
    ])
    printStep(3, "Add revenue text", compiler: compiler, batch: batch3, renderer: renderer)

    // Step 4: Add refresh button
    let batch4 = SpecPatchBatch(patches: [
        SpecPatch(op: .add, path: "/elements/refresh_btn", value: SpecValue([
            "type": SpecValue("Button"),
            "props": SpecValue([
                "title": SpecValue("Refresh"),
                "action": SpecValue("refresh"),
                "style": SpecValue("primary"),
            ]),
        ])),
    ])
    printStep(4, "Add refresh button", compiler: compiler, batch: batch4, renderer: renderer)

    // Step 5: Replace revenue with updated value (simulating live data)
    let batch5 = SpecPatchBatch(patches: [
        SpecPatch(op: .replace, path: "/elements/revenue", value: SpecValue([
            "type": SpecValue("Text"),
            "props": SpecValue([
                "content": SpecValue("Revenue: $15,000"),
            ]),
        ])),
    ])
    printStep(5, "Replace revenue (live update)", compiler: compiler, batch: batch5, renderer: renderer)

    print("  Patches applied: \(compiler.appliedPatchCount), skipped: \(compiler.skippedPatchCount)")
    print("")
}

private func printStep(
    _ step: Int,
    _ label: String,
    compiler: SpecStreamCompiler,
    batch: SpecPatchBatch,
    renderer: TerminalUIRenderer
) {
    print("  Step \(step): \(label)")
    if let tree = compiler.apply(batch) {
        print("  Elements: \(tree.nodeCount)")
        do {
            let rendered = try renderer.render(tree: tree)
            // Indent rendered output
            let indented = rendered
                .components(separatedBy: "\n")
                .map { "    \($0)" }
                .joined(separator: "\n")
            print(indented)
        } catch {
            print("    (render error: \(error.localizedDescription))")
        }
    } else {
        print("    (no tree yet — root element not added)")
    }
    print("")
}

// MARK: - Demo 2: UITool Execution & Metadata

#if canImport(SwiftUI)

struct DemoWeatherUITool: UITool {
    let name = "demo_weather"
    let description = "Get simulated weather for a city"

    @Parameter(description: "City name")
    var city: String = ""

    func execute() async throws -> ToolResult {
        // Simulated weather data — no network call needed
        ToolResult(content: "Weather in \(city): Sunny, 72F, Humidity 45%")
    }

    var body: some View {
        Text("Weather: \(city)")
    }
}

private func runUIToolDemo() async {
    print(ANSIStyles.bold("Demo 2: UITool Execution & Metadata"))
    print(String(repeating: "-", count: 50))
    print("")

    // Create and configure the tool
    var tool = DemoWeatherUITool()
    do {
        try tool.setParameters(from: ["city": "San Francisco"])
    } catch {
        print("  Parameter error: \(error)")
        return
    }

    print("  Tool name: \(tool.name)")
    print("  Tool description: \(tool.description)")
    print("  Parameter city: \"\(tool.city)\"")
    print("")

    // Execute the tool
    do {
        let result = try await tool.execute()
        print("  Execution result: \(result.content)")
        print("")

        // Simulate Agent behavior: wrap result with UIToolResultMetadata
        let metadata = UIToolResultMetadata(
            toolTypeName: String(describing: DemoWeatherUITool.self),
            hasUIView: true
        )
        let wrappedResult = ToolResult(
            content: result.content,
            metadata: metadata,
            artifacts: result.artifacts
        )

        // Verify metadata attachment
        if let meta = wrappedResult.metadata as? UIToolResultMetadata {
            print("  UIToolResultMetadata attached:")
            print("    toolTypeName: \(meta.toolTypeName)")
            print("    hasUIView: \(meta.hasUIView)")
        } else {
            print("  ERROR: metadata not attached correctly")
        }

        // Verify UITool conformance
        let conformsToUITool = tool is any UITool
        print("  Conforms to UITool: \(conformsToUITool)")
    } catch {
        print("  Execution error: \(error)")
    }
    print("")
}

#endif

// MARK: - Demo 3: Bidirectional State Change

private func runStateChangeDemo() async {
    print(ANSIStyles.bold("Demo 3: Bidirectional State Change"))
    print(String(repeating: "-", count: 50))
    print("")

    // Use nonisolated(unsafe) to avoid Swift 6 concurrency warning
    // The closure runs synchronously on MainActor so this is safe
    nonisolated(unsafe) var capturedEvent: UIStateChangeEvent?

    await MainActor.run {
        let viewModel = GenerativeUIViewModel()

        viewModel.onStateChange = { event in
            capturedEvent = event
        }

        // Create and emit a state change event
        let event = UIStateChangeEvent(
            componentName: "temperature_slider",
            path: "/state/temperature",
            value: SpecValue(72.5),
            previousValue: SpecValue(68.0)
        )

        viewModel.handleStateChange(event)
    }

    // Verify the handler received it
    if let captured = capturedEvent {
        print("  Handler received event:")
        print("    componentName: \(captured.componentName)")
        print("    path: \(captured.path)")
        print("    value: \(captured.value)")
        if let prev = captured.previousValue {
            print("    previousValue: \(prev)")
        }
        print("    timestamp: \(captured.timestamp)")
    } else {
        print("  ERROR: handler did not receive the event")
    }
    print("")
}
