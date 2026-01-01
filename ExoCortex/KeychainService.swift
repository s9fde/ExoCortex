//
//  KeychainService.swift
//  ExoCortex
//
//  Keychain service for secure password storage with biometric protection.
//

import Foundation
import LocalAuthentication
import Security

// MARK: - Keychain Errors

/// Errors that can occur during keychain operations
enum KeychainServiceError: Error, LocalizedError {
    case biometryUnavailable(String)
    case biometryFailed(String)
    case itemNotFound
    case unexpectedStatus(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .biometryUnavailable(let reason):
            return "Biometrics unavailable: \(reason)"
        case .biometryFailed(let reason):
            return "Biometric auth failed: \(reason)"
        case .itemNotFound:
            return "No stored password found"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - Keychain Service

/// Service for storing and retrieving passwords in the iOS/macOS Keychain
/// with biometric (Face ID / Touch ID) protection.
@MainActor
struct KeychainService {
    
    // MARK: - Constants
    
    /// Service identifier for keychain entries
    private let service = "com.exocortex.app"
    
    /// Account name for the stored password
    private let account = "cortexPassword"

    // MARK: - Public Methods
    
    /// Check if biometrics are available on this device
    func biometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Save password to keychain for biometric-protected retrieval
    /// - Parameter password: The password to store
    /// Note: The password is saved without encryption in the keychain.
    /// Biometric authentication is required when RETRIEVING the password.
    func savePassword(_ password: String) throws {
        // First verify biometrics are available on this device
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Not available"
            throw KeychainServiceError.biometryUnavailable(reason)
        }
        
        // Remove any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let data = Data(password.utf8)
        
        // Save password in keychain (accessible when device is unlocked)
        // Biometric authentication is enforced when reading via LAContext
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    /// Load password from keychain using biometric authentication
    /// - Parameter reason: Reason string shown to user during biometric prompt
    /// - Returns: The stored password
    func loadPasswordWithBiometrics(reason: String) async throws -> String {
        let context = LAContext()
        context.localizedReason = reason
        
        // Check if biometrics are available
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Not available"
            throw KeychainServiceError.biometryUnavailable(reason)
        }
        
        // Authenticate with biometrics
        // This triggers the Face ID / Touch ID prompt
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else {
                throw KeychainServiceError.biometryFailed("Authentication returned false")
            }
        } catch let laError as LAError {
            throw KeychainServiceError.biometryFailed(laError.localizedDescription)
        } catch {
            throw KeychainServiceError.biometryFailed(error.localizedDescription)
        }
        
        // After successful biometric auth, retrieve from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status != errSecItemNotFound else {
            throw KeychainServiceError.itemNotFound
        }
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        
        return password
    }

    /// Delete stored password from keychain
    func deletePassword() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
}
