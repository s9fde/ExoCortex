//
//  CryptoService.swift
//  ExoCortex
//
//  Encryption service using ChaCha20-Poly1305 with PBKDF2 key derivation.
//

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Crypto Errors

/// Errors that can occur during cryptographic operations
enum CryptoServiceError: Error, LocalizedError {
    case derivationFailed
    case invalidEnvelope
    case unsupportedVersion
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .derivationFailed: return "Key derivation failed"
        case .invalidEnvelope: return "Invalid encrypted data format"
        case .unsupportedVersion: return "Unsupported encryption version"
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        }
    }
}

// MARK: - Crypto Service

/// Actor-based service for symmetric encryption using ChaCha20-Poly1305.
/// Uses PBKDF2 for password-based key derivation with 150,000 iterations.
actor CryptoService {
    
    // MARK: - Constants
    
    /// Envelope format version for future compatibility
    static let version: UInt8 = 1
    
    /// Salt length for PBKDF2 (128 bits)
    private static let saltLength = 16
    
    /// Derived key length (256 bits for ChaCha20)
    private static let keyLength = 32
    
    /// PBKDF2 iteration count (balance of security vs performance)
    private static let pbkdfRounds: UInt32 = 150_000

    // MARK: - Public Methods
    
    /// Encrypt text with password
    /// - Parameters:
    ///   - text: Plain text to encrypt
    ///   - password: Password for key derivation
    /// - Returns: Encrypted data envelope (version + salt + ciphertext)
    func encrypt(text: String, password: String) throws -> Data {
        guard let plain = text.data(using: .utf8) else {
            throw CryptoServiceError.encryptionFailed
        }
        
        let salt = try randomSalt()
        let keyData = try deriveKey(password: password, salt: salt)
        let symmetricKey = SymmetricKey(data: keyData)
        
        let sealedBox = try ChaChaPoly.seal(plain, using: symmetricKey)
        
        // Build envelope: version (1 byte) + salt (16 bytes) + ciphertext
        var envelope = Data()
        envelope.append(Self.version)
        envelope.append(salt)
        envelope.append(sealedBox.combined)
        
        return envelope
    }

    /// Decrypt data with password
    /// - Parameters:
    ///   - data: Encrypted envelope data
    ///   - password: Password for key derivation
    /// - Returns: Decrypted plain text
    func decrypt(data: Data, password: String) throws -> String {
        // Parse envelope
        guard data.count > 1 + Self.saltLength else {
            throw CryptoServiceError.invalidEnvelope
        }
        
        var cursor = data.startIndex
        
        // Read version byte
        let version = data[cursor]
        guard version == Self.version else {
            throw CryptoServiceError.unsupportedVersion
        }
        cursor = data.index(after: cursor)
        
        // Read salt
        let saltEnd = data.index(cursor, offsetBy: Self.saltLength)
        let salt = Data(data[cursor..<saltEnd])
        
        // Read ciphertext
        let ciphertext = Data(data[saltEnd..<data.endIndex])
        
        // Derive key and decrypt
        let keyData = try deriveKey(password: password, salt: salt)
        let symmetricKey = SymmetricKey(data: keyData)
        
        let sealedBox = try ChaChaPoly.SealedBox(combined: ciphertext)
        let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey)
        
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw CryptoServiceError.decryptionFailed
        }
        
        return string
    }

    // MARK: - Private Methods
    
    /// Derive encryption key from password using PBKDF2-HMAC-SHA256
    private func deriveKey(password: String, salt: Data) throws -> Data {
        var derivedData = Data(count: Self.keyLength)
        
        let status = derivedData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, password.utf8.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    Self.pbkdfRounds,
                    derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), Self.keyLength
                )
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoServiceError.derivationFailed
        }
        
        return derivedData
    }

    /// Generate cryptographically secure random salt
    private func randomSalt() throws -> Data {
        var data = Data(count: Self.saltLength)
        
        let result = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, Self.saltLength, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw CryptoServiceError.derivationFailed
        }
        
        return data
    }
}
