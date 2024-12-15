//
//  QCPBuildshipService.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation
import Combine
import Network
import OSLog

/// API state tracking
public enum QCPAPIState: String, Codable, Sendable {
    case processing    // No response yet (working on it)
    case success      // Got 200 response
    case error        // Got error response (400/500)
    case unknown      // Initial state
    
    var isWorking: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}

/// Core networking configuration
public struct QCPNetworkConfig: Sendable {
    public let baseURL: URL
    public let defaultHeaders: [String: String]
    public let timeoutInterval: TimeInterval
    public let retryPolicy: QCPRetryPolicy
    
    public init(
        baseURL: URL,
        defaultHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 30,
        retryPolicy: QCPRetryPolicy = .default
    ) {
        self.baseURL = baseURL
        self.defaultHeaders = defaultHeaders
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
    }
}

/// Retry policy configuration
public struct QCPRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let backoffMultiplier: Double
    public let initialDelay: TimeInterval
    public let retryableStatusCodes: Set<Int>
    
    public static let `default` = QCPRetryPolicy(
        maxAttempts: 3,
        backoffMultiplier: 2.0,
        initialDelay: 1.0,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504]
    )
}

@globalActor public actor QCPNetworkActor {
    public static let shared = QCPNetworkActor()
}

/// Main networking service
@QCPNetworkActor
public final class QCPNetworkService: @unchecked Sendable {
    private let config: QCPNetworkConfig
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bristolavenue.qcp.NetworkMonitor")
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "NetworkService")
    
    @MainActor @Published public private(set) var isConnected = true
    @MainActor @Published public private(set) var apiState: QCPAPIState = .unknown
    private var cancellables = Set<AnyCancellable>()
    
    public init(config: QCPNetworkConfig) {
        self.config = config
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.logger.info("Network status: \(path.status == .satisfied ? "Connected" : "Disconnected")")
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    /// Send a message with optional tool context
    public func sendMessage(
        message: String,
        threadId: UUID,
        agentId: String,
        tools: [QCPTool] = [],
        endpoint: String? = nil,
        additionalContext: [String: Any]? = nil
    ) -> AnyPublisher<QCPAgentMessage, Error> {
        Deferred {
            Future { [weak self] promise in
                guard let self = self else {
                    promise(.failure(QCPNetworkError.serviceDeinitialized))
                    return
                }
                
                Task { @QCPNetworkActor in
                    await self.performRequest(
                        message: message,
                        threadId: threadId,
                        agentId: agentId,
                        tools: tools,
                        endpoint: endpoint,
                        additionalContext: additionalContext,
                        promise: promise
                    )
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func performRequest(
        message: String,
        threadId: UUID,
        agentId: String,
        tools: [QCPTool],
        endpoint: String?,
        additionalContext: [String: Any]?,
        promise: @escaping (Result<QCPAgentMessage, Error>) -> Void
    ) async {
        guard await getIsConnected() else {
            promise(.failure(QCPNetworkError.noConnection))
            return
        }
        
        await setAPIState(.processing)
        
        // Construct URL with optional endpoint
        let url: URL
        if let endpoint = endpoint {
            let cleanEndpoint = endpoint.starts(with: "/") ? String(endpoint.dropFirst()) : endpoint
            url = config.baseURL.appendingPathComponent(cleanEndpoint)
        } else {
            url = config.baseURL
        }
        
        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutInterval
        
        // Add headers
        config.defaultHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Prepare message payload
        let payload: [String: Any] = [
            "message": message,
            "threadId": threadId.uuidString,
            "agentId": agentId,
            "tools": tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema
                ]
            },
            "context": additionalContext ?? [:]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            await setAPIState(.error)
            promise(.failure(QCPNetworkError.encodingError(error)))
            return
        }
        
        await performURLRequest(request, attempt: 1, promise: promise)
    }
    
    private func performURLRequest(
        _ request: URLRequest,
        attempt: Int,
        promise: @escaping (Result<QCPAgentMessage, Error>) -> Void
    ) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await setAPIState(.error)
                promise(.failure(QCPNetworkError.invalidResponse))
                return
            }
            
            // Check if we should retry
            if shouldRetry(statusCode: httpResponse.statusCode, attempt: attempt) {
                await setAPIState(.error)
                await retryRequest(request, attempt: attempt, promise: promise)
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                await setAPIState(.error)
                promise(.failure(QCPNetworkError.httpError(
                    statusCode: httpResponse.statusCode,
                    data: data
                )))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(QCPMessageResponse.self, from: data)
                
                let message = QCPAgentMessage(
                    agentId: response.agentId,
                    content: response.content,
                    role: .assistant
                )
                
                await setAPIState(.success)
                promise(.success(message))
            } catch {
                await setAPIState(.error)
                logger.error("Decoding error: \(error.localizedDescription)")
                promise(.failure(QCPNetworkError.decodingError(error)))
            }
        } catch {
            await setAPIState(.error)
            if attempt < config.retryPolicy.maxAttempts {
                await retryRequest(request, attempt: attempt, promise: promise)
            } else {
                promise(.failure(QCPNetworkError.networkError(error)))
            }
        }
    }
    
    private func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        return config.retryPolicy.retryableStatusCodes.contains(statusCode) &&
               attempt < config.retryPolicy.maxAttempts
    }
    
    private func retryRequest(
        _ request: URLRequest,
        attempt: Int,
        promise: @escaping (Result<QCPAgentMessage, Error>) -> Void
    ) async {
        let delay = config.retryPolicy.initialDelay *
            pow(config.retryPolicy.backoffMultiplier, Double(attempt - 1))
        
        logger.info("Retrying request (attempt \(attempt + 1)) after \(delay) seconds")
        
        try? await Task.sleep(for: .seconds(delay))
        await performURLRequest(request, attempt: attempt + 1, promise: promise)
    }
    
    @MainActor
    private func setAPIState(_ state: QCPAPIState) {
        apiState = state
    }
    
    @MainActor
    private func getIsConnected() -> Bool {
        isConnected
    }
    
    deinit {
        monitor.cancel()
    }
}

/// Network response types
private struct QCPMessageResponse: Codable, Sendable {
    let agentId: String
    let content: String
    let metadata: [String: String]?
}

/// Network-related errors
public enum QCPNetworkError: Error, LocalizedError {
    case noConnection
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    case noData
    case serviceDeinitialized
    
    public var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .noData:
            return "No data received"
        case .serviceDeinitialized:
            return "Service was deinitialized"
        }
    }
}
