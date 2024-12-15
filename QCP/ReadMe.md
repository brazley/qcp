# QCP (Quik Context Protocol) Framework Documentation

## System Overview
QCP is a Swift framework designed to facilitate communication between AI agents and tools within iOS/macOS applications. The framework provides complete infrastructure for message handling, data persistence, network communication, and tool execution.

## Core Components

### Message Flow Architecture
Messages flow through the system in this order:
1. QCPAPIMessage created (contains content, agentId, and role)
2. Message added to QCPMessageQueue
3. Message processed through QCPNetworkService if needed
4. Any tool executions handled by QCPToolManager
5. Results persisted via QCPStorageManager
6. State updates propagated through system

### Tool System Architecture

#### Tool Library System
QCP provides a built-in tool library system that allows easy integration of pre-built tools:

```swift
// Configure the toolkit with default tools
await QCPToolKit.configureDefaultTools(
    fileService: .shared,
    networkService: networkService
)

// Or register specific tool providers
let toolKit = QCPToolKit.shared
await toolKit.register(QCPFileSystemTools())
await toolKit.register(QCPNetworkTools(networkService: networkService))
```

Available Tool Categories:
1. File System Tools
   - Text Editor Tool
   - File Search Tool
   - File Watcher Tool

2. Network Tools
   - HTTP Request Tool
   - WebSocket Tool (Coming Soon)
   - Network Monitor Tool (Coming Soon)

3. Data Processing Tools (Coming Soon)
   - JSON Tool
   - CSV Tool
   - Data Transform Tool

#### Tool Definition Protocol
```swift
public protocol QCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: QCPToolProperty] { get }
    func execute(with input: [String: String]) async throws -> QCPToolResult
}
```

#### Tool Provider Protocol
```swift
public protocol QCPToolProvider: Sendable {
    var tools: [QCPTool] { get }
    func register(with manager: QCPToolManager) async
}
```

#### Tool Property Structure
```swift
public struct QCPToolProperty: Codable, Sendable, Hashable {
    public let type: String
    public let description: String
    public let required: Bool
    public let enumValues: [String]?
}
```

#### Tool Result Structure
```swift
public struct QCPToolResult: Codable, Sendable, Hashable {
    public let success: Bool
    public let content: String
    public let isError: Bool
    public let metadata: [String: String]?
    public let state: QCPAPIState
}
```

### Data Models

#### QCPAPIMessage
```swift
public struct QCPAPIMessage: Codable, Sendable {
    public let id: UUID
    public let content: String
    public let agentId: String
    public let role: QCPMessageRole
    public let isInternal: Bool
    public let timestamp: Date
    public let metadata: [String: String]?
}
```

#### QCPMessageRole
```swift
public enum QCPMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case agent
    case system
}
```

#### QCPAPIState
```swift
public enum QCPAPIState: String, Codable, Sendable {
    case processing    // Operation in progress
    case success      // Operation completed successfully
    case error        // Operation failed
    case unknown      // Initial state
}
```

### File System Operations

The framework provides comprehensive file system operations through QCPFileSystemService:

```swift
// Initialize with project directory
let projectPath = "/Users/username/Projects/MyApp"
try await QCPFileSystemService.shared.initialize(watchedPath: projectPath)

// CRUD Operations
try await fileSystem.createFile(at: "path/file.swift", content: content)
let content = try await fileSystem.readFile(at: "path/file.swift")
try await fileSystem.updateFile(at: "path/file.swift", content: updatedContent)
try await fileSystem.deleteFile(at: "path/file.swift")

// Directory Operations
try await fileSystem.createDirectory(at: "path/newFolder")
let files = try await fileSystem.listDirectory(at: "path")
try await fileSystem.deleteDirectory(at: "path/folder")

// File Watching
try await fileSystem.watchFile(at: "path/file.swift") { event in
    switch event {
    case .modified(let url):
        // Handle modification
    case .deleted(let url):
        // Handle deletion
    }
}
```

### Persistence Layer
- Uses SwiftData for data storage
- Automatically handles model schema
- Manages chat and message persistence
- Provides CRUD operations for all data types

## System Integration Instructions

### Required Initial Setup
```swift
// 1. Network Configuration
let config = QCPNetworkConfig(
    baseURL: URL(string: "api-endpoint")!,
    defaultHeaders: ["Content-Type": "application/json"]
)
let networkService = QCPNetworkService(config: config)

// 2. Message Queue Initialization
let messageQueue = QCPMessageQueue()

// 3. Storage Access
let storage = QCPStorageManager.shared

// 4. Tool Library Setup
await QCPToolKit.configureDefaultTools(
    fileService: .shared,
    networkService: networkService
)
```

### Custom Tool Integration
1. Create a tool provider:
```swift
public actor CustomToolProvider: QCPToolProvider {
    public var tools: [QCPTool] {
        [CustomTool()]
    }
    
    public func register(with manager: QCPToolManager) async {
        for tool in tools {
            await manager.register(tool)
        }
    }
}
```

2. Implement custom tool:
```swift
struct CustomTool: QCPTool {
    let name = "custom.tool"
    let description = "Custom tool description"
    let inputSchema: [String: QCPToolProperty] = [
        "parameter": .init(
            type: "string",
            description: "Parameter description",
            required: true
        )
    ]
    
    func execute(with input: [String: String]) async throws -> QCPToolResult {
        // Tool logic here
        return QCPToolResult(
            success: true,
            content: "Result",
            state: .success
        )
    }
}
```

3. Register with toolkit:
```swift
await QCPToolKit.shared.register(CustomToolProvider())
```

### Message Processing Protocol
1. Create message:
```swift
let message = QCPAPIMessage(
    content: "message_content",
    agentId: "agent_identifier",
    role: .agent
)
```

2. Process message:
```swift
messageQueue.enqueue(message)
```

3. Handle tool usage:
```swift
// Tool usage in message content format:
/*
{
    "tool": "tool.name",
    "input": {
        "parameterName": "value"
    }
}
*/
```

## Error Handling System

### Network Errors (QCPNetworkError)
- noConnection
- invalidResponse
- httpError(statusCode: Int, data: Data?)
- networkError(Error)
- decodingError(Error)
- encodingError(Error)
- noData
- serviceDeinitialized

### Tool Errors (QCPToolError)
- toolNotFound(String)
- invalidInput(String)
- executionFailed(String)
- missingRequiredInput(String)
- invalidEnumValue(String, String, allowed: [String])
- parsingError(String)

## State Management
- All operations provide state feedback through QCPAPIState
- State changes can be observed for UI updates
- Error states include detailed error information
- States persist across app sessions

## Platform Requirements
- iOS 17.0 or later
- macOS 14.0 or later
- Swift 6.0
- SwiftData (automatically included with iOS 17/macOS 14)

## Security Considerations
- All network communication should use HTTPS
- Tool validation prevents injection attacks
- Input sanitization enforced through schema
- Actor isolation prevents race conditions

## Implementation Notes
1. Always validate tool inputs against schema
2. Handle all async operations with proper error catching
3. Maintain actor isolation boundaries
4. Process messages sequentially through queue
5. Persist critical data via storage manager
6. Monitor state changes for error handling
7. Use proper error types for different scenarios
8. Register tools through QCPToolKit for better organization
9. Respect network retry policies
10. Follow provided tool patterns for consistency

## License

Proprietary - Bristol Avenue 2024
