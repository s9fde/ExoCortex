//
//  LLMConfig.swift
//  ExoCortex
//
//  Configuration for LLM integration via OpenRouter.
//  Models and system prompts can be customized in Settings.
//

import Foundation

// MARK: - LLM Configuration

/// Configuration for LLM integration via OpenRouter.
/// API key, model, and system prompt can be configured at runtime via Settings.
enum LLMConfig {
    
    // MARK: - Default Values
    
    static let defaultModel = "anthropic/claude-opus-4.5"
    
    static let defaultSystemPrompt = """
        You are an intelligent editor and analyzer for a personal encrypted work log.
        
        The user has provided you with:
        1. Content from their work log, optionally scoped to specific dates or topics
        2. An instruction to analyze, transform, or edit this content
        
        Your responses should be:
        - Direct: Minimal preamble, get to the point
        - Scoped: Address only the given content
        - Focused: Make changes only as requested
        - Structured: Use formatting (bullets, headers) for clarity
        
        When asked to transform or edit content, apply the changes and return the result.
        When asked to analyze or extract information, provide your findings clearly.
        
        The user is tracking this in a personal system, so accuracy and clarity matter.
        """
    
    // MARK: - Runtime Configuration (Loaded from Keychain)
    
    /// Your OpenRouter API key - loaded from Keychain at runtime
    /// Set via Settings view → OpenRouter API Key
    nonisolated(unsafe) static var apiKey = "YOUR_API_KEY_HERE"
    
    /// Currently selected model (can be changed in Settings)
    /// Default: claude-opus-4.5
    nonisolated(unsafe) static var activeModel = defaultModel
    
    /// Currently active system prompt (can be customized in Settings)
    /// Default: defaultSystemPrompt
    nonisolated(unsafe) static var activeSystemPrompt = defaultSystemPrompt
    
    // MARK: - Fixed Configuration
    
    /// Maximum tokens for response (affects cost and response length)
    static let maxTokens = 12000
    
    // MARK: - OpenRouter Settings
    
    /// Base URL for OpenRouter API
    static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    
    /// App identifier for OpenRouter analytics
    static let appName = "ExoCortex"
    
    /// Referer URL for OpenRouter (required header)
    static let referer = "https://exocortex.app"
}
