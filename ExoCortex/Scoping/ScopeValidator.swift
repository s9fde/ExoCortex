//
//  ScopeValidator.swift
//  ExoCortex
//
//  Validation with configurable scope:
//  - lastDays(N): Check last N days only
//  - full: Check entire document
//

import Foundation

/// Validation scope options
enum ValidationScope {
    /// Last N days of content (for query-time checks)
    case lastDays(Int)
    
    /// Full document (for manual checks)
    case full
    
    /// Extract relevant text based on this scope
    func extract(from text: String) -> String {
        switch self {
        case .lastDays(let days):
            return extractLastDays(text, days: days)
        case .full:
            return text
        }
    }
    
    /// Extract last N days of content
    private func extractLastDays(_ text: String, days: Int) -> String {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let cutoffString = dateFormatter.string(from: cutoffDate)
        
        let lines = text.components(separatedBy: "\n")
        
        // Find first line with a date tag >= cutoff
        if let startIdx = lines.firstIndex(where: { line in
            // Check if line contains a date tag
            if let range = line.range(of: #"<<(\d{4}-\d{2}-\d{2})"#, options: .regularExpression) {
                let dateStr = String(line[range])
                    .replacingOccurrences(of: "<<", with: "")
                    .replacingOccurrences(of: ">>", with: "")
                return dateStr >= cutoffString
            }
            return false
        }) {
            return lines[startIdx...].joined(separator: "\n")
        }
        
        // Fallback: return last portion of document
        let fallbackLines = max(50, lines.count / 3)
        return lines.suffix(fallbackLines).joined(separator: "\n")
    }
}

/// Result of validation
struct ValidationResult {
    let parseResult: ScopeParseResult
    let scope: ValidationScope
    
    /// Whether parsing succeeded (no critical errors)
    var isValid: Bool {
        parseResult.isValid
    }
    
    /// Whether there are critical errors that should block operation
    var hasErrors: Bool {
        parseResult.errors.contains { $0.severity == .error }
    }
    
    /// All errors found
    var errors: [ScopeError] {
        parseResult.errors
    }
    
    /// Human-readable report
    var report: String {
        parseResult.errorReport
    }
}

/// Validator with configurable scope
class ScopeValidator {
    private let parser = ScopeParser()
    
    /// Validate with scope constraint
    ///
    /// - Parameters:
    ///   - text: Log text to validate
    ///   - scope: Validation scope (lastDays or full)
    /// - Returns: Validation result with errors
    func validate(text: String, scope: ValidationScope) -> ValidationResult {
        let scopedText = scope.extract(from: text)
        let parseResult = parser.parse(scopedText)
        
        return ValidationResult(parseResult: parseResult, scope: scope)
    }
    
    /// Validate last 10 days (typical query scope)
    ///
    /// Recommended for pre-query validation.
    func validateQueryScope(_ text: String) -> ValidationResult {
        validate(text: text, scope: .lastDays(10))
    }
    
    /// Validate entire document
    ///
    /// Recommended for manual checks.
    func validateFull(_ text: String) -> ValidationResult {
        validate(text: text, scope: .full)
    }
}
