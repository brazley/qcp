//
//  QCPMessageRole.swift
//  QCP
//
//  Created by Quikolas on 12/9/24.
//

import Foundation

public enum QCPMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case agent
    case system
}
