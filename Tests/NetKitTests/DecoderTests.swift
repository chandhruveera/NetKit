//
//  DecoderTests.swift
//  NetKit
//
//  The client decodes with its own copy of the decoder, without a lock.
//

import XCTest
@testable import NetKit

final class DecoderTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }


    private struct Snake: Decodable { let userId: Int }

    private func client(decoder: JSONDecoder) -> URLSessionNetworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSessionNetworkClient(baseURL: URL(string: "https://test.com"),
                                       sessionConfiguration: config, decoder: decoder)
    }

    func test_decoderSettingsAtInit_areUsed() async throws {
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data(#"{"user_id":7}"#.utf8)) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let value: Snake = try await client(decoder: d).send(Endpoint(path: "x"), as: Snake.self)
        XCTAssertEqual(value.userId, 7)
    }

    func test_changingDecoderAfterInit_hasNoEffect() async throws {
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data(#"{"user_id":7}"#.utf8)) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let c = client(decoder: d)
        d.keyDecodingStrategy = .useDefaultKeys      // app mutates its decoder later

        let value: Snake = try await c.send(Endpoint(path: "x"), as: Snake.self)
        XCTAssertEqual(value.userId, 7)
    }

    func test_allDecoderSettings_areCopied() {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        d.dataDecodingStrategy = .deferredToData
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        d.keyDecodingStrategy = .convertFromSnakeCase
        let key = CodingUserInfoKey(rawValue: "k")!
        d.userInfo = [key: "v"]
        d.allowsJSON5 = true
        d.assumesTopLevelDictionary = true

        let copy = URLSessionNetworkClient.privateCopy(of: d)

        XCTAssertFalse(copy === d)
        if case .secondsSince1970 = copy.dateDecodingStrategy {} else { XCTFail("date") }
        if case .deferredToData = copy.dataDecodingStrategy {} else { XCTFail("data") }
        if case .convertFromString(let p, _, _) = copy.nonConformingFloatDecodingStrategy { XCTAssertEqual(p, "inf") } else { XCTFail("float") }
        if case .convertFromSnakeCase = copy.keyDecodingStrategy {} else { XCTFail("keys") }
        XCTAssertEqual(copy.userInfo[key] as? String, "v")
        XCTAssertTrue(copy.allowsJSON5)
        XCTAssertTrue(copy.assumesTopLevelDictionary)
    }

    func test_decoderSubclass_isUsedAsIs() async throws {
        final class Counting: JSONDecoder, @unchecked Sendable {
            let calls = Counter()
            override func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
                calls.increment()
                return try super.decode(type, from: data)
            }
        }
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data(#"{"id":1}"#.utf8)) }
        let d = Counting()
        let _: TestItem = try await client(decoder: d).send(Endpoint(path: "x"), as: TestItem.self)
        XCTAssertEqual(d.calls.count, 1, "custom decode override must still run")
    }

    /// Each decode sleeps 0.3 s. With a lock around decoding, 5 parallel requests take >= 1.5 s.
    func test_decoding_isNotSerialized() async throws {
        struct Slow: Decodable {
            init(from decoder: Decoder) throws { Thread.sleep(forTimeInterval: 0.3) }
        }
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data("{}".utf8)) }
        let c = client(decoder: JSONDecoder())
        let start = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask { let _: Slow = try await c.send(Endpoint(path: "x\(i)"), as: Slow.self) }
            }
            try await group.waitForAll()
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.2)
    }
}
