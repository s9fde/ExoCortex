# OpenRouter API Quick Reference

## Configuration ([`LLMConfig.swift`](ExoCortex/LLMConfig.swift))

```swift
// Response Control
LLMConfig.temperature = 0.7              // 0-2: randomness
LLMConfig.topP = 1.0                     // 0-1: nucleus sampling
LLMConfig.frequencyPenalty = 0.0         // -2 to 2: reduce repetition
LLMConfig.presencePenalty = 0.0          // -2 to 2: new topics
LLMConfig.repetitionsPenalty = 1.0       // 1+: token-level dedup
LLMConfig.minP = 0.0                     // 0-1: quality filter

// Features
LLMConfig.enableStreaming = true         // Real-time token delivery
LLMConfig.enableToolUse = true           // Allow web search

// Runtime Config
LLMConfig.apiKey = "sk-..."              // From Keychain
LLMConfig.activeModel = "anthropic/claude-opus-4.5"
LLMConfig.activeSystemPrompt = "..."
```

---

## Basic API Calls

### Standard Request (Complete Response)
```swift
import Foundation

let service = OpenRouterService()

// Simple query
let response = try await service.fetch(userMessage: "Analyze @recent-work")
print(response)

// With custom system prompt
LLMConfig.activeSystemPrompt = "You are a concise analyst..."
let response = try await service.fetch(userMessage: query)
```

### Streaming Request (Real-Time Tokens)
```swift
var fullResponse = ""

let result = try await service.fetchStreaming(
    userMessage: "Summarize work patterns from @2026-01"
) { chunk in
    // Called for each token
    DispatchQueue.main.async {
        fullResponse.append(chunk)
        uiState.displayText = fullResponse  // Update UI
    }
}
print("Complete response: \(result)")
```

---

## Error Handling

```swift
do {
    let response = try await service.fetch(userMessage: query)
} catch OpenRouterService.APIError.invalidAPIKey {
    // API key not configured
} catch OpenRouterService.APIError.streamingError(let message) {
    // Streaming connection failed
} catch OpenRouterService.APIError.toolExecutionError(let message) {
    // Web search failed
} catch OpenRouterService.APIError.apiError(let message) {
    // OpenRouter returned error
} catch {
    // Other errors
    print("Error: \(error.localizedDescription)")
}
```

---

## Response Styles

### Factual Extraction
```swift
LLMConfig.temperature = 0.2
LLMConfig.frequencyPenalty = 0.0
LLMConfig.presencePenalty = 0.0

let dates = try await service.fetch(
    userMessage: "Extract all dates from @2026-01"
)
```

### Balanced Analysis
```swift
LLMConfig.temperature = 0.7
LLMConfig.frequencyPenalty = 0.0
LLMConfig.presencePenalty = 0.0

let summary = try await service.fetch(
    userMessage: "Summarize my work"
)
```

### Creative Ideation
```swift
LLMConfig.temperature = 1.2
LLMConfig.frequencyPenalty = 0.3
LLMConfig.presencePenalty = 0.5

let ideas = try await service.fetch(
    userMessage: "Generate alternative approaches to @problem"
)
```

### Research with Web Search
```swift
LLMConfig.temperature = 0.5
LLMConfig.enableToolUse = true
LLMConfig.enableStreaming = true

let research = try await service.fetchStreaming(
    userMessage: "What recent developments relate to @strategy?"
) { chunk in
    DispatchQueue.main.async {
        print(chunk, terminator: "")
    }
}
```

---

## Tool Use (Automatic Web Search)

No explicit code needed—Claude decides when to search:

```swift
// Enable tool use
LLMConfig.enableToolUse = true

// Claude will autonomously use web_search_perplexity if needed
let response = try await service.fetch(
    userMessage: "What's the latest in AI?"
)
// Claude may have searched web for "latest AI developments"
```

**When Claude searches:**
- Query asks about current events/recent developments
- Query needs external validation
- User specifically prompts for research

**What happens:**
1. Claude requests `web_search_perplexity` with search query
2. Service calls Perplexity API
3. Results sent back to Claude
4. Claude synthesizes final response with current information

---

## SwiftUI Integration

### Basic View with Streaming
```swift
struct AnalysisView: View {
    @State private var response = ""
    @State private var isLoading = false
    
    let service = OpenRouterService()
    
    var body: some View {
        VStack {
            TextEditor(text: $response)
                .disabled(true)
            
            Button(isLoading ? "Analyzing..." : "Analyze") {
                analyze()
            }
            .disabled(isLoading)
        }
    }
    
    private func analyze() {
        isLoading = true
        response = ""
        
        Task {
            do {
                try await service.fetchStreaming(
                    userMessage: "Analyze @recent-work"
                ) { chunk in
                    DispatchQueue.main.async {
                        response.append(chunk)
                    }
                }
            } catch {
                response = "Error: \(error.localizedDescription)"
            }
            
            DispatchQueue.main.async {
                isLoading = false
            }
        }
    }
}
```

