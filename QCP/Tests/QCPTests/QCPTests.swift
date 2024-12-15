//
//  QCPTests.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import XCTest
@testable import QCP

final class QCPTests: XCTestCase {
    var toolManager: QCPToolManager!
    
    override func setUpWithError() throws {
        // This runs before each test
        try super.setUpWithError()
        toolManager = .shared
    }
    
    override func tearDownWithError() throws {
        // This runs after each test
        toolManager = nil
        try super.tearDownWithError()
    }
    
    func testAPIStateIsWorking() {
        // Simple test to check our API states work as expected
        XCTAssertTrue(QCPAPIState.processing.isWorking)
        XCTAssertFalse(QCPAPIState.error.isWorking)
        XCTAssertFalse(QCPAPIState.success.isWorking)
        XCTAssertFalse(QCPAPIState.unknown.isWorking)
    }
    
    func testToolManagerRegistration() async throws {
        // 1. Create a test tool
        let testTool = TestTool()
        
        // 2. Register it with our tool manager
        await toolManager.register(testTool)
        
        // 3. Try to execute it
        let result = try await toolManager.executeTool("test.tool", with: ["test": "value"])
        
        // 4. Verify it worked
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.content, "test")
    }
}



// Helper test tool implementation
@QCPToolManager
final class TestTool: QCPTool, @unchecked Sendable {
    let name = "test.tool"
    let description = "Test tool"
    let inputSchema: [String: QCPToolProperty] = [
        "test": QCPToolProperty(
            type: "string",
            description: "Test input"
        )
    ]
    
    func execute(with input: [String: String]) async throws -> QCPToolResult {
        return QCPToolResult(
            success: true,
            content: "test",
            state: .success
        )
    }
}

//
