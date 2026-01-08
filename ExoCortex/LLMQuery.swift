//
//  LLMQuery.swift
//  ExoCortex
//
//  Data structures for LLM query system.
//  Queries handle both single-line (??) and multi-line (<? >?) formats.
//

import Foundation

/// Represents a detected LLM query (single-line or block)
struct LLMQuery {
    /// The instruction/prompt text (with embedded @scope references)
    let promptText: String
    
    /// Line number where query begins
    let startLineNumber: Int
    
    /// Is this a block query (<? >?) vs single-line (??)
    let isBlockQuery: Bool
    
    /// For block queries: line number of closing >>
    let blockEndLineNumber: Int?
    
    /// Unique identifier
    let id: UUID = UUID()
}

/// Resolved query with scope context and validation
struct ResolvedLLMQuery {
    /// The original query
    let query: LLMQuery
    
    /// Extracted scope references (["2026-01-08", "work"])
    let scopeReferences: [String]
    
    /// Combined content from all matched scopes
    let context: String
    
    /// Range of context in fullText (for reference)
    let contextRange: Range<String.Index>?
    
    /// Whether resolution succeeded
    let isValid: Bool
    
    /// Error messages if !isValid
    let errors: [String]
    
    /// Extract clean prompt with @scope references removed
    var cleanPrompt: String {
        var result = query.promptText
        for scope in scopeReferences {
            result = result.replacingOccurrences(of: "@\(scope)", with: "").trimmingCharacters(in: CharacterSet.whitespaces)
        }
        return result.trimmingCharacters(in: CharacterSet.whitespaces)
    }
}

// MARK: - Query Detection

/// Detects single-line (??) and block (<? >?) LLM queries
struct LLMQueryDetector {
    
    /// Detect all queries in text (both single-line and block)
    /// - Parameter text: Full log text
    /// - Returns: Array of detected LLMQuery objects
    func detectQueries(in text: String) -> [LLMQuery] {
        var queries: [LLMQuery] = []
        let lines = text.components(separatedBy: "\n")
        
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for block query opening
            if trimmed.hasPrefix("<?") && trimmed.hasSuffix("<?") {
                // Parse block query
                if let blockQuery = parseBlockQuery(startLine: i, in: lines) {
                    queries.append(blockQuery)
                    i = blockQuery.blockEndLineNumber ?? (i + 1)
                    continue
                }
            }
            
            // Check for single-line query
            if trimmed.hasPrefix("??") {
                let prompt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !prompt.isEmpty {
                    let query = LLMQuery(
                        promptText: prompt,
                        startLineNumber: i,
                        isBlockQuery: false,
                        blockEndLineNumber: nil
                    )
                    queries.append(query)
                }
            }
            
            i += 1
        }
        
        return queries
    }
    
    /// Parse a block query starting at given line
    private func parseBlockQuery(startLine: Int, in lines: [String]) -> LLMQuery? {
        var content: [String] = []
        var endLine: Int?
        
        // Start after opening <?
        for i in (startLine + 1)..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for closing >>
            if trimmed.hasPrefix(">>") && trimmed.hasSuffix(">>") {
                endLine = i
                break
            }
            
            content.append(line)
        }
        
        guard let endLine = endLine else { return nil }
        
        let promptText = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promptText.isEmpty else { return nil }
        
        return LLMQuery(
            promptText: promptText,
            startLineNumber: startLine,
            isBlockQuery: true,
            blockEndLineNumber: endLine
        )
    }
    
    /// Detect if the last query in text was just completed (user pressed Enter)
    /// - Parameters:
    ///   - oldText: Previous text state
    ///   - newText: Current text state
    /// - Returns: Completed query if one was just finished, nil otherwise
    func detectCompletedQuery(oldText: String, newText: String) -> LLMQuery? {
        // Check if a newline was added
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")
        
        guard newLines.count > oldLines.count else { return nil }
        
        // Get all queries in new text
        let queries = detectQueries(in: newText)
        
        // Check if the last query is "new" (not in old text)
        for query in queries.reversed() {
            if query.startLineNumber >= oldLines.count - 1 {
                // This query is new or we're at end of a new block
                return query
            }
        }
        
        return nil
    }
}

// MARK: - Scope Reference Extraction

/// Extract @scope references from instruction text
func extractScopeReferences(from text: String) -> [String] {
    var scopes: [String] = []
    let pattern = "@([\\w-]+)"
    
    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let scope = String(text[range])
                if !scopes.contains(scope) {
                    scopes.append(scope)
                }
            }
        }
    }
    
    return scopes
}
