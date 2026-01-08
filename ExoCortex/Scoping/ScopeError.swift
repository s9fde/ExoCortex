//
//  ScopeError.swift
//  ExoCortex
//
//  Validation errors that can occur during scope parsing.
//

import Foundation

/// Represents an unclosed tag info
struct UnclosedTag: Equatable {
    let name: String
    let openedAt: Int
}

/// Errors that can occur during scope parsing and validation.
enum ScopeError: Identifiable, Equatable {
    var id: String {
        "\(line)-\(col ?? 0)"
    }
    
    /// Tag opened after a date was closed (violates date-root tree)
    case tagCrossDate(tag: String, line: Int, col: Int, closedDate: String)
    
    /// Close tag >>tag without matching opening <<tag
    case unopenedClose(tag: String, line: Int, col: Int)
    
    /// Close tag >>tag doesn't match the most recent open tag
    case mismatchedClose(expected: String, found: String, line: Int, col: Int)
    
    /// One or more tags opened but never closed at EOF
    case unclosedAtEOF(tags: [UnclosedTag])
    
    /// Invalid tag name (doesn't match valid pattern)
    case invalidTagName(name: String, line: Int, col: Int)
    
    /// Severity level for this error
    var severity: ErrorSeverity {
        switch self {
        case .unclosedAtEOF:
            .warning  // Can auto-close
        case .duplicateOpen:
            .warning  // Likely user forgot close
        default:
            .error    // Fatal issue
        }
    }
    
    /// Adds support for another error type (placeholder for future)
    case duplicateOpen(tag: String, line: Int, col: Int, previousLine: Int)
    
    /// Line number where error occurred
    var line: Int {
        switch self {
        case .tagCrossDate(_, let line, _, _): return line
        case .unopenedClose(_, let line, _): return line
        case .mismatchedClose(_, _, let line, _): return line
        case .unclosedAtEOF: return 0  // End of file
        case .invalidTagName(_, let line, _): return line
        case .duplicateOpen(_, let line, _, _): return line
        }
    }
    
    /// Column number where error occurred (if applicable)
    var col: Int? {
        switch self {
        case .tagCrossDate(_, _, let col, _): return col
        case .unopenedClose(_, _, let col): return col
        case .mismatchedClose(_, _, _, let col): return col
        case .invalidTagName(_, _, let col): return col
        case .duplicateOpen(_, _, let col, _): return col
        default: return nil
        }
    }
    
    /// Human-readable error message
    var message: String {
        switch self {
        case let .tagCrossDate(tag, line, col, date):
            return "Line \(line):\(col): Tag '\(tag)' crosses date boundary (date '\(date)' was closed)"
        case let .unopenedClose(tag, line, col):
            return "Line \(line):\(col): Unopened close >>\(tag)"
        case let .mismatchedClose(expected, found, line, col):
            return "Line \(line):\(col): Expected >>\(expected), found >>\(found)"
        case let .unclosedAtEOF(tags):
            let names = tags.map { $0.name }.joined(separator: ", ")
            return "EOF: Unclosed tags: \(names)"
        case let .invalidTagName(name, line, col):
            return "Line \(line):\(col): Invalid tag name '\(name)'"
        case let .duplicateOpen(tag, line, col, previousLine):
            return "Line \(line):\(col): Tag '\(tag)' opened again without closing (previously opened at line \(previousLine))"
        }
    }
    
    /// Friendly explanation of the error
    var details: String? {
        switch self {
        case .tagCrossDate:
            return "All tags must be nested within a date block. Dates cannot cross."
        case .unopenedClose:
            return "Close tag without matching open tag."
        case .mismatchedClose:
            return "Close tag doesn't match the most recent open tag."
        case .unclosedAtEOF:
            return "All open tags must be closed before end of file."
        case .invalidTagName:
            return "Tag names must start with a letter and contain only letters, numbers, hyphens, and underscores."
        case .duplicateOpen:
            return "Tag opened twice without closing in between."
        }
    }
}

/// Error severity levels
enum ErrorSeverity {
    /// Warning level - can be auto-fixed or ignored
    case warning
    
    /// Error level - must be fixed for valid parse
    case error
}
