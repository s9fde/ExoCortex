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
    /// Note: The password is stored with biometric access control, meaning
    /// biometric authentication is required when RETRIEVING the password.
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
        
        // Create access control that requires biometric authentication
        // Using .biometryCurrentSet ensures re-enrollment if biometrics change
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            let errorDesc = accessControlError?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw KeychainServiceError.biometryUnavailable("Failed to create access control: \(errorDesc)")
        }
        
        // Save password in keychain with biometric access control
        // This binds the keychain item directly to biometric auth, avoiding
        // the separate account password prompt
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
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
        // Check if biometrics are available
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let errorReason = authError?.localizedDescription ?? "Not available"
            throw KeychainServiceError.biometryUnavailable(errorReason)
        }
        
        // Set the reason that will be displayed in the biometric prompt
        context.localizedReason = reason
        
        // Query keychain with the LAContext - this triggers biometric auth
        // automatically because the item was saved with biometric access control.
        // The system handles the biometric prompt when accessing the item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: reason
        ]

        // Perform keychain access on background thread as it may block
        // waiting for biometric authentication
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                
                if status == errSecItemNotFound {
                    continuation.resume(throwing: KeychainServiceError.itemNotFound)
                    return
                }
                
                if status == errSecUserCanceled {
                    continuation.resume(throwing: KeychainServiceError.biometryFailed("User cancelled"))
                    return
                }
                
                if status == errSecAuthFailed {
                    continuation.resume(throwing: KeychainServiceError.biometryFailed("Authentication failed"))
                    return
                }
                
                guard status == errSecSuccess,
                      let data = item as? Data,
                      let password = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: KeychainServiceError.unexpectedStatus(status))
                    return
                }
                
                continuation.resume(returning: password)
            }
        }
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
