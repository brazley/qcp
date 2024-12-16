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
    fileService: .shared
)

// Or register specific tool providers
let toolKit = QCPToolKit.shared
await toolKit.register(QCPFileSystemTools())
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

### Data Models

All message types conform to Sendable for actor isolation safety:

```swift
public struct QCPAPIMessage: Identifiable, Codable, Sendable {
    public let id: UUID
    public let content: String
    public let agentId: String
    public let role: QCPMessageRole
    public let isInternal: Bool
    public let timestamp: Date
    public let metadata: [String: String]?
}
```

### Network Architecture

The framework uses a serverless architecture for AI agent communication:

```swift
@globalActor actor BuildshipService {
    static let shared = BuildshipService()
    
    private let baseURL: URL       // Serverless endpoint
    private let qcpService: QCPBuildshipService
    
    func sendMessage(
        _ content: String,
        threadId: UUID,
        tools: [QCPTool] = []
    ) async throws -> SendableAgentMessage
}
```

Key characteristics:
- No persistent connections required
- Endpoints spin up on demand
- Built-in request error handling
- Actor isolation for thread safety

### Error Handling System

#### Network Errors (QCPNetworkError)
- noConnection
- invalidResponse
- httpError(statusCode: Int, data: Data?)
- networkError(Error)
- decodingError(Error)
- encodingError(Error)
- noData
- serviceDeinitialized

#### Tool Errors (QCPToolError)
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
- All network communication uses HTTPS
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
9. Remember serverless endpoints don't need availability checks
10. Follow provided tool patterns for consistency

## License

Proprietary - Bristol Avenue 2024
