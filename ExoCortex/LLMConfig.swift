//
//  LLMConfig.swift
//  ExoCortex
//
//  Configuration constants for LLM integration via OpenRouter.
//  Edit these values before compiling to customize behavior.
//

import Foundation

// MARK: - LLM Configuration

/// Configuration for LLM integration via OpenRouter.
/// Edit these values before compiling to customize behavior.
enum LLMConfig {
    
    // MARK: - API Configuration
    
    /// Your OpenRouter API key - loaded from Keychain at runtime
    /// Set via Settings view → OpenRouter API Key
    /// Uses keychain for secure storage without environment variables
    nonisolated(unsafe) static var apiKey = "YOUR_API_KEY_HERE"
    
    /// The model to use for AI responses
    /// Options: "anthropic/claude-opus-4.5", "anthropic/claude-sonnet-4", etc.
    static let model = "anthropic/claude-opus-4.5"
    
    /// Maximum tokens for response (affects cost and response length)
    static let maxTokens = 12000
    
    // MARK: - Prompt Tags
    
    /// Tag that triggers a read-only prompt (appends response below)
    /// Legacy tag, equivalent to readOnlyTag
    static let promptTag = "#p"
    
    /// Tag for read-only prompts (appends response below)
    static let readOnlyTag = "#ro"
    
    /// Tag for edit prompts (replaces scoped section with LLM output)
    static let editTag = "#do"
    
    /// Tag prepended to AI responses for visual identification
    static let responseTag = "#opus45"
    
    /// Tag prepended to error messages
    static let errorTag = "#error"
    
    // MARK: - System Prompt
    
    /// System prompt sent with every request to set AI behavior
    static let systemPrompt = """
        You are a helpful assistant integrated into a personal encrypted work log called ExoCortex.
        Respond concisely in markdown format. Use bullet points and headers for structure.
        Keep responses focused and actionable. The user's context may include their notes, todos, and logs.
        When analyzing todos, prioritize by urgency and importance.
        Format code snippets with proper markdown code blocks.
        """
    
    /// System prompt for edit mode (#do) - instructs LLM to return only modified text
    static let editSystemPrompt = """
        You are editing a section of a personal work log.
        Return ONLY the modified text with the requested changes applied.
        Do not add explanations, commentary, or markdown code block wrappers.
        Do not add phrases like "Here is the modified text:" or similar.
        Preserve the original structure and formatting unless specifically asked to change it.
        Output only the transformed content, nothing else.
        """
    
    // MARK: - OpenRouter Settings
    
    /// Base URL for OpenRouter API
    static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    
    /// App identifier for OpenRouter analytics
    static let appName = "ExoCortex"
    
    /// Referer URL for OpenRouter (required header)
    static let referer = "https://exocortex.app"
}
