//
//  QCPFileSystemService.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation

@globalActor public actor QCPFileSystemService {
    // Make everything public that needs to be accessed
    public enum FSEvent {
        case created(URL)
        case modified(URL)
        case deleted(URL)
    }
    
    public struct FileInfo: Codable, Hashable {
        public let path: String
        public let name: String
        public let modificationDate: Date
        public let size: Int
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(path)
        }
        
        public static func == (lhs: FileInfo, rhs: FileInfo) -> Bool {
            lhs.path == rhs.path
        }
    }
    
    public enum FileSystemError: LocalizedError {
        case invalidPath
        case accessDenied
        case fileNotFound
        case readError
        
        public var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "The specified path is invalid or does not exist"
            case .accessDenied:
                return "Access to the specified path is denied"
            case .fileNotFound:
                return "The specified file could not be found"
            case .readError:
                return "Failed to read the file contents"
            }
        }
    }
    
    private let fileManager = FileManager.default
    private let watchedPath: String
    private var directoryObserver: DirectoryObserver?
    
    public static let shared = QCPFileSystemService(watchedPath: FileManager.default.temporaryDirectory.path)
    
    private init(watchedPath: String) {
        self.watchedPath = watchedPath
    }
    
    public func initialize() async throws {
        try await validatePath()
        await setupDirectoryObserver()
    }
    
    private func validatePath() async throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: watchedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileSystemError.invalidPath
        }
    }
    
    private func setupDirectoryObserver() {
        directoryObserver = DirectoryObserver(url: URL(fileURLWithPath: watchedPath))
        directoryObserver?.onEvent = { [weak self] event in
            guard let self else { return }
            Task {
                await self.handleFileSystemEvent(event)
            }
        }
    }
    
    private func handleFileSystemEvent(_ event: DirectoryObserver.FSEvent) async {
        switch event {
        case .created(let url):
            print("File created: \(url.path)")
        case .modified(let url):
            print("File modified: \(url.path)")
        case .deleted(let url):
            print("File deleted: \(url.path)")
        }
    }
}

// MARK: - Directory Observer
private class DirectoryObserver {
    enum FSEvent {
        case created(URL)
        case modified(URL)
        case deleted(URL)
    }
    
    var onEvent: ((FSEvent) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    
    init(url: URL) {
        self.url = url
        setupObserver()
    }
    
    private func setupObserver() {
        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        
        source?.setEventHandler { [weak self] in
            guard let self = self,
                  let source = self.source else { return }
            
            let flags = source.data
            
            if flags.contains(.write) {
                self.onEvent?(.modified(self.url))
            }
            if flags.contains(.delete) {
                self.onEvent?(.deleted(self.url))
            }
            if flags.contains(.rename) {
                self.onEvent?(.deleted(self.url))
                self.onEvent?(.created(self.url))
            }
        }
        
        source?.setCancelHandler {
            close(fileDescriptor)
        }
        
        source?.resume()
    }
    
    deinit {
        source?.cancel()
    }
}
