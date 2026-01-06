//
//  ContextResolver.swift
//  ExoCortex
//
//  Resolves @-references in AI prompts to actual content from the log.
//  Supports: @log, @today, @week, @last:N, @tag:xyz, @todos
//

import Foundation

// MARK: - Context Resolver

/// Resolves @-references in prompts to actual content from the log.
/// Extracts relevant context based on date, tags, or line counts.
struct ContextResolver {
    
    // MARK: - Types
    
    /// Result of resolving context references
    struct Resolution {
        /// Prompt with @references removed
        let cleanPrompt: String
        /// Extracted context, if any
        let context: String?
        /// Range in original fullText where context was extracted from (for edit mode)
        let contextRange: Range<String.Index>?
        /// Number of @scope references found in the original prompt
        let scopeCount: Int
        /// Whether the scope supports editing (contiguous range)
        let isEditableScope: Bool
    }
    
    /// Supported context reference patterns
    private enum Reference {
        case log            // @log - entire log
        case today          // @today - today's entries
        case week           // @week - last 7 days
        case last(Int)      // @last:N - last N lines
        case tag(String)    // @tag:xyz - lines with #xyz
        case todos          // @todos - all open todos
        
        init?(from string: String) {
            let lower = string.lowercased()
            switch lower {
            case "@log": self = .log
            case "@today": self = .today
            case "@week": self = .week
            case "@todos": self = .todos
            default:
                if lower.hasPrefix("@last:"), let count = Int(lower.dropFirst(6)) {
                    self = .last(count)
                } else if lower.hasPrefix("@tag:") {
                    self = .tag(String(lower.dropFirst(5)))
                } else {
                    return nil
                }
            }
        }
    }
    
    /// Result of extraction with range information
    private struct ExtractionResult {
        let text: String
        let range: Range<String.Index>?
    }
    
    // MARK: - Public Methods
    
    /// Resolve all @-references in a prompt
    /// - Parameters:
    ///   - prompt: The raw prompt text (after #p tag)
    ///   - fullText: The complete log content
    /// - Returns: Clean prompt and extracted context
    func resolve(prompt: String, fullText: String) -> Resolution {
        // Match @-references
        let pattern = #"@(?:log|today|week|todos|last:\d+|tag:\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return Resolution(cleanPrompt: prompt, context: nil, contextRange: nil, scopeCount: 0, isEditableScope: false)
        }
        
        let range = NSRange(prompt.startIndex..., in: prompt)
        let matches = regex.matches(in: prompt, range: range)
        
        guard !matches.isEmpty else {
            return Resolution(cleanPrompt: prompt, context: nil, contextRange: nil, scopeCount: 0, isEditableScope: false)
        }
        
        // Extract references and build context
        var contextParts: [String] = []
        var contextRanges: [Range<String.Index>] = []
        var cleanPrompt = prompt
        let scopeCount = matches.count
        
