import Foundation

/// Simple configuration manager for environment variables and settings
public class ConfigManager {
    public static let shared = ConfigManager()
    
    private init() {}
    
    /// Get configuration value by key
    public subscript(key: String) -> String? {
        return ProcessInfo.processInfo.environment[key]
    }
    
    /// Get configuration value with default
    public func value(for key: String, default defaultValue: String) -> String {
        return ProcessInfo.processInfo.environment[key] ?? defaultValue
    }
} 