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
    
    // Account names for different keychain items
    private let passwordAccount = "cortexPassword"
    private let apiKeyAccount = "openRouterAPIKey"
    
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
        guard let data = password.data(using: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(errSecParam)
        }
        
        // Create LAContext - must be done and used carefully for iOS biometric UI
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 10
        
        // Verify biometrics are available (can be done synchronously)
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Biometrics not enrolled or available"
            throw KeychainServiceError.biometryUnavailable(reason)
        }
        
        // Pre-authenticate to ensure the context is "warm" before keychain operations
        // This helps avoid -34018 on first save in sandboxed apps
        // CRITICAL: On iOS, evaluatePolicy callback must not be blocked and UI must be on main thread
        do {
            // Use withCheckedThrowingContinuation to properly bridge the callback-based API
            // The biometric UI presentation is handled internally by LAContext
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Authenticate to save your password securely"
                ) { success, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: KeychainServiceError.biometryFailed("Authentication failed"))
                    }
                }
            }
        } catch let error as LAError {
            throw mapLAError(error)
        } catch let error as KeychainServiceError {
            throw error
        }
        
        // Delete any existing entry first (ignore errors)
        await deletePasswordSilently()
        
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
        
        // Perform save on background queue to avoid blocking
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Build query with LAContext attached - critical for avoiding -34018
                // The context proves entitlement to access the keychain in sandboxed apps
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.passwordAccount, // Use passwordAccount
                    kSecValueData as String: data,
                    kSecAttrAccessControl as String: accessControl,
                    kSecUseAuthenticationContext as String: context
                ]
                
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
        // Use LAContext.localizedReason instead of deprecated kSecUseOperationPrompt
        context.localizedReason = reason
        context.touchIDAuthenticationAllowableReuseDuration = 10
        
        // Verify biometrics availability
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let errorReason = authError?.localizedDescription ?? "Biometrics not available"
            throw KeychainServiceError.biometryUnavailable(errorReason)
        }
        
        // Perform on background thread as it blocks for biometric auth
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Query with context - this triggers biometric automatically because
                // the item was saved with biometric access control
                // Note: Using only kSecUseAuthenticationContext (localizedReason is set on context)
                // instead of deprecated kSecUseOperationPrompt
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.passwordAccount, // Use passwordAccount
                    kSecReturnData as String: true,
                    kSecUseAuthenticationContext as String: context
                ]
                
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
    
    /// Save API key to keychain (without biometric protection)
    /// - Parameter apiKey: The API key to store
    /// - Throws: KeychainServiceError if save fails
    func saveAPIKey(_ apiKey: String) async throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(errSecParam)
        }
        
        // Delete any existing entry first (ignore errors)
        await deleteAPIKeySilently()
        
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Build query without access control (API keys don't need biometric protection)
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.apiKeyAccount,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ]
                
                let result = SecItemAdd(query as CFDictionary, nil)
                continuation.resume(returning: result)
            }
        }
        
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Load API key from keychain
    /// - Returns: The stored API key or nil if not found
    /// - Throws: KeychainServiceError if load fails
    func loadAPIKey() async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.apiKeyAccount,
                    kSecReturnData as String: true
                ]
                
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                
                switch status {
                case errSecSuccess:
                    guard let data = item as? Data,
                          let apiKey = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: KeychainServiceError.unexpectedStatus(errSecDecode))
                        return
                    }
                    continuation.resume(returning: apiKey)
                    
                case errSecItemNotFound:
                    continuation.resume(returning: nil)
                    
                default:
                    continuation.resume(throwing: KeychainServiceError.unexpectedStatus(status))
                }
            }
        }
    }
    
    /// Clear API key from keychain
    /// - Throws: KeychainServiceError if delete fails (except item not found)
    func clearAPIKey() async throws {
        let status = await performAPIKeyDelete()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Check if a password is stored in the keychain
    /// - Returns: true if a password exists
    nonisolated func hasStoredPassword() -> Bool {
        // Use LAContext with interactionNotAllowed instead of deprecated kSecUseAuthenticationUIFail
        let context = LAContext()
        context.interactionNotAllowed = true
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount, // Use passwordAccount
            kSecUseAuthenticationContext as String: context
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
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.passwordAccount // Use passwordAccount
                ]
                
                let status = SecItemDelete(query as CFDictionary)
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Delete API key without throwing errors
    private func deleteAPIKeySilently() async {
        _ = await performAPIKeyDelete()
    }
    
    /// Perform the actual delete operation for API key
    private func performAPIKeyDelete() async -> OSStatus {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: self.service,
                    kSecAttrAccount as String: self.apiKeyAccount
                ]
                
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
