import Foundation

/// Resolves @-references in prompts to actual content from the log
struct ContextResolver {
    
    /// Result of resolving context references
    struct Resolution {
        let cleanPrompt: String  // Prompt with @references removed
        let context: String?     // Extracted context, if any
    }
    
    /// Supported context reference patterns
    private enum Reference {
        case log           // @log - entire log
        case today         // @today - today's entries
        case week          // @week - last 7 days
        case last(Int)     // @last:N - last N lines
        case tag(String)   // @tag:xyz - lines with #xyz
        case todos         // @todos - all open todos
        
        init?(from string: String) {
            let lower = string.lowercased()
            switch lower {
            case "@log":
                self = .log
            case "@today":
                self = .today
            case "@week":
                self = .week
            case "@todos":
                self = .todos
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
    
    /// Resolve all @-references in a prompt
    /// - Parameters:
    ///   - prompt: The raw prompt text (after #p tag)
    ///   - fullText: The complete log content
    /// - Returns: Clean prompt and extracted context
    func resolve(prompt: String, fullText: String) -> Resolution {
        // Find all @references in the prompt
        let pattern = #"@(?:log|today|week|todos|last:\d+|tag:\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return Resolution(cleanPrompt: prompt, context: nil)
        }
        
        let range = NSRange(prompt.startIndex..., in: prompt)
        let matches = regex.matches(in: prompt, range: range)
        
        guard !matches.isEmpty else {
            return Resolution(cleanPrompt: prompt, context: nil)
        }
        
        // Extract references and build context
        var contextParts: [String] = []
        var cleanPrompt = prompt
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: prompt) else { continue }
            let refString = String(prompt[swiftRange])
            
            if let reference = Reference(from: refString) {
                let extracted = extract(reference: reference, from: fullText)
                if !extracted.isEmpty {
                    contextParts.insert(extracted, at: 0)
                }
            }
            
            // Remove the reference from the prompt
            cleanPrompt.removeSubrange(swiftRange)
        }
        
        // Clean up extra whitespace
        cleanPrompt = cleanPrompt
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        
        // Build context string
        let context = contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
        
        return Resolution(cleanPrompt: cleanPrompt, context: context)
    }
    
    // MARK: - Private Extraction Methods
    
    private func extract(reference: Reference, from fullText: String) -> String {
        switch reference {
        case .log:
            return truncateIfNeeded(fullText, label: "Full log")
            
        case .today:
            return extractToday(from: fullText)
            
        case .week:
            return extractWeek(from: fullText)
            
        case .last(let count):
            return extractLastLines(count, from: fullText)
            
        case .tag(let tag):
            return extractByTag(tag, from: fullText)
            
        case .todos:
            return extractOpenTodos(from: fullText)
        }
    }
    
    private func extractToday(from fullText: String) -> String {
        let today = DateFormatter.logDate.string(from: Date())
        let lines = fullText.components(separatedBy: "\n")
        var todayLines: [String] = []
        var inTodaySection = false
        
        for line in lines {
            // Check if line contains today's date (common formats)
            if line.contains(today) || line.contains(formattedDate(Date())) {
                inTodaySection = true
                todayLines.append(line)
            } else if inTodaySection {
                // Stop at next date header (lines starting with # followed by date pattern)
                if line.hasPrefix("#") && containsDatePattern(line) && !line.contains(today) {
                    break
                }
                todayLines.append(line)
            }
        }
        
        let result = todayLines.joined(separator: "\n")
        return result.isEmpty ? "[No entries for today]" : truncateIfNeeded(result, label: "Today's entries")
    }
    
    private func extractWeek(from fullText: String) -> String {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let lines = fullText.components(separatedBy: "\n")
        var weekLines: [String] = []
        var currentDate: Date?
        
        for line in lines {
            if let date = extractDate(from: line) {
                currentDate = date
            }
            
            if let current = currentDate, current >= weekAgo {
                weekLines.append(line)
            }
        }
        
        let result = weekLines.joined(separator: "\n")
        return result.isEmpty ? "[No entries in the last week]" : truncateIfNeeded(result, label: "Last 7 days")
    }
    
    private func extractLastLines(_ count: Int, from fullText: String) -> String {
        let lines = fullText.components(separatedBy: "\n")
        let lastLines = lines.suffix(count)
        let result = lastLines.joined(separator: "\n")
        return truncateIfNeeded(result, label: "Last \(count) lines")
    }
    
    private func extractByTag(_ tag: String, from fullText: String) -> String {
        let lines = fullText.components(separatedBy: "\n")
        let tagPattern = "#\(tag)"
        let matchingLines = lines.filter { $0.lowercased().contains(tagPattern.lowercased()) }
        
        let result = matchingLines.joined(separator: "\n")
        return result.isEmpty ? "[No lines with #\(tag)]" : truncateIfNeeded(result, label: "Lines with #\(tag)")
    }
    
    private func extractOpenTodos(from fullText: String) -> String {
        let lines = fullText.components(separatedBy: "\n")
        let todoLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("[ ]") || lower.contains("- [ ]")
        }
        
        let result = todoLines.joined(separator: "\n")
        return result.isEmpty ? "[No open todos found]" : "Open todos:\n\(result)"
    }
    
    // MARK: - Helpers
    
    private func truncateIfNeeded(_ text: String, label: String) -> String {
        // Rough estimate: ~4 chars per token, leave room for prompt
        let maxChars = LLMConfig.maxTokens * 3  // Conservative estimate
        
        if text.count > maxChars {
            let truncated = String(text.prefix(maxChars))
            return "\(label) (truncated):\n\(truncated)\n[... content truncated due to length ...]"
        }
        return "\(label):\n\(text)"
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func containsDatePattern(_ line: String) -> Bool {
        // Match common date patterns: 2024-12-31, Dec 31, December 31, etc.
        let patterns = [
            #"\d{4}-\d{2}-\d{2}"#,  // 2024-12-31
            #"\d{1,2}/\d{1,2}/\d{2,4}"#,  // 12/31/24 or 12/31/2024
            #"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}"#  // Dec 31 or December 31
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return true
            }
        }
        return false
    }
    
    private func extractDate(from line: String) -> Date? {
        // Try to parse date from line (for week extraction)
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
    static let logDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
