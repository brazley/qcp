//
//  QCPStorage.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation
import SwiftData
import OSLog

@globalActor public actor QCPStorageActor {
    public static let shared = QCPStorageActor()
}

/// Protocol defining storage operations for QCP data
@QCPStorageActor
public protocol QCPStorageProvider {
    /// Save a chat with its messages
    func saveChat(_ chat: QCPChat) async throws
    
    /// Save a message to an existing chat
    func saveMessage(_ message: QCPMessage, to chatId: UUID) async throws
    
    /// Fetch a chat by ID
    func fetchChat(_ id: UUID) async throws -> QCPChat?
    
    /// Fetch all chats
    func fetchAllChats() async throws -> [QCPChat]
    
    /// Delete a chat and its messages
    func deleteChat(_ id: UUID) async throws
    
    /// Delete a specific message
    func deleteMessage(_ id: UUID) async throws
}

/// Core storage models for QCP data
@Model
public class QCPChat {
    public var id: UUID
    public var title: String?
    @Relationship(deleteRule: .cascade) public var messages: [QCPMessage]
    public var createdAt: Date
    public var lastModified: Date
    
    public init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [QCPMessage] = [],
        createdAt: Date = Date(),
        lastModified: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.lastModified = lastModified
    }
}

@Model
public final class QCPMessage {
    public var id: UUID
    public var content: String
    public var agentId: String
    public var role: QCPMessageRole
    public var isInternal: Bool
    public var timestamp: Date
    public var metadata: [String: String]?
    @Relationship(inverse: \QCPChat.messages) public var chat: QCPChat?
    
    public init(
        id: UUID = UUID(),
        content: String,
        agentId: String,
        role: QCPMessageRole,
        isInternal: Bool = false,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil,
        chat: QCPChat? = nil
    ) {
        self.id = id
        self.content = content
        self.agentId = agentId
        self.role = role
        self.isInternal = isInternal
        self.timestamp = timestamp
        self.metadata = metadata
        self.chat = chat
    }
}

/// Default SwiftData implementation of QCPStorageProvider
@QCPStorageActor
public final class QCPSwiftDataStorage: QCPStorageProvider {
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "Storage")
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    public init() throws {
        let schema = Schema([
            QCPChat.self,
            QCPMessage.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        self.modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
        self.modelContext = ModelContext(modelContainer)
        
        logger.debug("Initialized SwiftData storage")
    }
    
    public func saveChat(_ chat: QCPChat) async throws {
        logger.debug("Saving chat: \(chat.id)")
        modelContext.insert(chat)
        try modelContext.save()
    }
    
    public func saveMessage(_ message: QCPMessage, to chatId: UUID) async throws {
        logger.debug("Saving message to chat: \(chatId)")
        
        let descriptor = FetchDescriptor<QCPChat>(
            predicate: #Predicate<QCPChat> { chat in
                chat.id == chatId
            }
        )
        
        guard let chat = try modelContext.fetch(descriptor).first else {
            throw QCPStorageError.chatNotFound(chatId)
        }
        
        message.chat = chat
        chat.messages.append(message)
        modelContext.insert(message)
        
        try modelContext.save()
    }
    
    public func fetchChat(_ id: UUID) async throws -> QCPChat? {
        logger.debug("Fetching chat: \(id)")
        
        let descriptor = FetchDescriptor<QCPChat>(
            predicate: #Predicate<QCPChat> { chat in
                chat.id == id
            }
        )
        
        return try modelContext.fetch(descriptor).first
    }
    
    public func fetchAllChats() async throws -> [QCPChat] {
        logger.debug("Fetching all chats")
        let descriptor = FetchDescriptor<QCPChat>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    public func deleteChat(_ id: UUID) async throws {
        logger.debug("Deleting chat: \(id)")
        
        guard let chat = try await fetchChat(id) else {
            throw QCPStorageError.chatNotFound(id)
        }
        
        modelContext.delete(chat)
        try modelContext.save()
    }
    
    public func deleteMessage(_ id: UUID) async throws {
        logger.debug("Deleting message: \(id)")
        
        let descriptor = FetchDescriptor<QCPMessage>(
            predicate: #Predicate<QCPMessage> { message in
                message.id == id
            }
        )
        
        guard let message = try modelContext.fetch(descriptor).first else {
            throw QCPStorageError.messageNotFound(id)
        }
        
        modelContext.delete(message)
        try modelContext.save()
    }
}

/// Storage manager for coordinating storage operations
@QCPStorageActor
public final class QCPStorageManager: @unchecked Sendable {
    private let storage: QCPStorageProvider
    private let logger = Logger(subsystem: "com.bristolavenue.qcp", category: "StorageManager")
    
    public static let shared = QCPStorageManager(storage: try! QCPSwiftDataStorage())
    
    public init(storage: QCPStorageProvider) {
        self.storage = storage
        logger.debug("Initialized storage manager")
    }
    
    public func createChat(title: String? = nil) async throws -> QCPChat {
        let chat = QCPChat(title: title)
        try await storage.saveChat(chat)
        return chat
    }
    
    public func addMessage(
        content: String,
        agentId: String,
        role: QCPMessageRole, // Changed from QCPAgentMessage.MessageRole
        to chatId: UUID,
        metadata: [String: String]? = nil
    ) async throws {
        let message = QCPMessage(
            content: content,
            agentId: agentId,
            role: role,
            metadata: metadata
        )
        try await storage.saveMessage(message, to: chatId)
    }
    
    public func getChat(_ id: UUID) async throws -> QCPChat? {
        try await storage.fetchChat(id)
    }
    
    public func getAllChats() async throws -> [QCPChat] {
        try await storage.fetchAllChats()
    }
}

/// Storage-related errors
public enum QCPStorageError: Error, LocalizedError {
    case initializationFailed(Error)
    case chatNotFound(UUID)
    case messageNotFound(UUID)
    case saveFailed(Error)
    case deleteFailed(Error)
    case fetchFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let error):
            return "Storage initialization failed: \(error.localizedDescription)"
        case .chatNotFound(let id):
            return "Chat not found: \(id)"
        case .messageNotFound(let id):
            return "Message not found: \(id)"
        case .saveFailed(let error):
            return "Save operation failed: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Delete operation failed: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Fetch operation failed: \(error.localizedDescription)"
        }
    }
}
