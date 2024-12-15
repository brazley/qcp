//
//  QCPToolKit.swift
//  QCP
//
//  Created by Quikolas on 12/15/24.
//

import Foundation

public protocol QCPToolProvider: Sendable {
    var tools: [QCPTool] { get }
    func register(with manager: QCPToolManager) async
}

@globalActor public actor QCPToolKitActor {
    public static let shared = QCPToolKitActor()
}

@QCPToolKitActor
public final class QCPToolKit: @unchecked Sendable {
    public static let shared = QCPToolKit()
    private var providers: [QCPToolProvider] = []
    
    private init() {}
    
    public func register(_ provider: QCPToolProvider) {
        providers.append(provider)
    }
    
    public func loadTools(into manager: QCPToolManager) async {
        for provider in providers {
            await provider.register(with: manager)
        }
    }
}

// MARK: - File System Tools
public actor QCPFileSystemTools: @preconcurrency QCPToolProvider {
    private let fileService: QCPFileSystemService
    
    public init(fileService: QCPFileSystemService = .shared) {
        self.fileService = fileService
    }
    
    public var tools: [QCPTool] {
        [
            QCPTextEditorTool(fileService: fileService),
            QCPFileSearchTool(fileService: fileService),
            QCPFileWatcherTool(fileService: fileService)
        ]
    }
    
    public func register(with manager: QCPToolManager) async {
        for tool in tools {
            await manager.register(tool)
        }
    }
}

// MARK: - File System Tool Implementations
public struct QCPFileSearchTool: QCPTool {
    public let name = "file.search"
    public let description = "Search file contents and metadata"
    
    public let inputSchema: [String: QCPToolProperty] = [
        "query": .init(
            type: "string",
            description: "Search query",
            required: true
        ),
        "path": .init(
            type: "string",
            description: "Path to search in",
            required: true
        ),
        "type": .init(
            type: "string",
            description: "Search type (content/name/metadata)",
            required: true,
            enumValues: ["content", "name", "metadata"]
        )
    ]
    
    private let fileService: QCPFileSystemService
    
    public init(fileService: QCPFileSystemService) {
        self.fileService = fileService
    }
    
    public func execute(with input: [String: String]) async throws -> QCPToolResult {
        // Implementation here
        return QCPToolResult(success: true, content: "Search results")
    }
}

public struct QCPFileWatcherTool: QCPTool {
    public let name = "file.watch"
    public let description = "Watch files/directories for changes"
    
    public let inputSchema: [String: QCPToolProperty] = [
        "path": .init(
            type: "string",
            description: "Path to watch",
            required: true
        ),
        "events": .init(
            type: "string",
            description: "Events to watch for",
            required: true,
            enumValues: ["created", "modified", "deleted", "all"]
        )
    ]
    
    private let fileService: QCPFileSystemService
    
    public init(fileService: QCPFileSystemService) {
        self.fileService = fileService
    }
    
    public func execute(with input: [String: String]) async throws -> QCPToolResult {
        // Implementation here
        return QCPToolResult(success: true, content: "Watching path")
    }
}

// MARK: - Extension for Setup
extension QCPToolKit {
    @QCPToolKitActor
    public static func configureDefaultTools(
        fileService: QCPFileSystemService = .shared
    ) async {
        let toolKit = QCPToolKit.shared
        
        // Register file system tools
        toolKit.register(await QCPFileSystemTools(fileService: fileService))
        
        // Load all tools into the manager
        await toolKit.loadTools(into: QCPToolManager.shared)
    }
}
