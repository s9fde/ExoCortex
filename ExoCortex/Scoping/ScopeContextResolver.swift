//
//  ScopeContextResolver.swift
//  ExoCortex
//
//  Integration layer for scope-based context extraction for LLM queries.
//  Replaces the old ContextResolver.
//

import Foundation

/// Result of context resolution for LLM query
struct ScopeContextResolution {
    /// Prompt with @tag references removed (clean for LLM)
    let cleanPrompt: String
    
    /// Extracted context matching @tags (or full log if no @tags)
    let context: String?
    
    /// Blocks that were matched (for reference)
    let blocks: [ScopeBlock]
    
    /// Whether parsing was valid
    let isValid: Bool
    
    /// Validation errors if any
    let validationErrors: [ScopeError]?
    
    /// Whether there are critical errors
    var hasErrors: Bool {
        validationErrors?.contains { $0.severity == .error } ?? false
    }
    
    /// Error report if invalid
    var errorReport: String {
        validationErrors?.map { $0.message }.joined(separator: "\n") ?? ""
    }
}

/// Resolver for extracting LLM context using scope queries
class ScopeContextResolver {
    private let parser = ScopeParser()
    private let validator = ScopeValidator()
    
    /// Extract context for LLM query with validation
    ///
    /// Flow:
    /// 1. Parse @tag references from prompt
    /// 2. Validate last 10 days (pre-query validation)
    /// 3. If valid, extract matching blocks
    /// 4. Return clean prompt + context
    ///
    /// - Parameters:
    ///   - prompt: Raw prompt with potential @tags
    ///   - logText: Full log text
    /// - Returns: Context resolution with clean prompt and extracted content
    func resolveContext(from prompt: String, in logText: String) -> ScopeContextResolution {
        // Extract @tag queries from prompt
        if let query = ScopeQuery(from: prompt) {
            // Query with @tags - validate before extracting
            let validation = validator.validateQueryScope(logText)
            
            if validation.hasErrors {
                // Errors found - return early with error info
                return ScopeContextResolution(
                    cleanPrompt: prompt,
                    context: nil,
                    blocks: [],
                    isValid: false,
                    validationErrors: validation.errors
                )
            }
            
            // Parse full log and extract matching blocks
            let parseResult = parser.parse(logText)
            let matchingBlocks = parseResult.blocks.filter { query.matches($0) }
            
            // Build context from matching blocks
            let context = matchingBlocks
                .sorted { $0.lineNumber < $1.lineNumber }
                .map { $0.content }
                .joined(separator: "\n\n")
            
            // Clean prompt (remove @tags)
            let cleanPrompt = ScopeQuery.cleanPrompt(prompt)
            
            return ScopeContextResolution(
                cleanPrompt: cleanPrompt,
                context: context.isEmpty ? nil : context,
                blocks: matchingBlocks,
                isValid: parseResult.isValid,
                validationErrors: parseResult.errors.isEmpty ? nil : parseResult.errors
            )
        } else {
            // No @tags in prompt - use full log as context
            return ScopeContextResolution(
                cleanPrompt: prompt,
                context: logText,
                blocks: [],
                isValid: true,
                validationErrors: nil
            )
        }
    }
    
    /// Extract context without validation (for manual queries)
    ///
    /// Directly queries the log without pre-validation.
    /// Use only after manual validation has been done.
    func extractContext(matching query: ScopeQuery, from logText: String) -> String {
        let parseResult = parser.parse(logText)
        let matchingBlocks = parseResult.blocks.filter { query.matches($0) }
        
        return matchingBlocks
            .sorted { $0.lineNumber < $1.lineNumber }
            .map { $0.content }
            .joined(separator: "\n\n")
    }
    
    /// Get scope path for cursor position (for breadcrumb display)
    func getScopePath(at position: Int = 0, in logText: String) -> [String] {
        let parseResult = parser.parse(logText)
        
        // Find block at or near this position
        // For now, return empty - would require character position tracking
        return []
    }
}
