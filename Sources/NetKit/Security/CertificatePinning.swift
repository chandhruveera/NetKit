//
//  File.swift
//  NetKit
//
//  Created by Chandhru on 25/11/26.
//

import Foundation
import CryptoKit
import Security

/// host -> base64(SHA256(SPKI)) pins
public struct CertificatePinning: Sendable {
    private let pinsByHost: [String: Set<String>]

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

