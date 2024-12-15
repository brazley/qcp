//
//  QCPAPIMessage.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation

public struct QCPAPIMessage: Codable, Sendable {
    public let id: UUID
    public let content: String
    public let agentId: String
    public let role: QCPMessageRole
    public let isInternal: Bool
    public let timestamp: Date
    public let metadata: [String: String]?
    
    public init(
        id: UUID = UUID(),
        content: String,
        agentId: String,
        role: QCPMessageRole,
        isInternal: Bool = false,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.content = content
        self.agentId = agentId
        self.role = role
        self.isInternal = isInternal
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
