//
//  ResponseAndErrorTests.swift
//  NetKit
//

import XCTest
@testable import NetKit

final class ResponseAndErrorTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func respond(_ status: Int, _ body: String) {
        MockURLProtocol.handler = { request in (mockResponse(request, status), Data(body.utf8)) }
    }

    private func error(_ status: Int, _ body: String) -> NetworkError {
        status == 401
            ? .unauthorized(Data(body.utf8))
            : .httpError(statusCode: status, data: Data(body.utf8))
    }

    // MARK: - Empty responses

    func test_200_emptyBody_returnsEmptyResponse() async throws {
        respond(200, "")
        let _: EmptyResponse = try await makeMockClient().send(Endpoint(path: "logout", method: .post), as: EmptyResponse.self)
    }

    func test_200_emptyJSONObject_decodesEmptyResponse() async throws {
        respond(200, "{}")
        let _: EmptyResponse = try await makeMockClient().send(Endpoint(path: "x"), as: EmptyResponse.self)
    }

    func test_204_withNonEmptyType_throwsDecoding() async {
        respond(204, "")
        do {
            _ = try await makeMockClient().send(Endpoint(path: "x"), as: TestItem.self)
            XCTFail("Should have thrown")
        } catch NetworkError.decoding {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_401_withEmptyBody_hasNoServerMessage() async {
        respond(401, "")
        do {
            _ = try await makeMockClient().send(Endpoint(path: "x"), as: TestItem.self)
            XCTFail("Should have thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertNil(error.serverMessage)
            XCTAssertEqual(error.responseData, Data())
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - serverMessage parsing

    func test_serverMessage_knownKeys() {
        XCTAssertEqual(error(400, #"{"error": "Bad input"}"#).serverMessage, "Bad input")
        XCTAssertEqual(error(400, #"{"error_description": "Expired"}"#).serverMessage, "Expired")
        XCTAssertEqual(error(400, #"{"detail": "Not found"}"#).serverMessage, "Not found")
        XCTAssertEqual(error(400, #"{"msg": "Nope"}"#).serverMessage, "Nope")
        XCTAssertEqual(error(400, #"{"errorMessage": "Oops"}"#).serverMessage, "Oops")
    }

    func test_serverMessage_keyPriority_messageWins() {
        XCTAssertEqual(error(400, #"{"error": "generic", "message": "specific"}"#).serverMessage, "specific")
    }

    func test_serverMessage_nested() {
        XCTAssertEqual(error(400, #"{"error": {"code": 7, "message": "Card declined"}}"#).serverMessage, "Card declined")
    }

    func test_serverMessage_errorsArray_joined() {
        let e = error(422, #"{"errors": ["Name required", {"message": "Email invalid"}]}"#)
        XCTAssertEqual(e.serverMessage, "Name required\nEmail invalid")
    }

    func test_serverMessage_topLevelStringArray() {
        XCTAssertEqual(error(400, #"["First", "Second"]"#).serverMessage, "First")
    }

    func test_serverMessage_emptyStringIsSkipped() {
        XCTAssertEqual(error(400, #"{"message": "", "error": "Fallback"}"#).serverMessage, "Fallback")
    }

    func test_serverMessage_plainText() {
        XCTAssertEqual(error(503, "  Service down  \n").serverMessage, "Service down")
    }

    func test_serverMessage_htmlIsIgnored() {
        XCTAssertNil(error(502, "<html><body>Bad Gateway</body></html>").serverMessage)
    }

    func test_serverMessage_longTextIsIgnored() {
        XCTAssertNil(error(500, String(repeating: "a", count: 250)).serverMessage)
    }

    func test_serverMessage_jsonWithoutKnownKey_isNil() {
        XCTAssertNil(error(400, #"{"code": 42}"#).serverMessage)
    }

    func test_serverMessage_nonHTTPError_isNil() {
        XCTAssertNil(NetworkError.timeout.serverMessage)
        XCTAssertNil(NetworkError.timeout.statusCode)
    }

    func test_decodeBody_customErrorType() {
        struct APIError: Decodable { let code: Int }
        XCTAssertEqual(error(400, #"{"code": 42}"#).decodeBody(APIError.self)?.code, 42)
        XCTAssertNil(error(400, "not json").decodeBody(APIError.self))
    }

    // MARK: - localizedDescription fallbacks

    func test_localizedDescription_usesServerMessageFirst() {
        XCTAssertEqual(error(401, #"{"message": "Token expired"}"#).localizedDescription, "Token expired")
    }

    func test_localizedDescription_fallbacks() {
        XCTAssertEqual(NetworkError.invalidURL.localizedDescription, "Invalid request URL.")
        XCTAssertEqual(NetworkError.noConnection.localizedDescription, "No internet connection.")
        XCTAssertEqual(NetworkError.timeout.localizedDescription, "The request timed out.")
        XCTAssertEqual(NetworkError.unauthorized(Data()).localizedDescription, "Your session has expired. Please sign in again.")
        XCTAssertEqual(NetworkError.httpError(statusCode: 500, data: Data()).localizedDescription, "Server error (500).")
        XCTAssertEqual(NetworkError.cancelled.localizedDescription, "Request was cancelled.")
        XCTAssertEqual(NetworkError.security(.insecureConnection).localizedDescription, "Connection blocked for security reasons.")
        XCTAssertEqual(NetworkError.unknown(URLError(.badURL)).localizedDescription, "Something went wrong. Please try again.")
    }

    func test_localizedDescription_neverContainsURLOrToken() {
        let underlying = URLError(.cannotFindHost, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://x.com/a?token=SECRET"])
        XCTAssertFalse(NetworkError.unknown(underlying).localizedDescription.contains("SECRET"))
    }
}
