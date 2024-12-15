//
//  File.swift
//  QCP
//
//  Created by Quikolas on 12/15/24.
//

import Foundation

// MARK: - Text Editor Tool
public struct QCPTextEditorTool: QCPTool {
    public let name = "text.editor"
    public let description = "File content manipulation tool"
    
    public let inputSchema: [String: QCPToolProperty] = [
        "command": .init(
            type: "string",
            description: "Editor command (view/create/str_replace/insert/undo_edit)",
            required: true,
            enumValues: ["view", "create", "str_replace", "insert", "undo_edit"]
        ),
        "file_path": .init(
            type: "string",
            description: "Path to target file",
            required: true
        ),
        "view_range": .init(
            type: "string",
            description: "Line range to view (e.g. '1-10')",
            required: false
        ),
        "file_text": .init(
            type: "string",
            description: "Content for create/insert operations",
            required: false
        ),
        "new_str": .init(
            type: "string",
            description: "Replacement text for str_replace",
            required: false
        ),
        "insert_line": .init(
            type: "string",
            description: "Line number for insertion",
            required: false
        )
    ]
    
    private let fileService: QCPFileSystemService
    
    public init(fileService: QCPFileSystemService) {
        self.fileService = fileService
    }
    
    public func execute(with input: [String: String]) async throws -> QCPToolResult {
        guard let command = input["command"],
              let filePath = input["file_path"] else {
            throw QCPToolError.invalidInput("Missing required parameters")
        }
        
        let editor = TextEditor(
            type: "text_editor_20241022",
            name: "str_replace_editor",
            command: command
        )
        
        // Build editor parameters based on command
        var parameters: [String: String] = ["file_path": filePath]
        
        switch command {
        case "view":
            if let viewRange = input["view_range"] {
                parameters["view_range"] = viewRange
            }
            
        case "create":
            guard let fileText = input["file_text"] else {
                throw QCPToolError.invalidInput("file_text required for create command")
            }
            parameters["file_text"] = fileText
            
        case "str_replace":
            guard let newStr = input["new_str"] else {
                throw QCPToolError.invalidInput("new_str required for str_replace command")
            }
            parameters["new_str"] = newStr
            
        case "insert":
            guard let insertLine = input["insert_line"],
                  let fileText = input["file_text"] else {
                throw QCPToolError.invalidInput("insert_line and file_text required for insert command")
            }
            parameters["insert_line"] = insertLine
            parameters["file_text"] = fileText
            
        case "undo_edit":
            break // No additional parameters needed
            
        default:
            throw QCPToolError.invalidInput("Unknown command: \(command)")
        }
        
        // Execute editor operation
        return try await performEditorOperation(editor, parameters: parameters)
    }
    
    private func performEditorOperation(_ editor: TextEditor, parameters: [String: String]) async throws -> QCPToolResult {
        let result = await editor.execute(parameters)
        
        guard let content = result.content else {
            throw QCPToolError.executionFailed("Editor operation failed")
        }
        
        return QCPToolResult(
            success: true,
            content: content,
            metadata: result.metadata
        )
    }
}

// MARK: - FileSystemService Extension
extension QCPFileSystemService {
    private var editor: QCPTextEditorTool {
        QCPTextEditorTool(fileService: self)
    }
    
    public func readFileContent(at path: String, range: ClosedRange<Int>? = nil) async throws -> String {
        var input = [
            "command": "view",
            "file_path": path
        ]
        
        if let range = range {
            input["view_range"] = "\(range.lowerBound)-\(range.upperBound)"
        }
        
        let result = try await editor.execute(with: input)
        return result.content
    }
    
    public func writeFile(at path: String, content: String) async throws {
        let input = [
            "command": "create",
            "file_path": path,
            "file_text": content
        ]
        
        _ = try await editor.execute(with: input)
    }
    
    public func replaceInFile(at path: String, with newContent: String) async throws {
        let input = [
            "command": "str_replace",
            "file_path": path,
            "new_str": newContent
        ]
        
        _ = try await editor.execute(with: input)
    }
    
    public func insertInFile(at path: String, after line: Int, content: String) async throws {
        let input = [
            "command": "insert",
            "file_path": path,
            "insert_line": String(line),
            "file_text": content
        ]
        
        _ = try await editor.execute(with: input)
    }
    
    public func undoLastEdit(at path: String) async throws {
        let input = [
            "command": "undo_edit",
            "file_path": path
        ]
        
        _ = try await editor.execute(with: input)
    }
}

// MARK: - Text Editor Model
private struct TextEditor {
    let type: String
    let name: String
    let command: String
    
    func execute(_ parameters: [String: String]) async -> EditorResult {
        // This would interface with the actual Anthropic editor
        // For now, return dummy result
        return EditorResult(content: "Operation completed", metadata: parameters)
    }
}

private struct EditorResult {
    let content: String?
    let metadata: [String: String]?
}
