//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public enum NetworkError: Error, Sendable {
    case invalidURL
    case noConnection
    case timeout
    case unauthorized(Data)
    case httpError(statusCode: Int, data: Data)
    case decoding(Error)
    case cancelled
    case unknown(Error)
}
