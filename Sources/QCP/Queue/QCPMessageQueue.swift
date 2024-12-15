//
//  QCPMessageQueue.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation
import Combine
import OSLog

/// Main message queue component
@MainActor
public class QCPMessageQueue: ObservableObject {
    private let messageSubject = PassthroughSubject<QCPAPIMessage, Never>()
    private let batchProcessor: QCPBatchProcessor
    private let flowController: QCPFlowController
    private let toolManager: QCPToolManager
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "MessageQueue")
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published public private(set) var processingState: QCPAPIState = .unknown
    @Published public private(set) var activeMessages: [UUID: QCPAPIMessage] = [:]
    
    public var messagePublisher: AnyPublisher<QCPAPIMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    public init(
        toolManager: QCPToolManager = .shared,
        throttleInterval: TimeInterval = 0.5
    ) {
        self.toolManager = toolManager
        self.batchProcessor = QCPBatchProcessor()
        self.flowController = QCPFlowController()
        setupMessageProcessing(throttleInterval)
    }
    
    public func enqueue(_ message: QCPAPIMessage) {
        logger.debug("Enqueuing message: \(message.id)")
        activeMessages[message.id] = message
        messageSubject.send(message)
    }
    
    private func setupMessageProcessing(_ interval: TimeInterval) {
        messagePublisher
            .flatMap { [weak self] message -> AnyPublisher<QCPAPIMessage, Never> in
                guard let self = self else { return Empty().eraseToAnyPublisher() }
                return self.flowController.shouldProcess(message) ?
                    Just(message).eraseToAnyPublisher() :
                    self.flowController.enqueueForLater(message)
            }
            .collect(.byTime(RunLoop.main, RunLoop.SchedulerTimeType.Stride(interval)))
            .filter { !$0.isEmpty }
            .sink { [weak self] messages in
                guard let self = self else { return }
                
                Task { @MainActor in
                    await self.handleMessages(messages)
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleMessages(_ messages: [QCPAPIMessage]) async {
        do {
            try await processBatch(messages)
        } catch {
            logger.error("Batch processing error: \(error.localizedDescription)")
            processingState = .error
        }
    }
    
    private func processBatch(_ messages: [QCPAPIMessage]) async throws {
        let batches = await batchProcessor.createBatches(messages)
        
        for batch in batches {
            processingState = .processing
            try await processSingleBatch(batch)
        }
        
        processingState = .success
    }
    
    private func processSingleBatch(_ batch: QCPMessageBatch) async throws {
        logger.debug("Processing batch with \(batch.messages.count) messages")
        
        // Process any tool uses first
        if !batch.toolUses.isEmpty {
            let toolResults = await toolManager.processToolUses(batch.toolUses.first!.content)
            await handleToolResults(toolResults, for: batch)
        }
        
        // Process regular messages
        for message in batch.messages {
            activeMessages[message.id] = message
            messageSubject.send(message)
        }
    }
    
    private func handleToolResults(_ results: [QCPToolResult], for batch: QCPMessageBatch) async {
        for result in results {
            // Create response message from tool result
            let responseMessage = QCPAPIMessage(
                content: result.content,
                agentId: batch.messages.first?.agentId ?? "",
                role: .assistant,
                metadata: result.metadata
            )
            
            // Update processing state based on tool result
            processingState = result.state
            
            // Enqueue the response
            enqueue(responseMessage)
        }
    }
}

/// Message batch structure
public struct QCPMessageBatch: Sendable {
    public let messages: [QCPAPIMessage]
    public let toolUses: [QCPAPIMessage]
    public let priority: Int
    
    public init(
        messages: [QCPAPIMessage],
        toolUses: [QCPAPIMessage] = [],
        priority: Int = 0
    ) {
        self.messages = messages
        self.toolUses = toolUses
        self.priority = priority
    }
}

/// Processes messages into optimized batches
public actor QCPBatchProcessor {
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "BatchProcessor")
    
    public func createBatches(_ messages: [QCPAPIMessage]) -> [QCPMessageBatch] {
        // Separate tool uses from regular messages
        let (toolUses, regularMessages) = messages.partition { message in
            // Check if message contains tool use syntax
            return message.content.contains("\"tool\":")
        }
        
        // Group by agent and related operations
        let batchedMessages = Dictionary(grouping: regularMessages) { $0.agentId }
            .map { agentId, messages in
                QCPMessageBatch(
                    messages: messages,
                    priority: calculatePriority(agentId: agentId, messages: messages)
                )
            }
        
        // Create tool use batches
        let toolBatches = toolUses.map { toolUse in
            QCPMessageBatch(
                messages: [toolUse],
                toolUses: [toolUse],
                priority: 2  // Tool uses get higher priority
            )
        }
        
        return (toolBatches + batchedMessages).sorted { $0.priority > $1.priority }
    }
    
    private func calculatePriority(agentId: String, messages: [QCPAPIMessage]) -> Int {
        var priority = 1
        
        // Prioritize user messages
        if messages.contains(where: { $0.role == .user }) {
            priority += 1
        }
        
        return priority
    }
}

/// Controls message flow and backpressure
public class QCPFlowController {
    private let maxConcurrent: Int
    private let retrySubject = PassthroughSubject<QCPAPIMessage, Never>()
    private var activeRequests: Int = 0
    private var backpressureQueue: [QCPAPIMessage] = []
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "FlowController")
    
    public init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }
    
    public func shouldProcess(_ message: QCPAPIMessage) -> Bool {
        guard activeRequests < maxConcurrent else { return false }
        activeRequests += 1
        return true
    }
    
    public func enqueueForLater(_ message: QCPAPIMessage) -> AnyPublisher<QCPAPIMessage, Never> {
        logger.debug("Enqueuing message for later: \(message.id)")
        backpressureQueue.append(message)
        return Empty().eraseToAnyPublisher()
    }
    
    public func requestComplete() {
        activeRequests -= 1
        processBackpressureQueue()
    }
    
    private func processBackpressureQueue() {
        while !backpressureQueue.isEmpty && activeRequests < maxConcurrent {
            let message = backpressureQueue.removeFirst()
            retrySubject.send(message)
        }
    }
}

/// Helper extension for array partitioning
extension Array {
    func partition(by predicate: (Element) -> Bool) -> ([Element], [Element]) {
        var matches: [Element] = []
        var nonMatches: [Element] = []
        
        forEach { element in
            if predicate(element) {
                matches.append(element)
            } else {
                nonMatches.append(element)
            }
        }
        
        return (matches, nonMatches)
    }
}

/// Message queue errors
public enum QCPMessageQueueError: Error, LocalizedError {
    case processingFailed(String)
    case invalidBatch
    case toolExecutionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .processingFailed(let reason):
            return "Message processing failed: \(reason)"
        case .invalidBatch:
            return "Invalid message batch"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
