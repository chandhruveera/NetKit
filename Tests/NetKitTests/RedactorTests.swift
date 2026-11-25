//
//  RedactorTests.swift
//  NetKit
//

import XCTest
@testable import NetKit

final class RedactorTests: XCTestCase {

    // MARK: - Log redaction (loose)

    func test_sensitiveKeyVariants_areMasked() {
        for key in ["password", "newPassword", "password_confirmation", "accessToken", "refresh-token",
                    "ID_TOKEN", "clientSecret", "apiKey", "x-api-key", "Authorization", "authCode",
                    "sessionId", "cookie", "privateKey", "cardNumber", "pin", "OTP", "cvv", "pwd", "jwt", "ssn"] {
            XCTAssertTrue(Redactor.isSensitive(key), key)
        }
    }

    func test_ordinaryKeys_areNotMasked() {
        for key in ["user", "email", "shipping", "spinner", "hotpot", "page", "id", "amount", "keyboard"] {
            XCTAssertFalse(Redactor.isSensitive(key), key)
        }
    }

    func test_redactedBody_masksCamelCaseAndNested() {
        let data = Data(#"{"user":"a","accessToken":"T1","profile":{"newPassword":"P1"},"items":[{"refresh_token":"T2"}]}"#.utf8)
        let text = Redactor.redactedBody(data)
        for secret in ["T1", "P1", "T2"] { XCTAssertFalse(text.contains(secret), secret) }
        XCTAssertTrue(text.contains(#""user":"a""#))
    }

    func test_sensitiveHeaders_includeCustomTokenHeaders() {
        for name in ["Authorization", "Cookie", "X-Api-Key", "X-Auth-Token", "X-Access-Token", "Api-Key", "X-App-Attestation"] {
            XCTAssertTrue(Redactor.isSensitiveHeader(name), name)
        }
        for name in ["Content-Type", "Accept", "Idempotency-Key", "User-Agent"] {
            XCTAssertFalse(Redactor.isSensitiveHeader(name), name)
        }
    }
}
