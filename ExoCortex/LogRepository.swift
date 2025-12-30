import Foundation

actor LogRepository {
    private let crypto = CryptoService()
    private let fileURL: URL

    init(fileName: String = "cortex.enc") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = documents.appendingPathComponent(fileName)
    }

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

    func save(text: String, password: String) async throws {
        let encrypted = try await crypto.encrypt(text: text, password: password)
        let url = fileURL
        try await Task.detached(priority: .utility) {
            try encrypted.write(to: url, options: [.atomic])
        }.value
    }
}
