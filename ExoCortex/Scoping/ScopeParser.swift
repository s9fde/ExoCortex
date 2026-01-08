//
//  ScopeParser.swift
//  ExoCortex
//
//  Core parser for scope syntax: <<tag, >>tag, !!tag
//  Uses date-root tree architecture where dates are always roots.
//

import Foundation

/// Parses log text into hierarchical scope blocks with validation.
///
/// Scope syntax:
/// - `<<tagname` - opens a scope block (dates are roots)
/// - `>>tagname` - closes the matching scope block
/// - `!!tagname` - line-only tag (no closing needed)
///
/// Architecture: Date-root tree
/// - Dates (YYYY-MM-DD format) are always tree roots
/// - All other tags must nest within a date
/// - Tags cannot cross date boundaries
struct ScopeParser {
    /// Parse full log text into blocks with validation
    func parse(_ text: String) -> ScopeParseResult {
        let tokens = tokenize(text)
        let lines = text.components(separatedBy: "\n")
        let (blocks, errors) = buildTree(from: tokens, lines: lines, fullText: text)
        
        return ScopeParseResult(blocks: blocks, errors: errors)
    }
    
    // MARK: - Private: Tokenization
    
    /// Token representing a scope marker
    private struct Token {
        enum Kind {
            case blockOpen(String)
            case blockClose(String)
            case lineTag(String)
        }
        
        let kind: Kind
        let line: Int
        let col: Int
        
        var tagName: String {
            switch kind {
            case .blockOpen(let name), .blockClose(let name), .lineTag(let name):
                return name.lowercased()
            }
        }
    }
    
    /// Extract all scope markers from text
    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let lines = text.components(separatedBy: "\n")
        
        for (lineIdx, line) in lines.enumerated() {
            let lineNum = lineIdx + 1
            var col = 1
            var idx = line.startIndex
            
            while idx < line.endIndex {
                let remaining = String(line[idx...])
                
                // Try to match <<tagname
                if remaining.hasPrefix("<<") {
                    if let (tagName, endIdx) = extractTagName(from: remaining, after: 2) {
                        tokens.append(Token(kind: .blockOpen(tagName), line: lineNum, col: col))
                        let offset = endIdx.utf16Offset(in: remaining)
                        idx = line.index(idx, offsetBy: offset, limitedBy: line.endIndex) ?? line.endIndex
                        col += offset
                        continue
                    }
                }
                
                // Try to match >>tagname
                if remaining.hasPrefix(">>") {
                    if let (tagName, endIdx) = extractTagName(from: remaining, after: 2) {
                        tokens.append(Token(kind: .blockClose(tagName), line: lineNum, col: col))
                        let offset = endIdx.utf16Offset(in: remaining)
                        idx = line.index(idx, offsetBy: offset, limitedBy: line.endIndex) ?? line.endIndex
                        col += offset
                        continue
                    }
                }
                
                // Try to match !!tagname
                if remaining.hasPrefix("!!") {
                    if let (tagName, endIdx) = extractTagName(from: remaining, after: 2) {
                        tokens.append(Token(kind: .lineTag(tagName), line: lineNum, col: col))
                        let offset = endIdx.utf16Offset(in: remaining)
                        idx = line.index(idx, offsetBy: offset, limitedBy: line.endIndex) ?? line.endIndex
                        col += offset
                        continue
                    }
                }
                
                idx = line.index(after: idx)
                col += 1
            }
        }
        
