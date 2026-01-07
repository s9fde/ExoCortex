//
//  OpenRouterService.swift
//  ExoCortex
//
//  Service for fetching chat completions from OpenRouter API.
//  Returns complete responses for simple, high-performance text handling.
//

import Foundation

// MARK: - OpenRouter Service

/// Service for fetching complete chat completions from OpenRouter API.
/// Returns full responses in a single request for maximum simplicity and performance.
actor OpenRouterService {
    
    // MARK: - Errors
    
    enum APIError: Error, LocalizedError {
        case invalidAPIKey
        case networkError(String)
        case invalidResponse
        case apiError(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Invalid or missing API key. Edit LLMConfig.swift"
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidResponse:
                return "Invalid response from API"
            case .apiError(let message):
                return "API error: \(message)"
            }
        }
    }
    
    // MARK: - API Response Types
    
    private struct APIResponse: Decodable {
        let choices: [Choice]
        
        struct Choice: Decodable {
            let message: Message
            
            struct Message: Decodable {
                let content: String
            }
        }
    }
    
    // MARK: - Fetch Methods
    
    /// Fetch a complete chat response (read-only mode)
    /// - Parameter userMessage: The user's prompt (with context already included)
    /// - Returns: Complete response text
    func fetch(userMessage: String) async throws -> String {
        let response = try await performRequest(userMessage: userMessage, systemPrompt: LLMConfig.systemPrompt)
        return response
    }
    
    /// Fetch a complete chat response for edit mode (#do)
    /// - Parameter userMessage: The edit instruction with context
    /// - Returns: Complete response text
    func fetchEdit(userMessage: String) async throws -> String {
        let response = try await performRequest(userMessage: userMessage, systemPrompt: LLMConfig.editSystemPrompt)
        return response
    }
    
    // MARK: - Private Methods
    
    private func performRequest(
        userMessage: String,
        systemPrompt: String
    ) async throws -> String {
        // Validate API key
        guard !LLMConfig.apiKey.contains("YOUR_API_KEY") else {
            throw APIError.invalidAPIKey
        }
        
        // Build request
        var request = URLRequest(url: LLMConfig.baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(LLMConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(LLMConfig.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(LLMConfig.appName, forHTTPHeaderField: "X-Title")
        
        let body: [String: Any] = [
            "model": LLMConfig.model,
            "stream": false,
            "max_tokens": LLMConfig.maxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle error responses
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Parse JSON response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(APIResponse.self, from: data)
        
        guard let firstChoice = apiResponse.choices.first else {
            throw APIError.invalidResponse
        }
        
        return firstChoice.message.content
    }
}
