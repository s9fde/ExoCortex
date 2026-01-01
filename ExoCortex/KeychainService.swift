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
    case biometryUnavailable
    case itemNotFound
    case unexpectedStatus(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .biometryUnavailable:
            return "Biometric authentication unavailable"
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
    
    /// Save password to keychain with biometric protection
    /// - Parameter password: The password to store
    func savePassword(_ password: String) throws {
        // Remove any existing entry first
        try deletePassword()
        
        // Create access control requiring biometrics
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryCurrentSet, .userPresence],
            &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }

        let context = LAContext()
        let data = Data(password.utf8)
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
            kSecUseAuthenticationContext as String: context
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    /// Load password from keychain using biometric authentication
    /// - Parameter reason: Reason string shown to user during biometric prompt
    /// - Returns: The stored password
    func loadPasswordWithBiometrics(reason: String) throws -> String {
        let context = LAContext()
        
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            throw KeychainServiceError.biometryUnavailable
        }
        
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
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
