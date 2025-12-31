import Foundation

/// Configuration for LLM integration via OpenRouter
/// Edit these values before compiling to customize behavior
enum LLMConfig {
    // MARK: - API Configuration
    
    /// Your OpenRouter API key - get one at https://openrouter.ai/keys
    static let apiKey = "sk-or-v1-YOUR_API_KEY_HERE"
    
    /// The model to use - Claude Opus 4.5 via OpenRouter
    static let model = "anthropic/claude-sonnet-4-20250514"
    
    /// Maximum tokens for response (affects cost and response length)
    static let maxTokens = 12000
    
    // MARK: - Prompt Tags
    
    /// Tag that triggers a prompt (user writes this)
    static let promptTag = "#p"
    
    /// Tag prepended to AI responses
    static let responseTag = "#opus45"
    
    /// Tag for errors
    static let errorTag = "#error"
    
    // MARK: - System Prompt
    
    /// System prompt sent with every request
    static let systemPrompt = """
        You are a helpful assistant integrated into a personal encrypted work log called ExoCortex.
        Respond concisely in markdown format. Use bullet points and headers for structure.
        Keep responses focused and actionable. The user's context may include their notes, todos, and logs.
        When analyzing todos, prioritize by urgency and importance.
        Format code snippets with proper markdown code blocks.
        """
    
    // MARK: - OpenRouter Settings
    
    /// Base URL for OpenRouter API
    static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    
    /// App identifier for OpenRouter analytics
    static let appName = "ExoCortex"
    
    /// Referer URL for OpenRouter
    static let referer = "https://exocortex.app"
}
