//
//  QCPToolManager.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation
import OSLog
import Combine



/// Core tool manager for handling tool registration and execution
@globalActor public actor QCPToolManager {
    
    public actor Tool {
        let tool: QCPTool
        private let logger: Logger
        
        public init(_ tool: QCPTool) {
            self.tool = tool
            self.logger = Logger(subsystem: "com.bristolavenue.qcp", category: "Tool.\(tool.name)")
        }
        
        public func execute(with input: [String: String]) async throws -> QCPToolResult {
            logger.debug("Executing tool")
            return try await tool.execute(with: input)
        }
        
        public nonisolated var name: String {
            tool.name
        }
        
        public nonisolated var inputSchema: [String: QCPToolProperty] {
            tool.inputSchema
        }
    }
    
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "ToolManager")
    private var tools: [String: Tool] = [:]
    private var toolStates: [String: QCPAPIState] = [:]
    
    public static let shared = QCPToolManager()
    
    private init() {}
    
    /// Register a tool with the manager
    public func register(_ tool: QCPTool) {
        logger.debug("Registering tool: \(tool.name)")
        tools[tool.name] = Tool(tool)
        toolStates[tool.name] = .unknown
    }
    
    /// Remove a tool from the manager
    public func unregister(_ name: String) {
        logger.debug("Unregistering tool: \(name)")
        tools.removeValue(forKey: name)
        toolStates.removeValue(forKey: name)
    }
    
    /// Get the current state of a tool
    public func getToolState(_ name: String) -> QCPAPIState {
        return toolStates[name] ?? .unknown
    }
    
    /// Execute a specific tool with provided inputs
    public func executeTool(_ name: String, with input: [String: String]) async throws -> QCPToolResult {
        guard let tool = tools[name] else {
            toolStates[name] = .error
            throw QCPToolError.toolNotFound(name)
        }
        
        logger.debug("Executing tool: \(name)")
        toolStates[name] = .processing
        
        do {
            // Validate input against schema
            try validateToolInput(input, against: tool)
            
            // Execute the tool
            let result = try await tool.execute(with: input)
            toolStates[name] = result.state
            return result
        } catch {
            logger.error("Tool execution failed: \(error.localizedDescription)")
            toolStates[name] = .error
            
            if let toolError = error as? QCPToolError {
                throw toolError
            }
            
            throw QCPToolError.executionFailed(error.localizedDescription)
        }
    }
    
    /// Process all tool uses in a message
    public func processToolUses(_ message: String) async -> [QCPToolResult] {
        let toolUses = parseToolUses(from: message)
        var results: [QCPToolResult] = []
        
        for toolUse in toolUses {
            do {
                let result = try await executeTool(toolUse.name, with: toolUse.input)
                results.append(result)
            } catch {
                toolStates[toolUse.name] = .error
                results.append(QCPToolResult(
                    success: false,
                    content: error.localizedDescription,
                    isError: true,
                    metadata: nil,
                    state: .error
                ))
            }
        }
        
        return results
    }
    
    /// Parse tool uses from a message
    private func parseToolUses(from message: String) -> [(name: String, input: [String: String])] {
        logger.debug("Parsing tool uses from message")
        
        let pattern = #"(\{(?:[^{}]|(?:\{[^{}]*\}))*\})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            logger.error("Failed to create regex for tool parsing")
            return []
        }
        
        let range = NSRange(message.startIndex..., in: message)
        let matches = regex.matches(in: message, options: [], range: range)
        
        return matches.compactMap { match -> (name: String, input: [String: String])? in
            guard let range = Range(match.range, in: message) else { return nil }
            let jsonString = String(message[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toolName = json["tool"] as? String,
                  let toolInput = json["input"] as? [String: String] else {
                return nil
            }
            
            return (name: toolName, input: toolInput)
        }
    }
    
    /// Validate tool input against its schema
    private func validateToolInput(_ input: [String: String], against tool: Tool) throws {
        let schema = tool.inputSchema
        
        // Check required properties
        let requiredProperties = schema.filter { $0.value.required }.keys
        for required in requiredProperties {
            guard input[required] != nil else {
                throw QCPToolError.missingRequiredInput(required)
            }
        }
        
        // Validate enum values
        for (key, value) in input {
            if let property = schema[key],
               let enumValues = property.enumValues,
               !enumValues.contains(value) {
                throw QCPToolError.invalidEnumValue(key, value, allowed: enumValues)
            }
        }
    }
}

/// Tool-related errors
public enum QCPToolError: Error, LocalizedError {
    case toolNotFound(String)
    case invalidInput(String)
    case executionFailed(String)
    case missingRequiredInput(String)
    case invalidEnumValue(String, String, allowed: [String])
    case parsingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .invalidInput(let details):
            return "Invalid tool input: \(details)"
        case .executionFailed(let details):
            return "Tool execution failed: \(details)"
        case .missingRequiredInput(let field):
            return "Missing required input: \(field)"
        case .invalidEnumValue(let field, let value, let allowed):
            return "Invalid value '\(value)' for \(field). Allowed values: \(allowed.joined(separator: ", "))"
        case .parsingError(let details):
            return "Failed to parse tool use: \(details)"
        }
    }
}
