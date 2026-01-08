//
//  LogViewModel.swift
//  ExoCortex
//
//  View model managing log state, encryption, filtering, and AI interactions.
//

import Foundation
import Observation
import LocalAuthentication

// MARK: - Log View Model

/// Main view model orchestrating log functionality including encryption,
/// filtering, todo management, and AI prompt processing.
///
/// This class is the central state manager for the ExoCortex application,
/// handling the lifecycle of the encrypted log and coordinating with
/// various services for persistence, security, and AI features.
@MainActor
@Observable
final class LogViewModel {
    
    // MARK: - Types
    
    /// Current state of the autosave operation
    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case error(String)
    }

    /// Current biometric capability and eligibility state
    enum BiometricStatus: Equatable {
        case checking
        case available(type: LABiometryType)
        case missingPassword
        case unavailable(String)
    }

    /// Represents a single line in the filtered view
    struct LineItem: Identifiable, Equatable {
        let id: Int      // Line index in fullText
        let text: String
        let isTodo: Bool
        let isDone: Bool
    }
    
    /// Entry in the LLM undo stack for recovering from AI edits
    struct LLMUndoEntry {
        let fullText: String
        let label: String
        let timestamp: Date
    }

    // MARK: - State
    
    var isLocked = true
    var isLoading = false
    var password = ""
    var keychainStatus: String?
    var apiKeyInput: String = "" // For binding to settings text field
    var apiKeyStatus: String?      // For displaying status in settings
    var biometricStatus: BiometricStatus = .checking
    var fullText = "" {
        didSet { textDidChange(oldValue: oldValue) }
    }
    var filterText = "" {
        didSet { applyFilter() }
    }
    var filteredLines: [LineItem] = []
    var filteredText = "" {
        didSet { filteredTextDidChange() }
    }
    var savedFilters: [String] = []
    var unlockError: String?
    var filterError: String?
    var saveStatus: SaveStatus = .idle
    var isFetching = false
    private(set) var canUndoLLM = false
    var showValidationSheet = false
    var validationResult: ValidationResult?

    // MARK: - Dependencies
    
    private let repository: LogRepository
    private let keychain: KeychainService
    private let parser = TagQueryParser()
    private let openRouter = OpenRouterService()
    private let scopeResolver = ScopeContextResolver()
    private let llmQueryDetector = LLMQueryDetector()
    
    // MARK: - Private State
    
    private var activePassword: String?
    private var fetchTask: Task<Void, Never>?
    private var previousText = ""
    private var isUpdatingFilteredText = false
    
    // LLM Undo Stack
    private var llmUndoStack: [LLMUndoEntry] = []
    private let maxUndoLevels = 3

    // MARK: - Initialization
    
    init(repository: LogRepository, keychain: KeychainService) {
        self.repository = repository
        self.keychain = keychain
        self.savedFilters = UserDefaults.standard.stringArray(forKey: "savedFilters") ?? []
    }

    convenience init() {
        self.init(repository: LogRepository(), keychain: KeychainService.shared)
        // Call postInit after full initialization
        postInit()
    }
    
    // Post-init setup for async operations
    private func postInit() {
        refreshBiometricStatus()
        Task {
            await loadAPIKeyFromKeychain(initialLoad: true)
            await loadLLMConfigFromKeychain()
        }
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

    /// True when biometric unlock is possible
    var canUseBiometricUnlock: Bool {
        if case .available = biometricStatus { return true }
        return false
    }

    /// Re-evaluate biometric eligibility (password stored + device capability)
    func refreshBiometricStatus() {
        // Check device capability first
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        // Then check for stored password
        let hasPassword = keychain.hasStoredPassword()

        if !canEvaluate {
            // Device doesn't support biometrics
            let message = error?.localizedDescription ?? "Face ID / Touch ID unavailable."
            biometricStatus = .unavailable(message)
        } else if !hasPassword {
            // Device supports biometrics but no password saved
            biometricStatus = .missingPassword
        } else {
            // Both conditions met
            biometricStatus = .available(type: context.biometryType)
        }
    }

    /// Attempt unlock using biometric authentication
    func unlockWithBiometrics(completion: (() -> Void)? = nil) {
        unlockError = nil
        refreshBiometricStatus()

        switch biometricStatus {
        case .missingPassword:
            unlockError = "Save your password in Settings to enable Face ID / Touch ID."
            completion?()
            return
        case .unavailable(let reason):
            unlockError = reason
            completion?()
            return
        case .available:
            break
        case .checking:
            unlockError = "Checking biometric availability…"
            completion?()
            return
        }

        Task {
            do {
                let retrieved = try await keychain.loadPasswordWithBiometrics(reason: "Unlock ExoCortex")
                await unlock(using: retrieved)
            } catch let error as KeychainServiceError {
                unlockError = error.localizedDescription
            } catch {
                unlockError = "Biometric unlock failed. Try your password."
            }
            completion?()
        }
    }

    /// Lock the log and clear sensitive data (saves before locking)
    func lock() {
        cancelFetch()
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
            refreshBiometricStatus()
        }
    }

    /// Store password in keychain with biometric protection for later retrieval
    func rememberPasswordInKeychain() {
        guard let pwd = activePassword, !pwd.isEmpty else {
            keychainStatus = "No password to save - unlock the app first"
            return
        }
        keychainStatus = "Saving..."
        Task {
            do {
                try await keychain.savePassword(pwd)
                // Small delay to ensure keychain is synced
                try? await Task.sleep(for: .milliseconds(100))
                // Verify the password was saved
                if keychain.hasStoredPassword() {
                    keychainStatus = "Password saved - biometric unlock enabled"
                } else {
                    keychainStatus = "Password saved but verification failed"
                }
                refreshBiometricStatus()
            } catch let error as KeychainServiceError {
                keychainStatus = error.localizedDescription
                refreshBiometricStatus()
            } catch {
                keychainStatus = "Failed: \(error.localizedDescription)"
                refreshBiometricStatus()
            }
        }
    }

    /// Remove stored password from keychain
    func clearKeychainPassword() {
        Task {
            defer { refreshBiometricStatus() }
            do {
                try await keychain.deletePassword()
                keychainStatus = "Saved password cleared"
            } catch {
                keychainStatus = "Failed to clear password"
            }
        }
    }

    // MARK: - API Key Management
    
    /// Load API key from keychain and set to LLMConfig
    func loadAPIKeyFromKeychain(initialLoad: Bool = false) async {
        do {
            if let key = try await keychain.loadAPIKey() {
                LLMConfig.apiKey = key
                self.apiKeyInput = key
                self.apiKeyStatus = "API Key loaded."
            } else if initialLoad {
                // Only set message on initial load if no key found (not an error)
                self.apiKeyStatus = "No API Key found."
            }
        } catch {
            self.apiKeyStatus = "Failed to load API Key: \(error.localizedDescription)"
        }
    }
    
    /// Save API key to keychain and set to LLMConfig
    func saveAPIKeyToKeychain() {
        Task {
            guard !apiKeyInput.isEmpty else {
                apiKeyStatus = "API Key cannot be empty."
                return
            }
            do {
                try await keychain.saveAPIKey(apiKeyInput)
                LLMConfig.apiKey = apiKeyInput
                apiKeyStatus = "API Key saved."
            } catch {
                apiKeyStatus = "Failed to save API Key: \(error.localizedDescription)"
            }
        }
    }
    
    /// Clear API key from keychain and LLMConfig
    func clearAPIKeyFromKeychain() {
        Task {
            do {
                try await keychain.clearAPIKey()
                LLMConfig.apiKey = "YOUR_API_KEY_HERE" // Reset to default placeholder
                apiKeyInput = ""
                apiKeyStatus = "API Key cleared."
            } catch {
                apiKeyStatus = "Failed to clear API Key: \(error.localizedDescription)"
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
    
    /// Cancel any ongoing AI fetch
    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
        isFetching = false
    }
    
    // MARK: - LLM Undo
    
    /// Push current state to undo stack before LLM edit
    private func pushLLMUndo(label: String) {
        llmUndoStack.append(LLMUndoEntry(
            fullText: fullText,
            label: label,
            timestamp: Date()
        ))
        if llmUndoStack.count > maxUndoLevels {
            llmUndoStack.removeFirst()
        }
        canUndoLLM = true
    }
    
    /// Undo the last LLM edit
    /// - Returns: True if undo was performed, false if stack was empty
    @discardableResult
    func undoLLM() -> Bool {
        guard let previous = llmUndoStack.popLast() else { return false }
        fullText = previous.fullText
        canUndoLLM = !llmUndoStack.isEmpty
        return true
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
            refreshBiometricStatus()
        } catch {
            unlockError = "Invalid password or data"
            isLocked = true
        }
        isLoading = false
    }

    private func textDidChange(oldValue: String) {
        // Cancel fetch if user types during fetch
        if isFetching {
            cancelFetch()
        }
        
        applyFilter()
        // Note: No more auto-save debounce - saves only on focus lost, lock, or app close
        // This conforms to Apple HID standards for document-based apps where saving
        // is explicit or tied to lifecycle events rather than every keystroke.
        detectAndProcessLLMQuery(oldText: oldValue, newText: fullText)
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
    
    
    
    // MARK: - LLM Configuration Management
    
    /// Load LLM model and system prompt from keychain on app startup
    private func loadLLMConfigFromKeychain() async {
        do {
            // Load model
            if let model = try await keychain.loadLLMModel() {
                LLMConfig.activeModel = model
            }
            
            // Load system prompt
            if let prompt = try await keychain.loadSystemPrompt() {
                LLMConfig.activeSystemPrompt = prompt
            }
        } catch {
            // Silently fail - use defaults
            print("Failed to load LLM config: \(error)")
        }
    }
    
    /// Save new LLM model to keychain and update config
    func saveLLMModel(_ model: String) {
        LLMConfig.activeModel = model
        Task {
            do {
                try await keychain.saveLLMModel(model)
            } catch {
                print("Failed to save LLM model: \(error)")
            }
        }
    }
    
    /// Save new system prompt to keychain and update config
    func saveSystemPrompt(_ prompt: String) {
        LLMConfig.activeSystemPrompt = prompt
        Task {
            do {
                try await keychain.saveSystemPrompt(prompt)
            } catch {
                print("Failed to save system prompt: \(error)")
            }
        }
    }
    
    // MARK: - LLM Query Processing (? queries)
    
    /// Detect and process new LLM queries (?? and <? >?)
    private func detectAndProcessLLMQuery(oldText: String, newText: String) {
        // Guard against fetch operations
        guard !isFetching else { return }
        
        // Check if a newline was added
        let oldNewlineCount = oldText.filter { $0 == "\n" }.count
        let newNewlineCount = newText.filter { $0 == "\n" }.count
        guard newNewlineCount > oldNewlineCount else { return }
        
        // Detect completed query
        guard let query = llmQueryDetector.detectCompletedQuery(oldText: oldText, newText: newText) else { return }
        
        // Process the query
        processLLMQuery(query)
    }
    
    /// Process a detected LLM query
    private func processLLMQuery(_ query: LLMQuery) {
        isFetching = true
        
        // Extract scope references
        let scopes = extractScopeReferences(from: query.promptText)
        
        // Get clean prompt (without @scopes)
        let cleanPrompt = extractCleanPrompt(from: query.promptText, scopes: scopes)
        
        guard !scopes.isEmpty else {
            fullText += "\n[LLM Error] Query requires at least one @scope reference like @2026-01-08\n"
            isFetching = false
            return
        }
        
        guard !cleanPrompt.isEmpty else {
            fullText += "\n[LLM Error] Empty prompt - add text with your question\n"
            isFetching = false
            return
        }
        
        // Resolve scopes
        let resolution = scopeResolver.resolveContext(from: query.promptText, in: fullText)
        
        if resolution.hasErrors {
           validationResult = ValidationResult(
               parseResult: ScopeParseResult(
                   blocks: resolution.blocks,
                   errors: resolution.validationErrors ?? []
               ),
               scope:  .lastDays(10)
           )
           showValidationSheet = true
           isFetching = false
           return
        }
        
        guard let context = resolution.context, !context.isEmpty else {
            fullText += "\n[LLM Error] No content found for scopes: \(scopes.joined(separator: ", "))\n"
            isFetching = false
            return
        }
        
        // Push undo checkpoint
        let labelPreview = String(cleanPrompt.prefix(40))
        pushLLMUndo(label: "Query: \(labelPreview)...")
        
        // Build message
        let message = """
        \(context)
        
        User instruction: \(cleanPrompt)
        """
        
        // Execute query
        fetchTask = Task { [weak self] in
            await self?.executeLLMQuery(message: message, isBlockQuery: query.isBlockQuery)
        }
    }
    
    /// Execute LLM query and append response
    private func executeLLMQuery(message: String, isBlockQuery: Bool) async {
        do {
            let response = try await openRouter.fetch(userMessage: message)
            
            // Append response
            let formatted = response.trimmingCharacters(in: .whitespacesAndNewlines)
            fullText += "\n\(formatted)\n"
            
            isFetching = false
        } catch {
            fullText += "\n[LLM Error] \(error.localizedDescription)\n"
            isFetching = false
        }
    }
    
    /// Extract clean prompt text without @scope references
    private func extractCleanPrompt(from text: String, scopes: [String]) -> String {
        var result = text
        for scope in scopes {
            result = result.replacingOccurrences(of: "@\(scope)", with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