        return tokens
    }
    
    /// Extract tag name starting from position after the prefix (<<, >>, !!).
    /// Returns (tagName, endIndex) if valid, nil if invalid.
    private func extractTagName(from str: String, after offset: Int) -> (String, String.Index)? {
        guard offset < str.count else { return nil }
        let startIdx = str.index(str.startIndex, offsetBy: offset)
        var endIdx = startIdx
        
        // First character must be a letter
        guard endIdx < str.endIndex, str[endIdx].isLetter else { return nil }
        
        // Consume valid tag name characters
        while endIdx < str.endIndex {
            let char = str[endIdx]
            if char.isLetter || char.isNumber || char == "_" || char == "-" {
                endIdx = str.index(after: endIdx)
            } else {
                break
            }
        }
        
        let tagName = String(str[startIdx..<endIdx])
        return (tagName, endIdx)
    }
    
    // MARK: - Private: Tree Building
    
    /// Build scope tree and validate
    private func buildTree(
        from tokens: [Token],
        lines: [String],
        fullText: String
    ) -> (blocks: [ScopeBlock], errors: [ScopeError]) {
        var blockStack: [(tag: String, line: Int)] = []
        var currentDate: String? = nil
        var blocks: [ScopeBlock] = []
        var errors: [ScopeError] = []
        
        for (lineIdx, line) in lines.enumerated() {
            let lineNum = lineIdx + 1
            let lineTokens = tokens.filter { $0.line == lineNum }
            let lineTagNames = lineTokens
                .compactMap { token -> String? in
                    if case .lineTag(let name) = token.kind {
                        return name.lowercased()
                    }
                    return nil
                }
            
            // Process block markers
            for token in lineTokens {
                let tagName = token.tagName
                
                switch token.kind {
                case .blockOpen(let originalName):
                    if tagName.isDateTag() {
                        // Date tag - always a root
                        if let prevDate = currentDate {
                            // Previous date not closed, auto-close (could be error or warning)
                        }
                        currentDate = tagName
                        blockStack.append((tagName, lineNum))
                    } else {
                        // Regular tag
                        if currentDate == nil {
                            // Tag opened outside date - error
                            errors.append(.tagCrossDate(
                                tag: tagName,
                                line: lineNum,
                                col: token.col,
                                closedDate: ""
                            ))
                        } else {
                            blockStack.append((tagName, lineNum))
                        }
                    }
                    
                case .blockClose(let originalName):
                    if let last = blockStack.last, last.tag == tagName {
                        blockStack.removeLast()
                        
                        // If closing a date, clear current date context
                        if tagName.isDateTag() {
                            currentDate = nil
                        }
                    } else if let expected = blockStack.last {
                        errors.append(.mismatchedClose(
                            expected: expected.tag,
                            found: tagName,
                            line: lineNum,
                            col: token.col
                        ))
                    } else {
                        errors.append(.unopenedClose(
                            tag: tagName,
                            line: lineNum,
                            col: token.col
                        ))
                    }
                    
                case .lineTag:
                    break  // Handled below
                }
            }
            
            // Create block for content
            let content = cleanContent(line)
            
            if !content.trimmingCharacters(in: .whitespaces).isEmpty {
                let scopePath = blockStack.map { $0.tag } + lineTagNames
                let block = ScopeBlock(
                    dateTag: currentDate,
                    scopePath: scopePath,
                    lineScopes: lineTagNames,
                    content: content,
                    lineNumber: lineNum,
                    contentRange: line.startIndex..<line.endIndex
                )
                blocks.append(block)
            }
        }
        
        // EOF validation
        if !blockStack.isEmpty {
            let unclosed = blockStack.map { UnclosedTag(name: $0.tag, openedAt: $0.line) }
            errors.append(.unclosedAtEOF(tags: unclosed))
        }
        
        return (blocks, errors)
    }
    
    /// Remove scope markers from a line
    private func cleanContent(_ line: String) -> String {
        var result = line
        
        // Remove all markers: <<tag, >>tag, !!tag
        let patterns = [
            ("<<[a-zA-Z][a-zA-Z0-9_-]*", ""),
            (">>[a-zA-Z][a-zA-Z0-9_-]*", ""),
            ("!![a-zA-Z][a-zA-Z0-9_-]*", "")
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Extensions

extension String {
    /// Check if this string is a valid date tag (YYYY-MM-DD format)
    func isDateTag() -> Bool {
        let pattern = "^\\d{4}-\\d{2}-\\d{2}$"
        return range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Result Type

/// Result of parsing a log text
struct ScopeParseResult {
    /// Successfully parsed blocks
    let blocks: [ScopeBlock]
    
    /// All validation errors found
    let errors: [ScopeError]
    
    /// Whether parsing succeeded (no critical errors)
    var isValid: Bool {
        errors.filter { $0.severity == .error }.isEmpty
    }
    
    /// Human-readable error report
    var errorReport: String {
        let sorted = errors.sorted { a, b in
            // Errors come first, then warnings
            if a.severity == .error && b.severity != .error {
                return true
            }
            if a.severity != .error && b.severity == .error {
                return false
            }
            // Same severity, sort by line number
            return a.line < b.line
        }
        return sorted.map { $0.message }.joined(separator: "\n")
    }
}
