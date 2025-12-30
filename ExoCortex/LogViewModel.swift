import Foundation
import Combine
import LocalAuthentication

@MainActor
final class LogViewModel: ObservableObject {
    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    struct LineItem: Identifiable, Equatable {
        let id: Int
        let text: String
        let isTodo: Bool
        let isDone: Bool
    }

    @Published var isLocked: Bool = true
    @Published var isLoading: Bool = false
    @Published var password: String = ""
    @Published var fullText: String = "" {
        didSet { textDidChange() }
    }
    @Published var filterText: String = "" {
        didSet { applyFilter() }
    }
    @Published var filteredLines: [LineItem] = []
    @Published var savedFilters: [String] = []
    @Published var unlockError: String?
    @Published var filterError: String?
    @Published var saveStatus: SaveStatus = .idle

    private let repository: LogRepository
    private let keychain: KeychainService
    private let parser = TagQueryParser()
    private var activePassword: String?
    private var saveWorkItem: DispatchWorkItem?

    init(repository: LogRepository, keychain: KeychainService) {
        self.repository = repository
        self.keychain = keychain
        self.savedFilters = UserDefaults.standard.stringArray(forKey: "savedFilters") ?? []
    }

    convenience init() {
        self.init(repository: LogRepository(), keychain: KeychainService())
    }

    func unlockWithPassword() {
        let input = password
        guard !input.isEmpty else { unlockError = "Password required"; return }
        unlockError = nil
        Task { await unlock(using: input) }
    }

    func unlockWithBiometrics() {
        Task {
            do {
                let retrieved = try keychain.loadPasswordWithBiometrics(reason: "Unlock ExoCortex")
                await unlock(using: retrieved)
            } catch {
                await MainActor.run { self.unlockError = "Biometric unlock failed" }
            }
        }
    }

    func lock() {
        saveWorkItem?.cancel()
        activePassword = nil
        password = ""
        fullText = ""
        filteredLines = []
        isLocked = true
        saveStatus = .idle
    }

    func rememberPasswordInKeychain() {
        guard let pwd = activePassword, !pwd.isEmpty else { return }
        do {
            try keychain.savePassword(pwd)
        } catch {
            // ignore silently for now
        }
    }

    func clearKeychainPassword() {
        try? keychain.deletePassword()
    }

    func addSavedFilter(_ filter: String) {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !savedFilters.contains(trimmed) {
            savedFilters.append(trimmed)
            persistFilters()
        }
    }

    func removeSavedFilter(_ filter: String) {
        savedFilters.removeAll { $0 == filter }
        persistFilters()
    }

    func applySavedFilter(_ filter: String) {
        filterText = filter
    }

    func toggleTodo(for lineID: Int) {
        let lines = fullText.components(separatedBy: "\n")
        guard lineID >= 0 && lineID < lines.count else { return }
        var mutable = lines
        let line = mutable[lineID]
        let updated: String
        if line.range(of: "[ ]") != nil {
            updated = line.replacingOccurrences(of: "[ ]", with: "[x]", options: .literal, range: line.range(of: "[ ]"))
        } else if line.range(of: "[x]", options: [.caseInsensitive]) != nil {
            updated = line.replacingOccurrences(of: "[x]", with: "[ ]", options: [.caseInsensitive], range: line.range(of: "[x]", options: [.caseInsensitive]))
        } else {
            updated = line
        }
        mutable[lineID] = updated
        fullText = mutable.joined(separator: "\n")
    }

    // MARK: - Private

    private func unlock(using password: String) async {
        await MainActor.run { self.isLoading = true }
        do {
            let text = try await repository.load(password: password)
            await MainActor.run {
                self.activePassword = password
                self.fullText = text
                self.isLocked = false
                self.saveStatus = .saved
                self.unlockError = nil
                self.applyFilter()
            }
        } catch {
            await MainActor.run {
                self.unlockError = "Invalid password or data"
                self.isLocked = true
            }
        }
        await MainActor.run { self.isLoading = false }
    }

    private func textDidChange() {
        applyFilter()
        scheduleAutosave()
    }

    private func applyFilter() {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            filterError = nil
            filteredLines = enumerateLines(matching: nil)
            return
        }
        if let node = parser.parse(trimmed) {
            filterError = nil
            filteredLines = enumerateLines(matching: node)
        } else {
            filterError = "Invalid filter"
            filteredLines = enumerateLines(matching: nil)
        }
    }

    private func enumerateLines(matching node: TagQueryParser.Node?) -> [LineItem] {
        let lines = fullText.components(separatedBy: "\n")
        var result: [LineItem] = []
        for (idx, line) in lines.enumerated() {
            if parser.matches(node: node, line: line) {
                let lower = line.lowercased()
                let isDone = lower.contains("[x]")
                let isTodo = lower.contains("[ ]") || isDone
                result.append(LineItem(id: idx, text: line, isTodo: isTodo, isDone: isDone))
            }
        }
        return result
    }

    private func scheduleAutosave() {
        guard !isLocked else { return }
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { await self?.performAutosave() }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func performAutosave() async {
        guard let password = activePassword else { return }
        await MainActor.run { self.saveStatus = .saving }
        do {
            try await repository.save(text: fullText, password: password)
            await MainActor.run { self.saveStatus = .saved }
        } catch {
            await MainActor.run { self.saveStatus = .error(error.localizedDescription) }
        }
    }

    private func persistFilters() {
        UserDefaults.standard.set(savedFilters, forKey: "savedFilters")
    }
}
