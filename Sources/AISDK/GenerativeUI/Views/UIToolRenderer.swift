//
//  UIToolRenderer.swift
//  AISDK
//
//  SwiftUI view that manages UITool lifecycle and rendering.
//  Automatically transitions between loading/executing/complete/error phases.
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - UIToolRenderer

/// A SwiftUI view that manages the execution lifecycle of a UITool.
///
/// `UIToolRenderer` handles the full lifecycle:
/// 1. Shows a loading state when the tool is preparing
/// 2. Shows progress during execution (if available)
/// 3. Shows the tool's custom view on completion
/// 4. Shows an error view if execution fails
///
/// For `LifecycleUITool` conformances, it delegates to `render(phase:)`.
/// For basic `UITool` conformances, it uses default loading/error views
/// and the tool's `body` for the complete state.
///
/// ## Usage
/// ```swift
/// UIToolRenderer(tool: myWeatherTool)
///     .onComplete { result in
///         // Handle completion
///     }
/// ```
@MainActor
public struct UIToolRenderer<T: UITool>: View {
    /// The tool being rendered
    private let tool: T

    /// Current execution phase
    @State private var phase: UIToolPhase = .loading

    /// Whether execution has started
    @State private var hasStarted: Bool = false

    /// Completion callback
    private var onComplete: ((ToolResult) -> Void)?

    /// Error callback
    private var onError: ((Error) -> Void)?

    public init(tool: T) {
        self.tool = tool
    }

    public var body: some View {
        Group {
            if let lifecycleTool = tool as? any LifecycleUITool {
                AnyView(renderLifecycle(lifecycleTool))
            } else {
                renderDefault()
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await executeTool()
        }
    }

    // MARK: - Default Rendering (non-lifecycle UITool)

    @ViewBuilder
    private func renderDefault() -> some View {
        switch phase {
        case .loading:
            UIToolLoadingView(toolName: tool.name)

        case .executing(let progress):
            VStack(spacing: 8) {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
                Text(tool.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

        case .complete:
            tool.body

        case .error(let error):
            UIToolErrorView(error: error)
        }
    }

    // MARK: - Lifecycle Rendering

    private func renderLifecycle(_ lifecycleTool: some LifecycleUITool) -> some View {
        lifecycleTool.render(phase: phase)
    }

    // MARK: - Execution

    private func executeTool() async {
        phase = .executing(progress: nil)

        do {
            let result = try await tool.execute()
            phase = .complete(result: result)
            onComplete?(result)
        } catch {
            phase = .error(error)
            onError?(error)
        }
    }

    // MARK: - Modifiers

    /// Add a completion handler
    public func onComplete(_ handler: @escaping (ToolResult) -> Void) -> UIToolRenderer {
        var copy = self
        copy.onComplete = handler
        return copy
    }

    /// Add an error handler
    public func onError(_ handler: @escaping (Error) -> Void) -> UIToolRenderer {
        var copy = self
        copy.onError = handler
        return copy
    }
}

// MARK: - AnyUIToolRenderer

/// Type-erased UITool renderer for use when the specific tool type is not known.
///
/// This is used by the agent's tool execution pipeline to render any UITool
/// without knowing its concrete type at compile time.
@MainActor
public struct AnyUIToolRenderer: View {
    private let toolType: any UITool.Type
    private let arguments: Data
    @State private var phase: UIToolPhase = .loading
    @State private var hasStarted = false
    @State private var configuredToolBody: AnyView?

    public init(toolType: any UITool.Type, arguments: Data) {
        self.toolType = toolType
        self.arguments = arguments
    }

    public var body: some View {
        Group {
            switch phase {
            case .loading:
                UIToolLoadingView(toolName: toolType.init().name)

            case .executing:
                VStack(spacing: 8) {
                    ProgressView()
                    Text(toolType.init().name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            case .complete(let result):
                if let configuredToolBody {
                    configuredToolBody
                } else {
                    DefaultUIToolView(toolName: toolType.init().name, result: result)
                }

            case .error(let error):
                UIToolErrorView(error: error)
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await executeAnyTool()
        }
    }

    private func executeAnyTool() async {
        phase = .executing(progress: nil)

        do {
            var tool = toolType.init()
            let configured = try tool.validateAndSetParameters(arguments)
            let result = try await configured.execute()
            configuredToolBody = extractBody(configured)
            phase = .complete(result: result)
        } catch {
            phase = .error(error)
        }
    }

    /// Extract the custom body from a configured UITool via a generic helper
    /// that opens the existential type.
    private func extractBody(_ tool: some Tool) -> AnyView? {
        guard let uiTool = tool as? any UITool else { return nil }
        return AnyView(uiTool.body)
    }
}

#endif
