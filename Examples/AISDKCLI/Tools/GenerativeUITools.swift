//
//  GenerativeUITools.swift
//  AISDKCLI
//
//  Demo tools for testing GenerativeUI subsystems via the interactive CLI.
//  Each tool demonstrates a different GenerativeUI capability.
//

import Foundation
import AISDK

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - 1. WeatherDashboardTool (UITool Demo)

/// A UITool that renders a weather dashboard card.
/// Demonstrates: UITool conformance, UIToolResultMetadata auto-attachment by Agent,
/// and UITree rendering in the terminal.
///
/// Test with: "What's the weather in Tokyo?"
#if canImport(SwiftUI)
struct WeatherDashboardTool: UITool {
    let name = "weather_dashboard"
    let description = "Display a weather dashboard card for a city. Use this when asked about weather."

    @Parameter(description: "The city name to get weather for")
    var city: String = ""

    func execute() async throws -> ToolResult {
        // Simulated weather data
        let temp = Int.random(in: 55...95)
        let humidity = Int.random(in: 30...80)
        let conditions = ["Sunny", "Partly Cloudy", "Overcast", "Light Rain", "Clear Skies"].randomElement()!

        // Build a UITree JSON for the weather card
        let treeJSON = """
        {
            "root": "card",
            "elements": {
                "card": {
                    "type": "Card",
                    "props": { "title": "Weather in \(city)" },
                    "children": ["condition", "temp", "humidity"]
                },
                "condition": {
                    "type": "Text",
                    "props": { "content": "\(conditions)", "style": "headline" }
                },
                "temp": {
                    "type": "Text",
                    "props": { "content": "Temperature: \(temp)F" }
                },
                "humidity": {
                    "type": "Text",
                    "props": { "content": "Humidity: \(humidity)%" }
                }
            }
        }
        """

        return ToolResult(content: treeJSON)
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Weather Dashboard: \(city)")
                .font(.headline)
        }
    }
}
#endif

// MARK: - 2. DashboardStreamTool (SpecStream Demo)

/// A tool that demonstrates progressive SpecStream rendering.
/// Builds a dashboard card incrementally using SpecPatchBatch operations,
/// rendering each step to the terminal with delays to simulate streaming.
///
/// Test with: "Show me a sales dashboard"
struct DashboardStreamTool: Tool {
    let name = "show_dashboard"
    let description = "Show a live sales dashboard with progressive rendering. Use this when asked to show a dashboard."

    @Parameter(description: "Dashboard title")
    var title: String = "Sales Dashboard"

    func execute() async throws -> ToolResult {
        let compiler = SpecStreamCompiler()
        let renderer = TerminalUIRenderer()

        print("")
        print(ANSIStyles.cyan("   SpecStream: Building dashboard progressively..."))
        print("")

        // Step 1: Set root + card container
        let batch1 = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: SpecValue("dashboard")),
            SpecPatch(op: .add, path: "/elements/dashboard", value: SpecValue([
                "type": SpecValue("Card"),
                "props": SpecValue(["title": SpecValue(title)]),
                "children": SpecValue([
                    SpecValue("heading"),
                    SpecValue("revenue"),
                    SpecValue("users"),
                    SpecValue("refresh_btn"),
                ]),
            ])),
        ])
        renderStep(compiler: compiler, renderer: renderer, batch: batch1, label: "Card container")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Step 2: Add heading
        let batch2 = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/heading", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue([
                    "content": SpecValue("Q4 Performance"),
                    "style": SpecValue("headline"),
                ]),
            ])),
        ])
        renderStep(compiler: compiler, renderer: renderer, batch: batch2, label: "Headline")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Step 3: Add revenue
        let batch3 = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/revenue", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("Revenue: $142,500")]),
            ])),
        ])
        renderStep(compiler: compiler, renderer: renderer, batch: batch3, label: "Revenue metric")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Step 4: Add users
        let batch4 = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/users", value: SpecValue([
                "type": SpecValue("Text"),
                "props": SpecValue(["content": SpecValue("Active Users: 8,432")]),
            ])),
        ])
        renderStep(compiler: compiler, renderer: renderer, batch: batch4, label: "Users metric")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Step 5: Add refresh button
        let batch5 = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/refresh_btn", value: SpecValue([
                "type": SpecValue("Button"),
                "props": SpecValue([
                    "title": SpecValue("Refresh Data"),
                    "action": SpecValue("refresh"),
                    "style": SpecValue("primary"),
                ]),
            ])),
        ])
        renderStep(compiler: compiler, renderer: renderer, batch: batch5, label: "Action button")

        print(ANSIStyles.dim("   Patches applied: \(compiler.appliedPatchCount), skipped: \(compiler.skippedPatchCount)"))

        return ToolResult(content: "Dashboard rendered with \(compiler.appliedPatchCount) patches applied across 5 progressive steps.")
    }

    private func renderStep(
        compiler: SpecStreamCompiler,
        renderer: TerminalUIRenderer,
        batch: SpecPatchBatch,
        label: String
    ) {
        if let tree = compiler.apply(batch) {
            // Clear previous rendering with ANSI escape
            print(ANSIStyles.dim("   + \(label) (\(tree.nodeCount) elements)"))
            do {
                let rendered = try renderer.render(tree: tree)
                let indented = rendered
                    .components(separatedBy: "\n")
                    .map { "   \($0)" }
                    .joined(separator: "\n")
                print(indented)
            } catch {
                print(ANSIStyles.dim("   (render error)"))
            }
            print("")
        }
    }
}

