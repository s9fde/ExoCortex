import Foundation
import LocalAuthentication
import Security

enum KeychainServiceError: Error {
    case biometryUnavailable
    case itemNotFound
    case unexpectedStatus(OSStatus)
}

@MainActor
struct KeychainService {
    private let service = "com.exocortex.app"
    private let account = "cortexPassword"

    func savePassword(_ password: String) throws {
        try deletePassword()
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
                                                           kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           [.biometryCurrentSet, .userPresence],
                                                           &error) else {
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
        guard status == errSecSuccess else { throw KeychainServiceError.unexpectedStatus(status) }
    }

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
        guard status != errSecItemNotFound else { throw KeychainServiceError.itemNotFound }
        guard status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        return password
    }

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