        // Process in reverse to preserve indices
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: prompt) else { continue }
            let refString = String(prompt[swiftRange])
            
            if let reference = Reference(from: refString) {
                let extraction = extractWithRange(reference: reference, from: fullText)
                if !extraction.text.isEmpty {
                    contextParts.insert(extraction.text, at: 0)
                    if let extractedRange = extraction.range {
                        contextRanges.insert(extractedRange, at: 0)
                    }
                }
            }
            cleanPrompt.removeSubrange(swiftRange)
        }
        
        // Clean up whitespace
        cleanPrompt = cleanPrompt
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
        
        // For edit mode: use first contiguous range only if single scope
        // Multiple scopes or non-contiguous (tag/todos) return nil range
        let primaryRange = contextRanges.count == 1 ? contextRanges.first : nil
        let isEditable = scopeCount == 1 && primaryRange != nil
        
        return Resolution(cleanPrompt: cleanPrompt, context: context, contextRange: primaryRange, scopeCount: scopeCount, isEditableScope: isEditable)
    }
    
    // MARK: - Extraction Methods
    
    private func extractWithRange(reference: Reference, from fullText: String) -> ExtractionResult {
        switch reference {
        case .log:
            let text = truncateIfNeeded(fullText, label: "Full log")
            return ExtractionResult(text: text, range: fullText.startIndex..<fullText.endIndex)
        case .today:
            return extractTodayWithRange(from: fullText)
        case .week:
            return extractWeekWithRange(from: fullText)
        case .last(let count):
            return extractLastLinesWithRange(count, from: fullText)
        case .tag(let tag):
            return extractByTagWithRange(tag, from: fullText)
        case .todos:
            return extractOpenTodosWithRange(from: fullText)
        }
    }
    
    private func extractTodayWithRange(from fullText: String) -> ExtractionResult {
        let today = DateFormatter.isoDate.string(from: Date())
        let lines = fullText.components(separatedBy: "\n")
        var startLineIndex: Int?
        var endLineIndex: Int?
        var todayLines: [String] = []
        var inTodaySection = false
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line is a date header (starts with --- or #)
            let isDateHeader = (trimmed.hasPrefix("---") || trimmed.hasPrefix("#")) && containsDatePattern(line)
            
            if line.contains(today) && isDateHeader {
                // Found a today date header - start/continue section
                inTodaySection = true
                if startLineIndex == nil { startLineIndex = index }
                todayLines.append(line)
                endLineIndex = index
            } else if inTodaySection {
                // Stop at any date header that isn't today, or any --- separator
                if isDateHeader || (trimmed.hasPrefix("---") && trimmed.count >= 3) {
                    // Hit a new section - stop here
                    break
                }
                todayLines.append(line)
                endLineIndex = index
            }
        }
        
        let result = todayLines.joined(separator: "\n")
        
        // Calculate range in original string
        var range: Range<String.Index>?
        if let start = startLineIndex, let end = endLineIndex {
            range = calculateRange(for: lines, startLine: start, endLine: end, in: fullText)
        }
        
        let text = result.isEmpty ? "[No entries for today]" : result
        return ExtractionResult(text: text, range: range)
    }
    
    private func extractWeekWithRange(from fullText: String) -> ExtractionResult {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let lines = fullText.components(separatedBy: "\n")
        var weekLines: [String] = []
        var currentDate: Date?
        var startLineIndex: Int?
        var endLineIndex: Int?
        
        for (index, line) in lines.enumerated() {
            if let date = extractDate(from: line) {
                currentDate = date
            }
            if let current = currentDate, current >= weekAgo {
                if startLineIndex == nil { startLineIndex = index }
                weekLines.append(line)
                endLineIndex = index
            }
        }
        
        let result = weekLines.joined(separator: "\n")
        
        var range: Range<String.Index>?
        if let start = startLineIndex, let end = endLineIndex {
            range = calculateRange(for: lines, startLine: start, endLine: end, in: fullText)
        }
        
        let text = result.isEmpty ? "[No entries in the last week]" : result
        return ExtractionResult(text: text, range: range)
    }
    
    private func extractLastLinesWithRange(_ count: Int, from fullText: String) -> ExtractionResult {
        let lines = fullText.components(separatedBy: "\n")
        let startIndex = max(0, lines.count - count)
        let lastLines = Array(lines.suffix(count))
        let result = lastLines.joined(separator: "\n")
        
        let range = calculateRange(for: lines, startLine: startIndex, endLine: lines.count - 1, in: fullText)
        
        return ExtractionResult(text: result, range: range)
    }
    
    private func extractByTagWithRange(_ tag: String, from fullText: String) -> ExtractionResult {
        // Note: Tag extraction returns non-contiguous lines, so range tracking is complex
        // For edit mode, we return nil range (not supported for non-contiguous selections)
        let lines = fullText.components(separatedBy: "\n")
        let pattern = "#\(tag)"
        let matchingLines = lines.filter { $0.lowercased().contains(pattern.lowercased()) }
        
        let result = matchingLines.joined(separator: "\n")
        let text = result.isEmpty ? "[No lines with #\(tag)]" : result
        
        // Non-contiguous - return nil range (edit mode won't work with this scope)
        return ExtractionResult(text: text, range: nil)
    }
    
    private func extractOpenTodosWithRange(from fullText: String) -> ExtractionResult {
        // Note: Todos are scattered throughout, so range tracking returns nil
        // For edit mode, we return nil range (not supported for non-contiguous selections)
        let lines = fullText.components(separatedBy: "\n")
        let todoLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("[ ]") || lower.contains("- [ ]")
        }
        
        let result = todoLines.joined(separator: "\n")
        let text = result.isEmpty ? "[No open todos found]" : result
        
        // Non-contiguous - return nil range
        return ExtractionResult(text: text, range: nil)
    }
    
    /// Calculate the range in fullText that corresponds to the given line indices
    private func calculateRange(for lines: [String], startLine: Int, endLine: Int, in fullText: String) -> Range<String.Index>? {
        guard startLine >= 0 && endLine < lines.count && startLine <= endLine else { return nil }
        
        var currentIndex = fullText.startIndex
        var startIndex: String.Index?
        var endIndex: String.Index?
        
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex == startLine {
                startIndex = currentIndex
            }
            
            // Move to end of current line
            let lineEndDistance = line.count
            guard let nextIndex = fullText.index(currentIndex, offsetBy: lineEndDistance, limitedBy: fullText.endIndex) else {
                break
            }
            
            if lineIndex == endLine {
                endIndex = nextIndex
                break
            }
            
            // Move past newline if not at end
            if nextIndex < fullText.endIndex {
                currentIndex = fullText.index(after: nextIndex)
            } else {
                currentIndex = nextIndex
            }
        }
        
        guard let start = startIndex, let end = endIndex else { return nil }
        return start..<end
    }
    
    // MARK: - Helpers
    
    private func truncateIfNeeded(_ text: String, label: String) -> String {
        // Conservative estimate: ~4 chars per token
        let maxChars = LLMConfig.maxTokens * 3
        
        if text.count > maxChars {
            let truncated = String(text.prefix(maxChars))
            return "\(label) (truncated):\n\(truncated)\n[... content truncated due to length ...]"
        }
        return "\(label):\n\(text)"
    }
    
    private func containsDatePattern(_ line: String) -> Bool {
        let patterns = [
            #"\d{4}-\d{2}-\d{2}"#,                                    // 2024-12-31
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,                             // 12/31/24
            #"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)"#  // Month names
        ]
        
        return patterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }
    
    private func extractDate(from line: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"\d{4}-\d{2}-\d{2}"#, "yyyy-MM-dd"),
            (#"\d{2}/\d{2}/\d{4}"#, "MM/dd/yyyy")
        ]
        
        for (pattern, format) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range, in: line) {
                let dateString = String(line[range])
                let formatter = DateFormatter()
                formatter.dateFormat = format
                if let date = formatter.date(from: dateString) {
                    return date
                }
            }
        }
        return nil
    }
}

// MARK: - Date Formatter Extension

private extension DateFormatter {
    /// ISO date format (yyyy-MM-dd)
    static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
