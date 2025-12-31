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
        didSet { textDidChange(oldValue: oldValue) }
    }
    @Published var filterText: String = "" {
        didSet { applyFilter() }
    }
    @Published var filteredLines: [LineItem] = []
    @Published var savedFilters: [String] = []
    @Published var unlockError: String?
    @Published var filterError: String?
    @Published var saveStatus: SaveStatus = .idle
    
    /// Indicates AI is currently streaming a response
    @Published var isStreaming: Bool = false

    private let repository: LogRepository
    private let keychain: KeychainService
    private let parser = TagQueryParser()
    private let openRouter = OpenRouterService()
    private let contextResolver = ContextResolver()
    
    private var activePassword: String?
    private var saveWorkItem: DispatchWorkItem?
    private var streamTask: Task<Void, Never>?
    private var previousText: String = ""

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
        cancelStream()
        saveWorkItem?.cancel()
        activePassword = nil
        password = ""
        fullText = ""
        previousText = ""
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
    
    /// Cancel any ongoing stream (user started typing)
    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    // MARK: - Private

    private func unlock(using password: String) async {
        await MainActor.run { self.isLoading = true }
        do {
            let text = try await repository.load(password: password)
            await MainActor.run {
                self.activePassword = password
                self.previousText = text
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

    private func textDidChange(oldValue: String) {
        // Cancel stream if user types during streaming
        if isStreaming && !isStreamingAppend {
            cancelStream()
        }
        
        applyFilter()
        scheduleAutosave()
        
        // Check for prompt trigger (newline after #p line)
        detectAndProcessPrompt(oldText: oldValue, newText: fullText)
        
        previousText = fullText
    }
    
    /// Flag to differentiate streaming appends from user edits
    private var isStreamingAppend = false

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
    
    // MARK: - LLM Prompt Detection & Processing
    
    private func detectAndProcessPrompt(oldText: String, newText: String) {
        // Only trigger if a newline was just added
        guard newText.count > oldText.count else { return }
        guard newText.hasSuffix("\n") || newText.last?.isNewline == true else { return }
        
        // Don't trigger if already streaming
        guard !isStreaming else { return }
        
        let lines = newText.components(separatedBy: "\n")
        
        // Find the line that was just completed (second to last, since last is empty after newline)
        guard lines.count >= 2 else { return }
        let completedLine = lines[lines.count - 2]
        
        // Check if the completed line starts with #p
        let trimmed = completedLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(LLMConfig.promptTag.lowercased()) else { return }
        
        // Extract prompt text (everything after #p)
        let promptIndex = trimmed.index(trimmed.startIndex, offsetBy: LLMConfig.promptTag.count)
        let promptText = String(trimmed[promptIndex...]).trimmingCharacters(in: .whitespaces)
        
        // Don't process empty prompts
        guard !promptText.isEmpty else { return }
        
        // Start processing the prompt
        processPrompt(promptText)
    }
    
    private func processPrompt(_ rawPrompt: String) {
        // Cancel any existing stream
        cancelStream()
        
        // Resolve context references
        let resolution = contextResolver.resolve(prompt: rawPrompt, fullText: fullText)
        
        // Build the full message with context
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
        
        // Start streaming task
        streamTask = Task { [weak self] in
            await self?.streamResponse(message: fullMessage)
        }
    }
    
    private func streamResponse(message: String) async {
        do {
            let stream = await openRouter.stream(userMessage: message)
            
            for try await chunk in stream {
                // Check for cancellation
                if Task.isCancelled { break }
                
                await MainActor.run {
                    self.appendToText(chunk)
                }
            }
            
            // Stream completed successfully
            await MainActor.run {
                self.appendToText("\n---\n")
                self.isStreaming = false
            }
            
        } catch {
            // Handle error
            await MainActor.run {
                // Find and update the response line to show error
                let errorMessage = error.localizedDescription
                self.appendToText("\n\(LLMConfig.errorTag) \(errorMessage)\n---\n")
                self.isStreaming = false
            }
        }
    }
    
    /// Append text without triggering prompt detection
    private func appendToText(_ text: String) {
        isStreamingAppend = true
        fullText += text
        isStreamingAppend = false
    }
}
