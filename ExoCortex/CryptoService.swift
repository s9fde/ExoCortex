import Foundation
import CryptoKit
import CommonCrypto

enum CryptoServiceError: Error {
    case derivationFailed
    case invalidEnvelope
    case unsupportedVersion
    case encryptionFailed
    case decryptionFailed
}

actor CryptoService {
    static let version: UInt8 = 1
    private static let saltLength = 16
    private static let keyLength = 32
    private static let pbkdfRounds: UInt32 = 150_000

    func encrypt(text: String, password: String) throws -> Data {
        guard let plain = text.data(using: .utf8) else { throw CryptoServiceError.encryptionFailed }
        let salt = try randomSalt()
        let keyData = try deriveKey(password: password, salt: salt)
        let symmetricKey = SymmetricKey(data: keyData)

        let sealedBox = try ChaChaPoly.seal(plain, using: symmetricKey)
        let combined = sealedBox.combined

        var envelope = Data()
        envelope.append(Self.version)
        envelope.append(salt)
        envelope.append(combined)
        return envelope
    }

    func decrypt(data: Data, password: String) throws -> String {
        var cursor = data.startIndex
        guard data.count > 1 + Self.saltLength else { throw CryptoServiceError.invalidEnvelope }

        let version = data[cursor]
        guard version == Self.version else { throw CryptoServiceError.unsupportedVersion }
        cursor = data.index(after: cursor)

        let saltRange = cursor..<(cursor + Self.saltLength)
        let salt = Data(data[saltRange])
        let ciphertext = Data(data[data.index(cursor, offsetBy: Self.saltLength)..<data.endIndex])

        let keyData = try deriveKey(password: password, salt: salt)
        let symmetricKey = SymmetricKey(data: keyData)

        let sealedBox = try ChaChaPoly.SealedBox(combined: ciphertext)
        let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey)
        guard let string = String(data: plaintext, encoding: .utf8) else { throw CryptoServiceError.decryptionFailed }
        return string
    }

    private func deriveKey(password: String, salt: Data) throws -> Data {
        var derivedData = Data(count: Self.keyLength)
        let status = derivedData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     password, password.utf8.count,
                                     saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                     Self.pbkdfRounds,
                                     derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Self.keyLength)
            }
        }
        guard status == kCCSuccess else { throw CryptoServiceError.derivationFailed }
        return derivedData
    }

    private func randomSalt() throws -> Data {
        var data = Data(count: Self.saltLength)
        let result = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, Self.saltLength, bytes.baseAddress!)
        }
        guard result == errSecSuccess else { throw CryptoServiceError.derivationFailed }
        return data
    }
}
