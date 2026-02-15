//
//  UITool.swift
//  AISDK
//
//  UITool protocol for tools that render SwiftUI views alongside execution.
//  Provides lifecycle-aware rendering with loading/executing/complete/error phases.
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - UIToolPhase

/// Lifecycle phase for UITool rendering.
///
/// Each phase represents a stage in the tool's execution lifecycle:
/// - `.loading` — Tool call received, parameters being configured
/// - `.executing(progress:)` — Tool is actively executing
/// - `.complete(result:)` — Execution finished successfully
/// - `.error(_:)` — Execution failed
public enum UIToolPhase: Sendable {
    /// Tool call received, preparing to execute
    case loading
    /// Tool is actively executing (optional progress 0.0-1.0)
    case executing(progress: Double?)
    /// Execution completed successfully
    case complete(result: ToolResult)
    /// Execution failed
    case error(Error)
}

// MARK: - UITool Protocol

/// A tool that renders a SwiftUI view alongside its execution.
///
/// `UITool` extends the `Tool` protocol with an associated SwiftUI `View` type.
/// When an agent executes a UITool, the SDK automatically manages the rendering
/// lifecycle, showing appropriate views for each execution phase.
///
/// ## Simple Usage
/// For tools that only need to render after completion:
/// ```swift
/// struct WeatherTool: UITool {
///     @Parameter var location: String
///
///     func execute() async throws -> ToolResult {
///         let weather = try await fetchWeather(location)
///         return ToolResult(content: weather.description)
///     }
///
///     var body: some View {
///         WeatherCard(location: location, result: toolResult)
///     }
/// }
/// ```
///
/// ## Lifecycle-Aware Usage
/// For tools that need full lifecycle control, also conform to `LifecycleUITool`:
/// ```swift
/// struct DashboardTool: UITool, LifecycleUITool {
///     func execute() async throws -> ToolResult { ... }
///
///     func render(phase: UIToolPhase) -> some View {
///         switch phase {
///         case .loading: ShimmerPlaceholder()
///         case .executing(let p): ProgressOverlay(progress: p)
///         case .complete(let r): DashboardView(data: r)
///         case .error(let e): ErrorCard(error: e)
///         }
///     }
/// }
/// ```
public protocol UITool: Tool {
    /// The SwiftUI view type for rendering
    associatedtype Body: View

    /// The most recent tool result (set after execution completes)
    var toolResult: ToolResult? { get }

    /// Render the tool's view (simple case — called after execution completes)
    @ViewBuilder var body: Body { get }
}

// MARK: - UITool Default Implementations

extension UITool {
    /// Default toolResult returns nil (overridden by framework when executing)
    public var toolResult: ToolResult? { nil }
}

// MARK: - LifecycleUITool Protocol

/// A UITool that provides custom rendering for each execution phase.
///
/// Conform to this protocol in addition to `UITool` when you need to show
/// custom loading, progress, or error states during tool execution.
public protocol LifecycleUITool: UITool {
    /// The view type returned by phase-based rendering
    associatedtype PhaseView: View

    /// Render a view based on the current execution phase
    @ViewBuilder func render(phase: UIToolPhase) -> PhaseView
}

// MARK: - UITool Metadata

/// Metadata attached to ToolResult when the executed tool conforms to UITool.
///
/// Consumers can check for this metadata to decide whether to render
/// a UITool view for the result.
public struct UIToolResultMetadata: ToolMetadata {
    /// The name of the tool type (for lookup in UITool registry)
    public let toolTypeName: String
    /// Whether the tool has an associated UI view
    public let hasUIView: Bool

    public init(toolTypeName: String, hasUIView: Bool = true) {
        self.toolTypeName = toolTypeName
        self.hasUIView = hasUIView
    }
}

// MARK: - Default UITool View

/// A default card view shown for UITool results when no custom body is provided.
public struct DefaultUIToolView: View {
    public let toolName: String
    public let result: ToolResult?

    public init(toolName: String, result: ToolResult?) {
        self.toolName = toolName
        self.result = result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                Text(toolName)
                    .font(.headline)
            }

            if let result {
                Text(result.content)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Default Lifecycle Views

/// Default loading view for LifecycleUITool
public struct UIToolLoadingView: View {
    public let toolName: String

    public init(toolName: String) {
        self.toolName = toolName
    }

    public var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(toolName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Default error view for LifecycleUITool
public struct UIToolErrorView: View {
    public let error: Error

    public init(error: Error) {
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.headline)
            }
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#endif
