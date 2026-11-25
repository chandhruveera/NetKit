//
//  RelaxedPolicyTests.swift
//  NetKit
//
//  R1: policies made from `.relaxed` must not work in Release builds.
//  Release path is tested via apply(to:isDebugBuild: false); the real build flag is checked by
//  test_client_relaxed_followsBuildConfiguration (run with: swift test -c release -Xswiftc -enable-testing).
//

import XCTest
@testable import NetKit

final class RelaxedPolicyTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private let request = URLRequest(url: URL(string: "http://staging.local/x")!)

    private func assertInsecure(_ policy: SecurityPolicy, isDebugBuild: Bool,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await policy.apply(to: request, isDebugBuild: isDebugBuild)
            XCTFail("should be blocked", file: file, line: line)
        } catch NetworkError.security(.insecureConnection) {
        } catch {
            XCTFail("wrong error \(error)", file: file, line: line)
        }
    }

    func test_relaxed_inRelease_isBlocked() async {
        await assertInsecure(.relaxed, isDebugBuild: false)
    }

    func test_relaxed_blocksHTTPSToo_inRelease() async {
        let https = URLRequest(url: URL(string: "https://api.shop.com/x")!)
        do {
            _ = try await SecurityPolicy.relaxed.apply(to: https, isDebugBuild: false)
            XCTFail("should be blocked")
        } catch NetworkError.security(.insecureConnection) {
        } catch { XCTFail("wrong error \(error)") }
    }

    func test_modifiedRelaxedCopy_isStillBlocked_inRelease() async {
        var p = SecurityPolicy.relaxed
        p.allowedHosts = ["staging.local"]
        p.requestTimeout = 5
        await assertInsecure(p, isDebugBuild: false)
    }

    func test_relaxed_inDebug_allowsHTTP() async throws {
        let r = try await SecurityPolicy.relaxed.apply(to: request, isDebugBuild: true)
        XCTAssertEqual(r.url?.scheme, "http")
    }

    func test_explicitCustomHTTPPolicy_worksInRelease() async throws {
        var p = SecurityPolicy.standard
        p.requireHTTPS = false
        let r = try await p.apply(to: request, isDebugBuild: false)
        XCTAssertEqual(r.url?.scheme, "http", "explicit opt-in (LAN / IoT) still allowed")
    }

    func test_otherPresets_unaffectedInRelease() async throws {
        let https = URLRequest(url: URL(string: "https://test.com/x")!)
        _ = try await SecurityPolicy.standard.apply(to: https, isDebugBuild: false)
        _ = try await SecurityPolicy.strict(allowedHosts: ["test.com"]).apply(to: https, isDebugBuild: false)
    }

    /// Real build flag, end to end through the client.
    func test_client_relaxed_followsBuildConfiguration() async {
        MockURLProtocol.handler = { r in (mockResponse(r, 200), Data(#"{"id":1}"#.utf8)) }
        let client = makeMockClient(security: .relaxed)
        do {
            let item: TestItem = try await client.send(Endpoint(path: "x"), as: TestItem.self)
            #if DEBUG
            XCTAssertEqual(item.id, 1)
            #else
            XCTFail("relaxed must be blocked in release, got \(item)")
            #endif
        } catch {
            #if DEBUG
            XCTFail("relaxed should work in DEBUG: \(error)")
            #else
            guard case NetworkError.security(.insecureConnection) = error else { return XCTFail("wrong error \(error)") }
            #endif
        }
    }
}
