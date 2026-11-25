//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation
import CryptoKit
import Security

/// Public-key (SPKI) pins per host, used by ``SecurityPolicy/pinning``.
///
/// A connection to a pinned host succeeds only if normal TLS validation passes **and** at least
/// one certificate in the chain has a matching pin; otherwise it fails closed with
/// ``SecurityViolation/pinningFailed(_:)``. Supported keys: RSA 2048/4096, EC P-256/P-384.
///
/// Generate a pin with:
/// ```
/// openssl s_client -connect api.bank.com:443 -servername api.bank.com </dev/null \
///   | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary | base64
/// ```
public struct CertificatePinning: Sendable {
    private let pinsByHost: [String: Set<String>]

    /// - Parameter pins: Exact host name (case-insensitive) → base64 SHA-256 SPKI hashes.
    ///   Always include at least two per host (current + backup key) so a certificate
    ///   rotation doesn't lock users out. Fewer than two triggers an assertion in DEBUG builds.
    public init(_ pins: [String: Set<String>]) {
        for (host, values) in pins {
            assert(values.count >= 2,
                   "\(host): current + backup pin rendum podunga. Illa na certificate rotate aana users lock aagiduvanga")
        }
        self.pinsByHost = pins.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }

    func pins(for host: String) -> Set<String>? {
        pinsByHost[host.lowercased()]
    }

    // MARK: - SPKI hash

    static func spkiHash(of cert: SecCertificate) -> String? {
        guard let key = SecCertificateCopyKey(cert),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attrs[kSecAttrKeyType as String] as? String,
              let bits = attrs[kSecAttrKeySizeInBits as String] as? Int
        else { return nil }

        let isRSA = type == (kSecAttrKeyTypeRSA as String)
        let isEC = type == (kSecAttrKeyTypeECSECPrimeRandom as String)

        let header: Data
        if isRSA && bits == 2048 { header = rsa2048 }
        else if isRSA && bits == 4096 { header = rsa4096 }
        else if isEC && bits == 256 { header = ecP256 }
        else if isEC && bits == 384 { header = ecP384 }
        else { return nil }

        return Data(SHA256.hash(data: header + raw)).base64EncodedString()
    }

    private static let rsa2048 = Data([0x30,0x82,0x01,0x22,0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00,0x03,0x82,0x01,0x0f,0x00])
    private static let rsa4096 = Data([0x30,0x82,0x02,0x22,0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00,0x03,0x82,0x02,0x0f,0x00])
    private static let ecP256 = Data([0x30,0x59,0x30,0x13,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,0x06,0x08,0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07,0x03,0x42,0x00])
    private static let ecP384 = Data([0x30,0x76,0x30,0x10,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,0x06,0x05,0x2b,0x81,0x04,0x00,0x22,0x03,0x62,0x00])
}

