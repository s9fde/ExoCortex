//
//  ScopeQuery.swift
//  ExoCortex
//
//  Query system for extracting content by scope tags.
//  Supports simple AND logic: @tag1 @tag2 matches blocks containing BOTH tags.
//

import Foundation

/// A query to extract blocks matching specific scope tags.
///
/// Uses simple AND logic:
/// - `@work` - all blocks with "work" tag
/// - `@260108` - all blocks from this date
/// - `@work @urgent` - all blocks with BOTH "work" AND "urgent" tags
///
/// Example:
/// ```
/// let query = ScopeQuery(from: "Summarize @260108 @work")
/// let matching = blocks.filter { query.matches($0) }
/// ```
struct ScopeQuery {
    /// Tags to match (lowercase, normalized)
    private(set) var tags: Set<String>
    
    /// Initialize from prompt string
    ///
    /// Extracts all @tagname tokens from the prompt.
    /// Returns nil if no tags found.
    init?(from prompt: String) {
        var queryTags: Set<String> = []
        
        let words = prompt.split(separator: " ", omittingEmptySubsequences: true)
        for word in words {
            if word.hasPrefix("@") {
                let tag = String(word.dropFirst()).lowercased()
                if !tag.isEmpty {
                    queryTags.insert(tag)
                }
            }
        }
        
        guard !queryTags.isEmpty else { return nil }
        self.tags = queryTags
    }
    
    /// Initialize with explicit tags
    init(tags: [String]) {
        self.tags = Set(tags.map { $0.lowercased() })
    }
    
    /// Check if block matches ALL query tags (AND logic)
    ///
    /// A block matches if all query tags are present in its scope path or line tags.
    /// - Parameter block: Block to check
    /// - Returns: true if block contains all query tags
    func matches(_ block: ScopeBlock) -> Bool {
        let blockTags = block.allTags
        return tags.isSubset(of: blockTags)
    }
    
    /// Extract clean prompt with all @tag references removed
    ///
    /// - Parameter text: Original prompt text
    /// - Returns: Cleaned prompt without @tags
    static func cleanPrompt(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        return words
            .filter { !$0.hasPrefix("@") }
            .joined(separator: " ")
    }
}

// MARK: - Extensions

extension ScopeQuery: CustomStringConvertible {
    var description: String {
        let tagsList = tags.sorted().joined(separator: ", ")
        return "ScopeQuery(tags: \(tagsList))"
    }
}
