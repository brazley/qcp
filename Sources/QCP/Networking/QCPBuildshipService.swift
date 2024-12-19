//
//  QCPBuildshipService.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation
import Network
import Combine
import os

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

@globalActor public actor QCPBuildshipService {
    public static let shared = QCPBuildshipService()
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bristolavenue.qcp.NetworkMonitor")
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "NetworkService")
    
    @MainActor @Published public private(set) var isConnected = true
    
    private init() { }
    
    public func setup() async {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.updateConnectionStatus(path.status == .satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    @MainActor
    private func updateConnectionStatus(_ status: Bool) {
        self.isConnected = status
        logger.info("Network status: \(status ? "Connected" : "Disconnected")")
    }
    
    public func sendMessage(
        _ content: String,
        baseURL: URL,
        threadId: UUID,
        tools: [QCPTool] = [],
        endpoint: String? = nil
    ) async throws -> QCPAgentMessage {
        guard await isConnected else {
            throw QCPNetworkError.noConnection
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Construct URL with endpoint
            let url: URL
            if let endpoint = endpoint {
                let cleanEndpoint = endpoint.starts(with: "/") ? String(endpoint.dropFirst()) : endpoint
                url = baseURL.appendingPathComponent(cleanEndpoint)
            } else {
                url = baseURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Prepare message payload
            let payload: [String: Any] = [
                "message": content,
                "threadId": threadId.uuidString,
                "tools": tools.map { tool in
                    [
                        "name": tool.name,
                        "description": tool.description,
                        "input_schema": [
                            "type": "object",
                            "properties": tool.inputSchema,
                            "required": Array(tool.inputSchema.filter { $0.value.required }.keys)
                        ]
                    ]
                }
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                continuation.resume(throwing: QCPNetworkError.encodingError(error))
                return
            }
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self else {
                    continuation.resume(throwing: QCPNetworkError.serviceDeinitialized)
                    return
                }
                
                if let error = error {
                    self.logger.error("Network error: \(error.localizedDescription)")
                    continuation.resume(throwing: QCPNetworkError.networkError(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.logger.error("Invalid response")
                    continuation.resume(throwing: QCPNetworkError.invalidResponse)
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    self.logger.error("HTTP error: \(httpResponse.statusCode)")
                    continuation.resume(throwing: QCPNetworkError.httpError(statusCode: httpResponse.statusCode, data: data))
                    return
                }
                
                guard let data = data else {
                    self.logger.error("No data received")
                    continuation.resume(throwing: QCPNetworkError.noData)
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(ResponseData.self, from: data)
                    self.logger.info("Received response for threadId: \(threadId.uuidString)")
                    
                    let message = QCPAgentMessage(
                        id: UUID(),
                        agentId: "assistant",
                        content: response.resolvedMessage,
                        role: .assistant
                    )
                    
                    continuation.resume(returning: message)
                } catch {
                    self.logger.error("Decoding error: \(error.localizedDescription)")
                    continuation.resume(throwing: QCPNetworkError.decodingError(error))
                }
            }.resume()
        }
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Response Types
private struct ResponseData: Codable {
    let message: String
    let status: String?
    let value: ResponseValue?
    
    struct ResponseValue: Codable {
        let message: String
        let threadId: String?
    }
    
    var resolvedMessage: String {
        if let value = value {
            return value.message
        }
        return message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode the new format first
        if let status = try? container.decode(String.self, forKey: .status),
           let value = try? container.decode(ResponseValue.self, forKey: .value) {
            self.status = status
            self.value = value
            self.message = value.message
        } else {
            // Fall back to old format
            self.message = try container.decode(String.self, forKey: .message)
            self.status = nil
            self.value = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        if let status = status, let value = value {
            try container.encode(status, forKey: .status)
            try container.encode(value, forKey: .value)
        } else {
            try container.encode(message, forKey: .message)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case message, status, value
    }
}