// MARK: - 3. StateChangeDemoTool (Bidirectional State Demo)

/// A tool that demonstrates UIStateChangeEvent handling.
/// Simulates form field changes and shows how state change events
/// flow through a handler.
///
/// Test with: "Show me a user profile form"
struct StateChangeDemoTool: Tool {
    let name = "show_form"
    let description = "Show a user profile form demonstrating bidirectional state changes. Use this when asked to show a form."

    @Parameter(description: "User's name")
    var userName: String = ""

    @Parameter(description: "User's email")
    var email: String = ""

    func execute() async throws -> ToolResult {
        print("")
        print(ANSIStyles.cyan("   Bidirectional State: Simulating form interactions..."))
        print("")

        // Build and render the form UI
        let compiler = SpecStreamCompiler()
        let renderer = TerminalUIRenderer()

        let formBatch = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/root", value: SpecValue("form_card")),
            SpecPatch(op: .add, path: "/elements/form_card", value: SpecValue([
                "type": SpecValue("Card"),
                "props": SpecValue(["title": SpecValue("User Profile")]),
                "children": SpecValue([
                    SpecValue("name_input"),
                    SpecValue("email_input"),
                    SpecValue("submit_btn"),
                ]),
            ])),
            SpecPatch(op: .add, path: "/elements/name_input", value: SpecValue([
                "type": SpecValue("Input"),
                "props": SpecValue([
                    "label": SpecValue("Name"),
                    "placeholder": SpecValue("Enter your name"),
                ]),
            ])),
            SpecPatch(op: .add, path: "/elements/email_input", value: SpecValue([
                "type": SpecValue("Input"),
                "props": SpecValue([
                    "label": SpecValue("Email"),
                    "placeholder": SpecValue("Enter your email"),
                ]),
            ])),
            SpecPatch(op: .add, path: "/elements/submit_btn", value: SpecValue([
                "type": SpecValue("Button"),
                "props": SpecValue([
                    "title": SpecValue("Save Profile"),
                    "action": SpecValue("submit"),
                    "style": SpecValue("primary"),
                ]),
            ])),
        ])

        if let tree = compiler.apply(formBatch) {
            do {
                let rendered = try renderer.render(tree: tree)
                let indented = rendered
                    .components(separatedBy: "\n")
                    .map { "   \($0)" }
                    .joined(separator: "\n")
                print(indented)
            } catch {
                print(ANSIStyles.dim("   (render error)"))
            }
        }

        // Simulate state change events (as if user filled in the form)
        let nameValue = userName.isEmpty ? "Jane Doe" : userName
        let emailValue = email.isEmpty ? "jane@example.com" : email

        print("")
        print(ANSIStyles.cyan("   State Changes (simulating user input):"))
        print("")

        var capturedEvents: [UIStateChangeEvent] = []

        // Handler that captures events
        let handler: UIStateChangeHandler = { event in
            capturedEvents.append(event)
        }

        // Simulate name field change
        let nameEvent = UIStateChangeEvent(
            componentName: "name_input",
            path: "/state/form/name",
            value: SpecValue(nameValue),
            previousValue: SpecValue("")
        )
        handler(nameEvent)
        print("   \(ANSIStyles.green("->")) name_input: \"\" -> \"\(nameValue)\"")
        print("      path: \(nameEvent.path)")

        try await Task.sleep(nanoseconds: 200_000_000)

        // Simulate email field change
        let emailEvent = UIStateChangeEvent(
            componentName: "email_input",
            path: "/state/form/email",
            value: SpecValue(emailValue),
            previousValue: SpecValue("")
        )
        handler(emailEvent)
        print("   \(ANSIStyles.green("->")) email_input: \"\" -> \"\(emailValue)\"")
        print("      path: \(emailEvent.path)")

        try await Task.sleep(nanoseconds: 200_000_000)

        // Simulate submit button tap
        let submitEvent = UIStateChangeEvent(
            componentName: "submit_btn",
            path: "/state/form/submitted",
            value: SpecValue(true),
            previousValue: SpecValue(false)
        )
        handler(submitEvent)
        print("   \(ANSIStyles.green("->")) submit_btn: false -> true")
        print("      path: \(submitEvent.path)")

        print("")
        print(ANSIStyles.dim("   Handler captured \(capturedEvents.count) state change events"))

        return ToolResult(content: "Form rendered with 3 state change events: name=\(nameValue), email=\(emailValue), submitted=true")
    }
}
