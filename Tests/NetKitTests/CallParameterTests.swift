//
//  CallParameterTests.swift
//  NetKit
//
//  How call(parameter:) values become query items (GET/DELETE) or a JSON body (POST/PUT/PATCH).
//

import XCTest
@testable import NetKit

final class CallParameterTests: XCTestCase {

    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        private var body: Data?
        func set(_ r: URLRequest) {
            lock.lock()
            request = r
            // URLProtocol receives the body as a stream
            if let stream = r.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                body = data
            } else { body = r.httpBody }
            lock.unlock()
        }
        var query: String? { lock.lock(); defer { lock.unlock() }; return request?.url?.query }
        var bodyText: String? { lock.lock(); defer { lock.unlock() }; return body.flatMap { String(data: $0, encoding: .utf8) } }
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func call(_ parameter: [String: Any], method: HTTPMethod = .get) async throws -> Captured {
        let captured = Captured()
        MockURLProtocol.handler = { request in captured.set(request); return (mockResponse(request, 200), Data()) }
        let _: EmptyResponse = try await makeMockClient().call("items", method: method, parameter: parameter)
        return captured
    }

    // MARK: - Optionals in query

    func test_optionalWithValue_isUnwrapped() async throws {
        let page: Int? = 2
        let captured = try await call(["page": page as Any])
        XCTAssertEqual(captured.query, "page=2")
    }

    func test_nilOptional_isOmitted() async throws {
        let q: String? = nil
        let captured = try await call(["page": 1, "q": q as Any])
        XCTAssertEqual(captured.query, "page=1")
    }

    func test_nestedOptional_isUnwrapped() async throws {
        let inner: Int? = 5
        let outer: Int?? = inner
        let captured = try await call(["n": outer as Any])
        XCTAssertEqual(captured.query, "n=5")
    }

    func test_nsNull_isOmitted() async throws {
        let captured = try await call(["a": NSNull(), "b": "x"])
        XCTAssertEqual(captured.query, "b=x")
    }

    func test_allNil_sendsNoQuery() async throws {
        let q: String? = nil
        let captured = try await call(["q": q as Any])
        XCTAssertNil(captured.query)
    }

    // MARK: - Arrays in query

    func test_array_repeatsKey() async throws {
        let captured = try await call(["ids": [1, 2, 3]])
        XCTAssertEqual(captured.query, "ids=1&ids=2&ids=3")
    }

    func test_array_dropsNilElements() async throws {
        let ids: [Int?] = [1, nil, 3]
        let captured = try await call(["ids": ids])
        XCTAssertEqual(captured.query, "ids=1&ids=3")
    }

    func test_emptyArray_isOmitted() async throws {
        let captured = try await call(["ids": [Int](), "page": 1])
        XCTAssertEqual(captured.query, "page=1")
    }

    func test_arrayOfStrings_isEncoded() async throws {
        let captured = try await call(["tag": ["a b", "c+d"]])
        XCTAssertEqual(captured.query, "tag=a%20b&tag=c%2Bd")
    }

    // MARK: - Scalars

    func test_scalars() async throws {
        let captured = try await call(["b": true, "f": false, "i": 7, "s": "x"])
        XCTAssertEqual(captured.query, "b=true&f=false&i=7&s=x")
    }

    func test_delete_usesQueryToo() async throws {
        let id: Int? = 9
        let captured = try await call(["id": id as Any], method: .delete)
        XCTAssertEqual(captured.query, "id=9")
    }

    // MARK: - JSON body keeps explicit nulls

    func test_postBody_optionals() async throws {
        let some: Int? = 2
        let none: Int? = nil
        let captured = try await call(["a": some as Any, "b": none as Any], method: .post)
        XCTAssertNil(captured.query)
        XCTAssertEqual(captured.bodyText, #"{"a":2,"b":null}"#)
    }
}
