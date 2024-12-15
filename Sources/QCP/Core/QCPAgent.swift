//
//  QCPAgent.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation

/// Protocol defining the core capabilities required for any agent in the QCP system
public protocol QCPAgent {
    /// Unique identifier for the agent
    var id: String { get }
    
    /// Agent's role or primary function
    var role: String { get }
    
    /// Agent's capabilities or skills
    var capabilities: [String] { get }
    
    /// Optional endpoint for agent-specific API routing
    var endpoint: String? { get }
    
    /// Agent's description
    var description: String { get }
}

/// Standard agent configuration used to initialize agents
public struct QCPAgentConfig {
    public let id: String
    public let role: String
    public let capabilities: [String]
    public let endpoint: String?
    public let description: String
    
    public init(
        id: String,
        role: String,
        capabilities: [String] = [],
        endpoint: String? = nil,
        description: String
    ) {
        self.id = id
        self.role = role
        self.capabilities = capabilities
        self.endpoint = endpoint
        self.description = description
    }
}

/// Standard agent message type for communication
public struct QCPAgentMessage: Identifiable, Codable {
    public let id: UUID
    public let agentId: String
    public let content: String
    public let isInternal: Bool
    public let role: QCPMessageRole
    public let timestamp: Date
    
    public init(
        id: UUID = UUID(),
        agentId: String,
        content: String,
        isInternal: Bool = false,
        role: QCPMessageRole,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.agentId = agentId
        self.content = content
        self.isInternal = isInternal
        self.role = role
        self.timestamp = timestamp
    }
}

/// Errors that can occur during agent operations
public enum QCPAgentError: Error, LocalizedError {
    case invalidAgent
    case invalidMessage
    case communicationError(String)
    case invalidResponse(String)
    case toolUseError(String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidAgent:
            return "Invalid or unknown agent"
        case .invalidMessage:
            return "Invalid message format"
        case .communicationError(let details):
            return "Communication error: \(details)"
        case .invalidResponse(let details):
            return "Invalid response: \(details)"
        case .toolUseError(let details):
            return "Tool use error: \(details)"
        case .unknown(let details):
            return "Unknown error: \(details)"
        }
    }
}