### With Tool Progress Indicator
```swift
struct ResearchView: View {
    @State private var response = ""
    @State private var isSearching = false
    
    var body: some View {
        VStack {
            if isSearching {
                Label("Searching web...", systemImage: "magnifyingglass")
                    .foregroundColor(.blue)
            }
            
            TextEditor(text: $response)
        }
        .onAppear(perform: startResearch)
    }
    
    private func startResearch() {
        Task {
            LLMConfig.enableToolUse = true
            
            try await OpenRouterService().fetchStreaming(
                userMessage: "Latest developments in @domain?"
            ) { chunk in
                DispatchQueue.main.async {
                    if chunk.contains("search") {
                        isSearching = true
                    }
                    response.append(chunk)
                }
            }
            
            DispatchQueue.main.async {
                isSearching = false
            }
        }
    }
}
```

---

## Common Patterns

### Retry with Exponential Backoff
```swift
func fetchWithRetry(
    message: String,
    maxAttempts: Int = 3,
    delaySeconds: Double = 1.0
) async throws -> String {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await service.fetch(userMessage: message)
        } catch {
            lastError = error
            try await Task.sleep(nanoseconds: UInt64(delaySeconds * Double(attempt) * 1_000_000_000))
        }
    }
    
    throw lastError ?? OpenRouterService.APIError.networkError("Max retries exceeded")
}
```

### Batch Processing Multiple Queries
```swift
let queries = [
    "Extract dates from @2026-01",
    "Summarize patterns from @recent-work",
    "List all issues from @backlog"
]

var results: [String] = []

for query in queries {
    do {
        let result = try await service.fetch(userMessage: query)
        results.append(result)
    } catch {
        results.append("Error: \(error)")
    }
}
```

### Progressive Enhancement
```swift
// Start with streaming for better UX
LLMConfig.enableStreaming = true

let response = try await service.fetchStreaming(
    userMessage: query
) { chunk in
    DispatchQueue.main.async {
        uiText.append(chunk)
    }
}

// Fall back to non-streaming if error
if response.isEmpty {
    let fallbackResponse = try await service.fetch(userMessage: query)
    uiText = fallbackResponse
}
```

---

## Parameter Cheat Sheet

| Goal | Temperature | Frequency Penalty | Presence Penalty |
|------|------------------|--------------------|--------------------|
| Extraction | 0.2 | 0.0 | 0.0 |
| Analysis | 0.7 | 0.0 | 0.0 |
| Creativity | 1.2 | 0.3 | 0.5 |
| Technical | 0.4 | 0.2 | 0.1 |
| Research | 0.5 | 0.1 | 0.3 |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `invalidAPIKey` error | Check Keychain, verify key format |
| No tokens received from streaming | Check network, try non-streaming |
| Web search not triggering | Query may not need external info; Claude decides |
| Response too short | Check `max_tokens` setting (default 12000) |
| Response repetitive | Increase `frequency_penalty` to 0.3-0.5 |
| Response inconsistent | Decrease `temperature` to 0.3-0.5 |
| Tool execution fails | Check Perplexity API limits, retry with backoff |

---

## Advanced: Custom System Prompts

```swift
// Analytical mode
LLMConfig.activeSystemPrompt = """
You are an analytical assistant for work logs. Focus on:
- Patterns and trends
- Anomalies and outliers
- Actionable insights
"""

// Concise mode
LLMConfig.activeSystemPrompt = """
Respond in 1-2 sentences maximum. Be specific and actionable.
"""

// Research mode
LLMConfig.activeSystemPrompt = """
Use web search for any current information. Cross-reference multiple sources.
Prioritize recent, verified information over general knowledge.
"""

// Then use: try await service.fetch(userMessage: query)
```

---

## API Limits (OpenRouter)

- **Max tokens per request**: 12,000 (configurable)
- **Max requests per minute**: Depends on plan
- **Supported models**: See [OpenRouter docs](https://openrouter.ai/docs)
- **Web search (Perplexity)**: ~500 tokens per search

---

## Key Model Options

```swift
// Fast & cheap
LLMConfig.activeModel = "anthropic/claude-haiku-4.5"

// Balanced (current default)
LLMConfig.activeModel = "anthropic/claude-opus-4.5"

// Most capable
LLMConfig.activeModel = "anthropic/claude-3-opus"

// Web search dedicated
// Use Perplexity for web-focused queries
```

---

## Monitoring

```swift
// Track API usage (optional enhancement)
var apiCallsToday = 0
var tokensUsedToday = 0

func logAPICall(_ tokens: Int) {
    apiCallsToday += 1
    tokensUsedToday += tokens
    
    #if DEBUG
    print("API: \(apiCallsToday) calls, \(tokensUsedToday) tokens today")
    #endif
}
```

---

## More Information

- **Full Architecture**: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- **Streaming Guide**: [`STREAMING_INTEGRATION_GUIDE.md`](STREAMING_INTEGRATION_GUIDE.md)
- **Parameter Tuning**: [`PARAMETER_TUNING_GUIDE.md`](PARAMETER_TUNING_GUIDE.md)
- **Implementation Details**: [`IMPLEMENTATION_SUMMARY.md`](IMPLEMENTATION_SUMMARY.md)
- **Source Code**: [`ExoCortex/OpenRouterService.swift`](ExoCortex/OpenRouterService.swift)
