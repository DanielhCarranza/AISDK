//
//  ToolRegistry.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 22/01/25.
//


// ToolRegistry.swift

import Foundation

/// Global registry for tools by name
public class ToolRegistry {
    /// Map toolName -> Tool.Type
    private static var registry: [String: Tool.Type] = [:]
    
    /// Register a tool type with a unique name
    public static func register(tool: Tool.Type) {
        registry[tool.init().name] = tool
    }
    
    /// Get a registered tool type by name
    public static func toolType(forName name: String) -> Tool.Type? {
        registry[name]
    }
    
    /// For convenience, a method to register multiple tools at once
    public static func registerAll(tools: [Tool.Type]) {
        for t in tools {
            register(tool: t)
        }
    }
}
