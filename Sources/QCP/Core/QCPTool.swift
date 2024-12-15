//
//  QCPTool.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation

/// Protocol defining a tool's requirements and capabilities
public protocol QCPTool: Sendable {
    /// Unique name for the tool
    var name: String { get }
    
    /// Human-readable description of what the tool does
    var description: String { get }
    
    /// Schema defining the tool's input parameters
    var inputSchema: [String: QCPToolProperty] { get }
    
    /// Execute the tool with provided arguments
    func execute(with input: [String: String]) async throws -> QCPToolResult
}

/// Defines tool input schema properties
public struct QCPToolProperty: Codable, Sendable, Hashable {
    public let type: String
    public let description: String
    public let required: Bool
    public let enumValues: [String]?
    
    public init(
        type: String,
        description: String,
        required: Bool = true,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

/// Tool execution result
public struct QCPToolResult: Codable, Sendable, Hashable {
    public let success: Bool
    public let content: String
    public let isError: Bool
    public let metadata: [String: String]?
    public let state: QCPAPIState
    
    public init(
        success: Bool,
        content: String,
        isError: Bool = false,
        metadata: [String: String]? = nil,
        state: QCPAPIState = .success
    ) {
        self.success = success
        self.content = content
        self.isError = isError
        self.metadata = metadata
        self.state = state
    }
}
