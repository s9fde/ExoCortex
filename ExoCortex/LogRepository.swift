//
//  LogRepository.swift
//  ExoCortex
//
//  Repository for encrypted log file persistence.
//

import Foundation

// MARK: - Log Repository

/// Handles loading and saving encrypted log data to disk.
/// Uses CryptoService for encryption/decryption operations.
actor LogRepository {
    
    // MARK: - Properties
    
    private let crypto = CryptoService()
    private let fileName: String
    
    private var fileURL: URL {
        if let icloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            // Ensure Documents directory exists in iCloud
            if !FileManager.default.fileExists(atPath: icloudURL.path) {
                try? FileManager.default.createDirectory(at: icloudURL, withIntermediateDirectories: true)
            }
            return icloudURL.appendingPathComponent(fileName)
        } else {
            // Fallback to local documents if iCloud is not available
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            return documents.appendingPathComponent(fileName)
        }
    }

    // MARK: - Initialization
    
    /// Initialize with a specific filename
    init(fileName: String = "cortex.enc") {
        self.fileName = fileName
    }

    // MARK: - File Operations
    
    /// Load and decrypt the log file
    /// - Parameter password: Password for decryption
    /// - Returns: Decrypted log content, or empty string if file doesn't exist
    func load(password: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ""
        }
        
        let url = fileURL
        let data = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
        
        return try await crypto.decrypt(data: data, password: password)
    }

    /// Encrypt and save log content to disk
    /// - Parameters:
    ///   - text: Plain text content to save
    ///   - password: Password for encryption
    func save(text: String, password: String) async throws {
        let encrypted = try await crypto.encrypt(text: text, password: password)
        let url = fileURL
        
        try await Task.detached(priority: .utility) {
            try encrypted.write(to: url, options: .atomic)
        }.value
    }
}
