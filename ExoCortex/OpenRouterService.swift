import Foundation

/// Service for streaming chat completions from OpenRouter API
actor OpenRouterService {
    
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
    
    /// Stream a chat completion response
    /// - Parameters:
    ///   - userMessage: The user's prompt (with context already included)
    /// - Returns: An async stream of text chunks
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
        
        guard httpResponse.statusCode == 200 else {
            // Try to read error message
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw StreamError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Parse SSE stream
        var buffer = ""
        for try await byte in bytes {
            buffer.append(Character(UnicodeScalar(byte)))
            
            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<newlineIndex])
                buffer = String(buffer[buffer.index(after: newlineIndex)...])
                
                // Skip empty lines and comments
                guard !line.isEmpty, line.hasPrefix("data: ") else { continue }
                
                let jsonString = String(line.dropFirst(6)) // Remove "data: "
                
                // Check for stream end
                if jsonString == "[DONE]" {
                    continuation.finish()
                    return
                }
                
                // Parse JSON chunk
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    continuation.yield(content)
                }
            }
        }
        
        continuation.finish()
    }
}
