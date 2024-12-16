//
//  QCPAPIState.swift
//  QCP
//
//  Created by Quikolas on 12/15/24.
//

import Foundation

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
