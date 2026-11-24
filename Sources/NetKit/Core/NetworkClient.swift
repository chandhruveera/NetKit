//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 24/11/26.
//

import Foundation

public protocol NetworkClient: Sendable {
    func send<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type
    ) async throws -> T
}
