//
//  LogViewModel.swift
//  ExoCortex
//
//  View model managing log state, encryption, filtering, and AI interactions.
//

import Foundation
import Combine
import LocalAuthentication

// MARK: - Log View Model

/// Main view model orchestrating log functionality including encryption,
/// filtering, todo management, and AI prompt processing.
@MainActor
final class LogViewModel: ObservableObject {
    
    // MARK: - Types
    
    /// Current state of the autosave operation
    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    /// Represents a single line in the filtered view
    struct LineItem: Identifiable, Equatable {
        let id: Int      // Line index in fullText
        let text: String
        let isTodo: Bool
        let isDone: Bool
    }

    // MARK: - Published State
    
    @Published var isLocked = true
    @Published var isLoading = false
    @Published var password = ""
    @Published var keychainStatus: String?
    @Published var fullText = "" {
        didSet { textDidChange(oldValue: oldValue) }
    }
    @Published var filterText = "" {
        didSet { applyFilter() }
    }
    @Published var filteredLines: [LineItem] = []
    @Published var filteredText = "" {
        didSet { filteredTextDidChange() }
    }
    @Published var savedFilters: [String] = []
    @Published var unlockError: String?
    @Published var filterError: String?
    @Published var saveStatus: SaveStatus = .idle
    @Published var isStreaming = false

    // MARK: - Dependencies
    
    private let repository: LogRepository
    private let keychain: KeychainService
    private let parser = TagQueryParser()
    private let openRouter = OpenRouterService()
    private let contextResolver = ContextResolver()
    
    // MARK: - Private State
    
    private var activePassword: String?
    private var streamTask: Task<Void, Never>?
    private var previousText = ""
    private var isStreamingAppend = false
    private var isUpdatingFilteredText = false

    // MARK: - Initialization
    
    init(repository: LogRepository, keychain: KeychainService) {
        self.repository = repository
        self.keychain = keychain
        self.savedFilters = UserDefaults.standard.stringArray(forKey: "savedFilters") ?? []
    }

    convenience init() {
        self.init(repository: LogRepository(), keychain: KeychainService())
    }

    // MARK: - Authentication
    
    /// Attempt unlock with entered password
    func unlockWithPassword() {
        let input = password
        guard !input.isEmpty else {
            unlockError = "Password required"
            return
        }
        unlockError = nil
        Task { await unlock(using: input) }
    }

    /// Attempt unlock using biometric authentication
    func unlockWithBiometrics() {
        Task {
            do {
                let retrieved = try await keychain.loadPasswordWithBiometrics(reason: "Unlock ExoCortex")
                await unlock(using: retrieved)
            } catch let error as KeychainServiceError {
                unlockError = error.localizedDescription
            } catch {
                unlockError = "Biometric unlock failed"
            }
        }
    }

    /// Lock the log and clear sensitive data (saves before locking)
    func lock() {
        cancelStream()
        // Force save before locking
        Task {
            await forceSave()
            activePassword = nil
            password = ""
            fullText = ""
            previousText = ""
            filteredLines = []
            isLocked = true
            saveStatus = .idle
        }
    }

