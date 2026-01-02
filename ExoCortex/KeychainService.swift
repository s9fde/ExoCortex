//
//  KeychainService.swift
//  ExoCortex
//
//  Modern keychain service for secure password storage with biometric protection.
//  Uses async/await and proper LAContext management to avoid -34018 errors.
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
    case accessControlCreationFailed(String)
    case unexpectedStatus(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .biometryUnavailable(let reason):
            return "Biometrics unavailable: \(reason)"
        case .biometryFailed(let reason):
            return "Biometric auth failed: \(reason)"
        case .itemNotFound:
            return "No stored password found"
        case .accessControlCreationFailed(let reason):
            return "Failed to create access control: \(reason)"
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            return "Keychain error \(status): \(message)"
        }
    }
}

// MARK: - Keychain Service

/// Service for storing and retrieving passwords in the iOS/macOS Keychain
/// with biometric (Face ID / Touch ID) protection.
///
/// This implementation uses the modern approach of binding an LAContext
/// during save operations to avoid error -34018 (errSecMissingEntitlement)
/// in sandboxed macOS apps.
actor KeychainService {
    
    // MARK: - Constants
    
    /// Service identifier for keychain entries (must match keychain-access-groups in entitlements)
    private let service = "com.exocortex.app"
    
    /// Account name for the stored password
    private let account = "cortexPassword"
    
    /// Shared instance for convenience
    static let shared = KeychainService()

    // MARK: - Public Methods
    
    /// Check if biometrics are available on this device
    nonisolated func biometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Save password to keychain for biometric-protected retrieval.
    ///
    /// This method uses an LAContext during save to properly bind the access control
    /// to the keychain item. This is the modern approach that avoids -34018 errors
    /// in sandboxed macOS apps.
    ///
    /// - Parameter password: The password to store
    /// - Throws: KeychainServiceError if save fails
    func savePassword(_ password: String) async throws {
        // Create and configure LAContext for the save operation
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 10
        
        // Verify biometrics are available
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Biometrics not enrolled or available"
            throw KeychainServiceError.biometryUnavailable(reason)
        }
        
        // Pre-authenticate to ensure the context is "warm" before keychain operations
        // This helps avoid -34018 on first save in sandboxed apps
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to save your password securely"
            )
        } catch let error as LAError {
            throw mapLAError(error)
        }
        
        // Delete any existing entry first (ignore errors)
        await deletePasswordSilently()
        
        guard let data = password.data(using: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(errSecParam)
        }
        
        // Create access control requiring biometric authentication for future access
        // Using .biometryCurrentSet invalidates the item if biometrics change
        var accessControlError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &accessControlError
        ) else {
            let errorDesc = accessControlError?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw KeychainServiceError.accessControlCreationFailed(errorDesc)
        }
        
        // Build query with LAContext attached - critical for avoiding -34018
        // The context proves entitlement to access the keychain in sandboxed apps
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
            kSecUseAuthenticationContext as String: context
        ]
        
        // Perform save on background queue to avoid blocking
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = SecItemAdd(query as CFDictionary, nil)
                continuation.resume(returning: result)
            }
        }
        
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    /// Load password from keychain using biometric authentication.
    ///
    /// - Parameter reason: Reason string shown to user during biometric prompt
    /// - Returns: The stored password
    /// - Throws: KeychainServiceError if load fails
    func loadPasswordWithBiometrics(reason: String) async throws -> String {
        let context = LAContext()
        context.localizedReason = reason
        context.touchIDAuthenticationAllowableReuseDuration = 10
        
        // Verify biometrics availability
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let errorReason = authError?.localizedDescription ?? "Biometrics not available"
            throw KeychainServiceError.biometryUnavailable(errorReason)
        }
        
        // Query with context - this triggers biometric automatically because
        // the item was saved with biometric access control
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: reason
        ]
        
        // Perform on background thread as it blocks for biometric auth
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                
                switch status {
                case errSecSuccess:
                    guard let data = item as? Data,
                          let password = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: KeychainServiceError.unexpectedStatus(errSecDecode))
                        return
                    }
                    continuation.resume(returning: password)
                    
                case errSecItemNotFound:
                    continuation.resume(throwing: KeychainServiceError.itemNotFound)
                    
                case errSecUserCanceled:
                    continuation.resume(throwing: KeychainServiceError.biometryFailed("User cancelled"))
                    
                case errSecAuthFailed:
                    continuation.resume(throwing: KeychainServiceError.biometryFailed("Authentication failed"))
                    
                case errSecInteractionNotAllowed:
                    continuation.resume(throwing: KeychainServiceError.biometryFailed("Interaction not allowed"))
                    
                default:
                    continuation.resume(throwing: KeychainServiceError.unexpectedStatus(status))
                }
            }
        }
    }

    /// Delete stored password from keychain
    /// - Throws: KeychainServiceError if delete fails (except item not found)
    func deletePassword() async throws {
        let status = await performDelete()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Check if a password is stored in the keychain
    /// - Returns: true if a password exists
    nonisolated func hasStoredPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed means item exists but needs auth
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
    
    // MARK: - Private Methods
    
    /// Delete password without throwing errors
    private func deletePasswordSilently() async {
        _ = await performDelete()
    }
    
    /// Perform the actual delete operation
    private func performDelete() async -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let status = SecItemDelete(query as CFDictionary)
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Map LAError to KeychainServiceError
    private func mapLAError(_ error: LAError) -> KeychainServiceError {
        switch error.code {
        case .userCancel:
            return .biometryFailed("User cancelled")
        case .userFallback:
            return .biometryFailed("User chose fallback")
        case .biometryNotAvailable:
            return .biometryUnavailable("Biometry not available")
        case .biometryNotEnrolled:
            return .biometryUnavailable("No biometrics enrolled")
        case .biometryLockout:
            return .biometryFailed("Biometry is locked out")
        case .authenticationFailed:
            return .biometryFailed("Authentication failed")
        default:
            return .biometryFailed(error.localizedDescription)
        }
    }
}
