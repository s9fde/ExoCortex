//
//  ScopeBlock.swift
//  ExoCortex
//
//  Represents a single content block with its hierarchical scope path.
//

import Foundation

/// A block of content within the scope tree.
///
/// Each block represents a line or paragraph of content with its full scope path
/// (which tags/dates are active for this content).
///
/// Example:
/// ```
/// <<260108
///   <<meeting
///     - [ ] Task !!urgent
/// >>meeting
/// >>260108
/// ```
///
/// Results in a block with:
/// - dateTag: "260108"
/// - scopePath: ["260108", "meeting", "urgent"]
/// - lineScopes: ["urgent"]
/// - content: "- [ ] Task"
struct ScopeBlock: Identifiable {
    let id: UUID = UUID()
    
    /// The root date tag, if this block is within a date scope
    /// Example: "260108" from <<260108
    let dateTag: String?
    
    /// Full hierarchical scope path from root to leaf
    /// Example: ["260108", "meeting", "urgent"]
    let scopePath: [String]
    
    /// Line-only tags that apply to this specific line
    /// Subset of scopePath (the !!tags on this line)
    let lineScopes: [String]
    
    /// The actual content text (with markers removed)
    let content: String
    
    /// Line number in original document (1-indexed)
    let lineNumber: Int
    
    /// Character range in original text (for reference/editing)
    let contentRange: Range<String.Index>
    
    /// Depth in the hierarchy (0 = root, 1 = under date, 2 = under topic, etc.)
    var depth: Int {
        scopePath.count
    }
    
    /// All tags in this block (block scope + line tags)
    var allTags: Set<String> {
        Set(scopePath + lineScopes)
    }
}

// MARK: - Debugging

extension ScopeBlock: CustomStringConvertible {
    var description: String {
        let scopeStr = scopePath.joined(separator: " > ")
        return "Block[\(lineNumber)]: \(scopeStr) = \(content.prefix(50))..."
    }
}
