//
//  KeychainService.swift
//  ExoCortex
//
//  Secure keychain service for password storage with biometric (Touch ID / Face ID) protection.
//  Follows Apple's recommended patterns for LocalAuthentication + Keychain integration.
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
            return "Biometric authentication failed: \(reason)"
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

/// Actor-based service for storing and retrieving passwords in the macOS/iOS Keychain
/// with optional biometric (Face ID / Touch ID) protection.
///
/// ## Architecture Notes
/// - Uses `actor` for thread-safe access to keychain operations
/// - Employs pre-authentication pattern: authenticate with LAContext first, then use
///   the "warm" context for keychain operations to avoid -34018 errors in sandboxed apps
/// - Tracks biometric password state in UserDefaults to avoid triggering biometric
///   prompts when just checking if a password exists
actor KeychainService {
    
    // MARK: - Configuration
    
    /// Service identifier for keychain entries (should match bundle identifier)
    private let service = "com.exocortex.app"
    
    /// Account identifier for the encrypted password
    private let passwordAccount = "cortexPassword"
    
    /// Account identifier for the API key
    private let apiKeyAccount = "openRouterAPIKey"
    
    /// Account identifier for the LLM model
    private let llmModelAccount = "llmModel"
    
    /// Account identifier for the system prompt
    private let systemPromptAccount = "systemPrompt"
    
    /// UserDefaults key for tracking biometric password state
    private static let biometricEnabledKey = "com.exocortex.biometricPasswordEnabled"
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide access
    static let shared = KeychainService()
    
    // MARK: - Biometric Availability
    
    /// Checks if biometric authentication is available on this device.
    /// - Returns: `true` if Touch ID or Face ID is enrolled and available
    nonisolated func biometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Checks if a biometric-protected password has been stored.
    /// Uses UserDefaults to avoid triggering biometric prompts.
    /// - Returns: `true` if a password was previously saved with biometric protection
    nonisolated func hasStoredPassword() -> Bool {
        UserDefaults.standard.bool(forKey: KeychainService.biometricEnabledKey)
    }
    
    // MARK: - Password Operations
    
    /// Saves a password to the keychain with biometric protection.
    ///
    /// This method follows Apple's recommended pattern:
    /// 1. Create and authenticate an LAContext
    /// 2. Create access control with biometric requirements
    /// 3. Bind the authenticated context to the keychain item
    ///
    /// - Parameter password: The password to store securely
    /// - Throws: `KeychainServiceError` if biometrics unavailable or save fails
    func savePassword(_ password: String) async throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(errSecParam)
        }
        
        // Create and configure LAContext for authentication
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 10
        
        // Verify biometric availability
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Biometrics not enrolled or available"
            throw KeychainServiceError.biometryUnavailable(reason)
        }
        
        // Pre-authenticate to "warm" the context
        try await authenticateWithBiometrics(
            context: context,
            reason: "Authenticate to save your password securely"
        )
        
        // Remove any existing entry
        deleteKeychainItem(service: service, account: passwordAccount)
        
        // Create access control requiring current biometric enrollment
        let accessControl = try createBiometricAccessControl()
        
        // Build and execute the add query with the authenticated context
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
            kSecUseAuthenticationContext as String: context
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        
        // Track state in UserDefaults
        UserDefaults.standard.set(true, forKey: KeychainService.biometricEnabledKey)
    }
    
    /// Loads the stored password using biometric authentication.
    ///
    /// - Parameter reason: The reason string shown in the biometric prompt
    /// - Returns: The decrypted password
    /// - Throws: `KeychainServiceError` if authentication fails or no password stored
    func loadPasswordWithBiometrics(reason: String) async throws -> String {
        // Create and configure LAContext
        let context = LAContext()
        context.localizedReason = reason
        context.touchIDAuthenticationAllowableReuseDuration = 30
        
        // Verify biometric availability
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            let errorReason = authError?.localizedDescription ?? "Biometrics not available"
            throw KeychainServiceError.biometryUnavailable(errorReason)
        }
        
        // Pre-authenticate to warm the context
        try await authenticateWithBiometrics(context: context, reason: reason)
        
        // Query keychain with authenticated context
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw KeychainServiceError.unexpectedStatus(errSecDecode)
            }
            return password
            
        case errSecItemNotFound:
            throw KeychainServiceError.itemNotFound
            
        case errSecUserCanceled:
            throw KeychainServiceError.biometryFailed("User cancelled")
            
        case errSecAuthFailed:
            throw KeychainServiceError.biometryFailed("Authentication failed")
            
        case errSecInteractionNotAllowed:
            throw KeychainServiceError.biometryFailed("Interaction not allowed")
            
        default:
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Deletes the stored password from the keychain.
    /// - Throws: `KeychainServiceError` if deletion fails unexpectedly
    func deletePassword() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: passwordAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        
        // Update state tracking
        UserDefaults.standard.set(false, forKey: KeychainService.biometricEnabledKey)
    }
    
    // MARK: - API Key Operations
    
    /// Saves an API key to the keychain without biometric protection.
    /// API keys use standard keychain protection (device unlock required).
    /// - Parameter apiKey: The API key to store
    /// - Throws: `KeychainServiceError` if save fails
    func saveAPIKey(_ apiKey: String) async throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(errSecParam)
        }
        
        // Remove existing entry
        deleteKeychainItem(service: service, account: apiKeyAccount)
        
        // Add new entry with standard protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Loads the API key from the keychain.
    /// - Returns: The stored API key, or `nil` if not found
    /// - Throws: `KeychainServiceError` if load fails unexpectedly
    func loadAPIKey() async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw KeychainServiceError.unexpectedStatus(errSecDecode)
            }
            return apiKey
            
        case errSecItemNotFound:
            return nil
            
        default:
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    /// Clears the API key from the keychain.
    /// - Throws: `KeychainServiceError` if deletion fails unexpectedly
    func clearAPIKey() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }
    
    // MARK: - LLM Model Operations
    
    /// Saves the selected LLM model to the keychain.
    /// - Parameter model: The model identifier (e.g., "anthropic/claude-opus-4.5")
    /// - Throws: `KeychainServiceError` if save fails
   func saveLLMModel(_ model: String) async throws {
       guard let data = model.data(using: .utf8) else {
           throw KeychainServiceError.unexpectedStatus(errSecParam)
       }
       
       // Remove existing entry
       deleteKeychainItem(service: service, account: llmModelAccount)
       
       // Add new entry
       let query: [String: Any] = [
           kSecClass as String: kSecClassGenericPassword,
           kSecAttrService as String: service,
           kSecAttrAccount as String: llmModelAccount,
           kSecValueData as String: data,
           kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
       ]
       
       let status = SecItemAdd(query as CFDictionary, nil)
       guard status == errSecSuccess else {
           throw KeychainServiceError.unexpectedStatus(status)
       }
   }
   
   /// Loads the selected LLM model from the keychain.
   /// - Returns: The stored model identifier, or `nil` if not found
   /// - Throws: `KeychainServiceError` if load fails unexpectedly
   func loadLLMModel() async throws -> String? {
       let query: [String: Any] = [
           kSecClass as String: kSecClassGenericPassword,
           kSecAttrService as String: service,
           kSecAttrAccount as String: llmModelAccount,
           kSecReturnData as String: true
       ]
       
       var item: CFTypeRef?
       let status = SecItemCopyMatching(query as CFDictionary, &item)
       
       switch status {
       case errSecSuccess:
           guard let data = item as? Data,
                 let model = String(data: data, encoding: .utf8) else {
               throw KeychainServiceError.unexpectedStatus(errSecDecode)
           }
           return model
           
       case errSecItemNotFound:
           return nil
           
       default:
           throw KeychainServiceError.unexpectedStatus(status)
       }
   }
   
   // MARK: - System Prompt Operations
   
   /// Saves the system prompt to the keychain.
   /// - Parameter prompt: The system prompt text
   /// - Throws: `KeychainServiceError` if save fails
   func saveSystemPrompt(_ prompt: String) async throws {
       guard let data = prompt.data(using: .utf8) else {
           throw KeychainServiceError.unexpectedStatus(errSecParam)
       }
       
       // Remove existing entry
       deleteKeychainItem(service: service, account: systemPromptAccount)
       
       // Add new entry
       let query: [String: Any] = [
           kSecClass as String: kSecClassGenericPassword,
           kSecAttrService as String: service,
           kSecAttrAccount as String: systemPromptAccount,
           kSecValueData as String: data,
           kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
       ]
       
       let status = SecItemAdd(query as CFDictionary, nil)
       guard status == errSecSuccess else {
           throw KeychainServiceError.unexpectedStatus(status)
       }
   }
   
   /// Loads the system prompt from the keychain.
   /// - Returns: The stored system prompt, or `nil` if not found
   /// - Throws: `KeychainServiceError` if load fails unexpectedly
   func loadSystemPrompt() async throws -> String? {
       let query: [String: Any] = [
           kSecClass as String: kSecClassGenericPassword,
           kSecAttrService as String: service,
           kSecAttrAccount as String: systemPromptAccount,
           kSecReturnData as String: true
       ]
       
       var item: CFTypeRef?
       let status = SecItemCopyMatching(query as CFDictionary, &item)
       
       switch status {
       case errSecSuccess:
           guard let data = item as? Data,
                 let prompt = String(data: data, encoding: .utf8) else {
               throw KeychainServiceError.unexpectedStatus(errSecDecode)
           }
           return prompt
           
       case errSecItemNotFound:
           return nil
           
       default:
           throw KeychainServiceError.unexpectedStatus(status)
       }
   }
    
    // MARK: - Private Helpers
    
    /// Performs biometric authentication using the provided context.
    /// - Parameters:
    ///   - context: The LAContext to authenticate
    ///   - reason: The reason string shown in the biometric prompt
    /// - Throws: `KeychainServiceError` if authentication fails
    private func authenticateWithBiometrics(context: LAContext, reason: String) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
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
    }
    
    /// Creates an access control object requiring biometric authentication.
    /// Uses `.biometryCurrentSet` to invalidate the item if biometrics change.
    /// - Returns: A SecAccessControl configured for biometric protection
    /// - Throws: `KeychainServiceError` if creation fails
    private func createBiometricAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw KeychainServiceError.accessControlCreationFailed(errorDesc)
        }
        return accessControl
    }
    
    /// Deletes a keychain item silently (ignores errors).
    /// - Parameters:
    ///   - service: The service identifier
    ///   - account: The account identifier
    private func deleteKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
    
    /// Maps LocalAuthentication errors to KeychainServiceError.
    /// - Parameter error: The LAError to map
    /// - Returns: An appropriate KeychainServiceError
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