    /// Store password in keychain with biometric protection for later retrieval
    func rememberPasswordInKeychain() {
        guard let pwd = activePassword, !pwd.isEmpty else {
            keychainStatus = "No password to save"
            return
        }
        keychainStatus = nil
        Task {
            do {
                try await keychain.savePassword(pwd)
                keychainStatus = "Password saved - use biometrics to unlock"
            } catch let error as KeychainServiceError {
                keychainStatus = error.localizedDescription
            } catch {
                keychainStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Remove stored password from keychain
    func clearKeychainPassword() {
        Task {
            do {
                try await keychain.deletePassword()
                keychainStatus = "Saved password cleared"
            } catch {
                keychainStatus = "Failed to clear password"
            }
        }
    }

    // MARK: - Filter Management
    
    /// Add a new saved filter
    func addSavedFilter(_ filter: String) {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !savedFilters.contains(trimmed) else { return }
        savedFilters.append(trimmed)
        persistFilters()
    }

    /// Remove a saved filter
    func removeSavedFilter(_ filter: String) {
        savedFilters.removeAll { $0 == filter }
        persistFilters()
    }

    /// Apply a saved filter to the current view
    func applySavedFilter(_ filter: String) {
        filterText = filter
    }

    // MARK: - Todo Management
    
    /// Toggle a todo item between open and done states
    func toggleTodo(for lineID: Int) {
        let lines = fullText.components(separatedBy: "\n")
        guard lineID >= 0 && lineID < lines.count else { return }
        
        var mutable = lines
        let line = mutable[lineID]
        
        // Toggle between [ ] and [x]
        let updated: String
        if let range = line.range(of: "[ ]") {
            updated = line.replacingCharacters(in: range, with: "[x]")
        } else if let range = line.range(of: "[x]", options: .caseInsensitive) {
            updated = line.replacingCharacters(in: range, with: "[ ]")
        } else {
            return
        }
        
        mutable[lineID] = updated
        fullText = mutable.joined(separator: "\n")
    }
    
    /// Cancel any ongoing AI stream
    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    /// Insert a date separator line at the end of the log
    /// Format: --- YYYY-MM-DD --- for LLM temporal context
    func insertDateLine() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        let dateLine = "\n--- \(dateString) ---\n"
        fullText += dateLine
    }

    // MARK: - Private Methods
    
    private func unlock(using password: String) async {
        isLoading = true
        do {
            let text = try await repository.load(password: password)
            activePassword = password
            previousText = text
            fullText = text
            isLocked = false
            saveStatus = .saved
            unlockError = nil
            applyFilter()
        } catch {
            unlockError = "Invalid password or data"
            isLocked = true
        }
        isLoading = false
    }

    private func textDidChange(oldValue: String) {
        // Cancel stream if user types during streaming
        if isStreaming && !isStreamingAppend {
            cancelStream()
        }
        
        applyFilter()
        // Note: No more auto-save debounce - saves only on focus lost, lock, or app close
        detectAndProcessPrompt(oldText: oldValue, newText: fullText)
        previousText = fullText
    }

    private func applyFilter() {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            filterError = nil
            filteredLines = enumerateLines(matching: nil)
            updateFilteredText()
            return
        }
        
        if let node = parser.parse(trimmed) {
            filterError = nil
            filteredLines = enumerateLines(matching: node)
        } else {
            filterError = "Invalid filter"
            filteredLines = enumerateLines(matching: nil)
        }
        updateFilteredText()
    }

    private func enumerateLines(matching node: TagQueryParser.Node?) -> [LineItem] {
        fullText.components(separatedBy: "\n").enumerated().compactMap { idx, line in
            guard parser.matches(node: node, line: line) else { return nil }
            let lower = line.lowercased()
            let isDone = lower.contains("[x]")
            let isTodo = lower.contains("[ ]") || isDone
            return LineItem(id: idx, text: line, isTodo: isTodo, isDone: isDone)
        }
    }
    
    /// Handle changes to filteredText - sync back to fullText
    private func filteredTextDidChange() {
        // Skip if we're programmatically updating filteredText
        guard !isUpdatingFilteredText else { return }
        
        // Skip if no filter is active (fullText is the source of truth)
        guard !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Get current filtered line indices
        let lineIndices = filteredLines.map { $0.id }
        guard !lineIndices.isEmpty else { return }
        
        // Split the edited filtered text into lines
        let editedLines = filteredText.components(separatedBy: "\n")
        
        // Get the full text lines
        var fullLines = fullText.components(separatedBy: "\n")
        
        // Handle the case where user is editing within the filtered view
        // Map edited lines back to their original positions
        for (editIndex, originalIndex) in lineIndices.enumerated() {
            guard originalIndex < fullLines.count else { continue }
            
            if editIndex < editedLines.count {
                // Update existing line
                fullLines[originalIndex] = editedLines[editIndex]
            }
        }
        
        // Handle added lines at the end of filtered text
        if editedLines.count > lineIndices.count {
            // User added new lines at the end of the filtered view
            // Insert them after the last filtered line
            if let lastIndex = lineIndices.last {
                let newLines = editedLines.suffix(editedLines.count - lineIndices.count)
                let insertIndex = lastIndex + 1
                for (offset, newLine) in newLines.enumerated() {
                    fullLines.insert(newLine, at: min(insertIndex + offset, fullLines.count))
                }
            }
        }
        
        // Handle removed lines (user deleted content in filtered view)
        // If fewer edited lines than filtered lines, append empty handling
        // Actually, for simplicity, we'll just update existing lines
        // and let new lines be added. Deletion across filtered views is complex.
        
        // Update fullText without triggering another filter cycle
        let newFullText = fullLines.joined(separator: "\n")
        if fullText != newFullText {
            fullText = newFullText
        }
    }
    
    /// Update filteredText from filteredLines (called from applyFilter)
    private func updateFilteredText() {
        isUpdatingFilteredText = true
        filteredText = filteredLines.map(\.text).joined(separator: "\n")
        isUpdatingFilteredText = false
    }

    /// Force save immediately - called on focus lost, lock, or app termination
    func forceSave() async {
        guard let password = activePassword else { return }
        guard !isLocked else { return }
        saveStatus = .saving
        do {
            try await repository.save(text: fullText, password: password)
            saveStatus = .saved
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }

    private func persistFilters() {
        UserDefaults.standard.set(savedFilters, forKey: "savedFilters")
    }
    
    // MARK: - LLM Integration
    
    private func detectAndProcessPrompt(oldText: String, newText: String) {
        guard !isStreaming else { return }
        
        // Check if a newline was added (Enter key pressed)
        let oldNewlineCount = oldText.filter { $0 == "\n" }.count
        let newNewlineCount = newText.filter { $0 == "\n" }.count
        guard newNewlineCount > oldNewlineCount else { return }
        
        let lines = newText.components(separatedBy: "\n")
        
        // Find unprocessed #p prompts
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix(LLMConfig.promptTag.lowercased()) else { continue }
            guard index + 1 < lines.count else { continue }
            
            let nextLine = lines[index + 1].trimmingCharacters(in: .whitespaces).lowercased()
            
            // Skip if already processed
            if nextLine.hasPrefix(LLMConfig.responseTag.lowercased()) ||
               nextLine.hasPrefix(LLMConfig.errorTag.lowercased()) {
                continue
            }
            
            // Extract prompt text after tag
            let tagLength = LLMConfig.promptTag.count
            guard trimmed.count > tagLength else { continue }
            
            let promptIndex = trimmed.index(trimmed.startIndex, offsetBy: tagLength)
            let promptText = String(trimmed[promptIndex...]).trimmingCharacters(in: .whitespaces)
            guard !promptText.isEmpty else { continue }
            
            processPrompt(promptText)
            return // Process one at a time
        }
    }
    
    private func processPrompt(_ rawPrompt: String) {
        cancelStream()
        
        // Resolve @-references to context
        let resolution = contextResolver.resolve(prompt: rawPrompt, fullText: fullText)
        
        // Build full message with context
        let fullMessage: String
        if let context = resolution.context {
            fullMessage = """
            Context from work log:
            \(context)
            
            User prompt: \(resolution.cleanPrompt)
            """
        } else {
            fullMessage = resolution.cleanPrompt
        }
        
        // Insert response tag
        appendToText("\(LLMConfig.responseTag) ")
        isStreaming = true
        
        streamTask = Task { [weak self] in
            await self?.streamResponse(message: fullMessage)
        }
    }
    
    private func streamResponse(message: String) async {
        do {
            let stream = await openRouter.stream(userMessage: message)
            
            for try await chunk in stream {
                if Task.isCancelled { break }
                appendToText(chunk)
            }
            
            appendToText("\n---\n")
            isStreaming = false
        } catch {
            appendToText("\n\(LLMConfig.errorTag) \(error.localizedDescription)\n---\n")
            isStreaming = false
        }
    }
    
    /// Append text without triggering prompt detection
    private func appendToText(_ text: String) {
        isStreamingAppend = true
        fullText += text
        isStreamingAppend = false
    }
}
