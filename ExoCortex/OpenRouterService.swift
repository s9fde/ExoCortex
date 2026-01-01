//
//  OpenRouterService.swift
//  ExoCortex
//
//  Service for streaming chat completions from OpenRouter API.
//  Supports Claude and other models via SSE streaming.
//

import Foundation

// MARK: - OpenRouter Service

/// Actor-based service for streaming chat completions from OpenRouter API.
/// Handles SSE (Server-Sent Events) stream parsing for real-time responses.
actor OpenRouterService {
    
    // MARK: - Errors
    
    enum StreamError: Error, LocalizedError {
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
    
    // MARK: - Streaming
    
    /// Stream a chat completion response
    /// - Parameter userMessage: The user's prompt (with context already included)
    /// - Returns: Async stream of text chunks
    func stream(userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await performStream(userMessage: userMessage, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func performStream(
        userMessage: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        // Validate API key
        guard !LLMConfig.apiKey.contains("YOUR_API_KEY") else {
            throw StreamError.invalidAPIKey
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
            "stream": true,
            "max_tokens": LLMConfig.maxTokens,
            "messages": [
                ["role": "system", "content": LLMConfig.systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Perform streaming request
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamError.invalidResponse
        }
        
        // Handle error responses
        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw StreamError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Parse SSE stream
        try await parseSSEStream(bytes: bytes, continuation: continuation)
    }
    
    /// Parse SSE (Server-Sent Events) stream and yield text chunks
    private func parseSSEStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var buffer = ""
        
        for try await byte in bytes {
            buffer.append(Character(UnicodeScalar(byte)))
            
            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<newlineIndex])
                buffer = String(buffer[buffer.index(after: newlineIndex)...])
                
                // Skip empty lines and non-data lines
                guard !line.isEmpty, line.hasPrefix("data: ") else { continue }
                
                let jsonString = String(line.dropFirst(6))
                
                // Check for stream end marker
                if jsonString == "[DONE]" {
                    continuation.finish()
                    return
                }
                
                // Parse JSON and extract content
                if let content = extractContent(from: jsonString) {
                    continuation.yield(content)
                }
            }
        }
        
        continuation.finish()
    }
    
    /// Extract text content from SSE JSON chunk
    private func extractContent(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }
}
