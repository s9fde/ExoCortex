# Streaming Integration Guide

## Quick Start: Using Streaming in Your Views

### Basic Streaming Example

```swift
import SwiftUI

struct StreamingQueryView: View {
    @State private var response = ""
    @State private var isLoading = false
    @State private var error: String?
    
    let service = OpenRouterService()
    let userQuery = "Analyze my work log for patterns @recent"
    
    var body: some View {
        VStack {
            // Display response as it streams in
            TextEditor(text: $response)
                .disabled(true)
                .frame(minHeight: 200)
            
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Streaming response...")
                }
            }
            
            Button(isLoading ? "Stop" : "Query") {
                if isLoading {
                    // TODO: Implement cancellation
                } else {
                    fetchWithStreaming()
                }
            }
            .disabled(isLoading)
            
            if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    private func fetchWithStreaming() {
        isLoading = true
        error = nil
        response = ""
        
        Task {
            do {
                let result = try await service.fetchStreaming(
                    userMessage: userQuery
                ) { chunk in
                    // This callback is called for each token received
                    DispatchQueue.main.async {
                        response.append(chunk)
                    }
                }
                
                DispatchQueue.main.async {
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
```

---

## Integration Patterns

### Pattern 1: Simple Append (Default)
Best for general responses, minimal UI complexity.

```swift
let result = try await service.fetchStreaming(
    userMessage: query
) { chunk in
    DispatchQueue.main.async {
        response.append(chunk)
    }
}
```

**Pros**: Simple, works for most use cases
**Cons**: No formatting, tokens accumulate linearly

---

### Pattern 2: Smart Formatting
Parse streaming chunks for formatting (bold, headers, code blocks).

```swift
let result = try await service.fetchStreaming(
    userMessage: query
) { chunk in
    DispatchQueue.main.async {
        let formatted = formatStreamingChunk(chunk)
        response.append(formatted)
    }
}

func formatStreamingChunk(_ chunk: String) -> String {
    // Example: Convert **text** to bold
    return chunk
        .replacingOccurrences(of: "**", with: "")  // Simplified
        // Add AttributedString conversion for real formatting
}
```

---

### Pattern 3: Buffered Updates
Accumulate chunks and update UI in batches for better performance.

```swift
@State private var updateBuffer = ""
@State private var lastUpdateTime = Date()

private func fetchWithBuffering() {
    Task {
        let result = try await service.fetchStreaming(
            userMessage: query
        ) { chunk in
            updateBuffer.append(chunk)
            
            // Batch update every 100ms
            if Date().timeIntervalSince(lastUpdateTime) > 0.1 {
                DispatchQueue.main.async {
                    response.append(updateBuffer)
                    updateBuffer = ""
                    lastUpdateTime = Date()
                }
            }
        }
        
        // Flush remaining buffer
        DispatchQueue.main.async {
            response.append(updateBuffer)
        }
    }
}
```

**Pros**: Higher performance, fewer UI updates
**Cons**: Slight latency increase (100ms is imperceptible)

---

### Pattern 4: With Tool Use Progress
Display when Claude invokes tools like web search.

```swift
@State private var toolCalls: [String] = []
@State private var isSearching = false

private func fetchWithToolTracking() {
    Task {
        do {
            let result = try await service.fetchStreaming(
                userMessage: query
            ) { chunk in
                // Simple heuristic: detect tool invocation in response
                if chunk.contains("web_search") || chunk.contains("searching") {
                    DispatchQueue.main.async {
                        isSearching = true
                        toolCalls.append("Web search initiated")
                    }
                }
                
                DispatchQueue.main.async {
                    response.append(chunk)
                    
                    // If we see continuation after search, mark as complete
                    if isSearching && chunk.count > 50 {
                        isSearching = false
                    }
                }
            }
        } catch {
            // Handle error
        }
    }
}

var body: some View {
    VStack {
        // Show active tools
        if isSearching {
            Label("Searching web for context...", systemImage: "magnifyingglass")
                .foregroundColor(.blue)
        }
        
        if !toolCalls.isEmpty {
            Section("Tool Calls") {
                ForEach(toolCalls, id: \.self) { call in
                    Text(call)
                        .font(.caption)
                }
            }
        }
        
        // Response display
        TextEditor(text: $response)
    }
}
```

---

## Cancellation Support

### Adding Cancellation

To add cancellation support, you'll need to modify `OpenRouterService`:

```swift
// Add to OpenRouterService
private var currentTask: Task<Void, Never>?

func cancelStreaming() {
    currentTask?.cancel()
}
```

Then in View:

```swift
@State private var service = OpenRouterService()

Button("Stop") {
    Task {
        await service.cancelStreaming()
        isLoading = false
    }
}
```

**Note**: Full cancellation implementation requires modifying the async/await flow to support `AsyncThrowingStream` with cancellation tokens.

---

## Performance Optimization

### 1. Reduce UI Update Overhead
```swift
// AVOID: Updates UI for every token
for await chunk in stream {
    response.append(chunk)  // ❌ Too many redraws
}

// PREFER: Batch updates
var buffer = ""
for await chunk in stream {
    buffer.append(chunk)
    if buffer.count > 20 {  // ✅ Update every 20 chars
        await updateUI(buffer)
        buffer = ""
    }
}
```

### 2. Use `@MainActor` for UI Thread Safety
```swift
@MainActor
func updateResponseUI(_ chunk: String) {
    response.append(chunk)
}

// In streaming callback:
Task { @MainActor in
    updateResponseUI(chunk)
}
```

### 3. Memory Management for Long Responses
```swift
// For very long responses, consider pagination:
@State private var pages: [String] = [""]
@State private var currentPageIndex = 0

private func addChunkToCurrentPage(_ chunk: String) {
    let maxPageSize = 50000  // chars per page
    
    if let last = pages.last, last.count + chunk.count > maxPageSize {
        pages.append(chunk)  // New page
    } else if !pages.isEmpty {
        pages[pages.count - 1].append(chunk)
    }
}
```

---

## Error Handling

### Streaming-Specific Errors

```swift
do {
    try await service.fetchStreaming(userMessage: query) { chunk in
        // Process chunk
    }
} catch OpenRouterService.APIError.streamingError(let msg) {
    // Network dropped during streaming
    error = "Connection interrupted: \(msg)"
} catch OpenRouterService.APIError.toolExecutionError(let msg) {
    // Tool (web search) failed
    error = "Search failed: \(msg)"
} catch {
    error = error.localizedDescription
}
```

### Retry Logic
```swift
func fetchWithRetry(maxAttempts: Int = 3) async throws -> String {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await service.fetch(userMessage: query)
        } catch {
            lastError = error
            try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))  // Exponential backoff
        }
    }
    
    throw lastError ?? APIError.networkError("Max retries exceeded")
}
```

---

## Monitoring & Debugging

### Enable Verbose Logging

Add to OpenRouterService for debugging:

```swift
private func logStreamingChunk(_ chunk: String, index: Int) {
    #if DEBUG
    print("[\(index)] Chunk: \(chunk.prefix(50))...")
    #endif
}
```

### Performance Profiling

```swift
@State private var metrics = StreamingMetrics()
@State private var startTime: Date?

struct StreamingMetrics {
    var chunksReceived = 0
    var totalCharacters = 0
    var startTime: Date?
    
    var elapsedSeconds: Double {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    var tokensPerSecond: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(totalCharacters) / elapsedSeconds / 4.0  // ~4 chars per token
    }
}

private func fetchWithMetrics() {
    metrics = StreamingMetrics(startTime: Date())
    
    Task {
        try await service.fetchStreaming(userMessage: query) { chunk in
            DispatchQueue.main.async {
                metrics.chunksReceived += 1
                metrics.totalCharacters += chunk.count
                response.append(chunk)
            }
        }
        
        #if DEBUG
        print("""
        Streaming Complete:
        - Chunks: \(metrics.chunksReceived)
        - Characters: \(metrics.totalCharacters)
        - Duration: \(String(format: "%.2f", metrics.elapsedSeconds))s
        - Speed: \(String(format: "%.1f", metrics.tokensPerSecond)) tokens/sec
        """)
        #endif
    }
}
```

---

## Tool Use During Streaming

When Claude decides to use a tool during streaming, the response may include tool invocation blocks. The current implementation handles this, but here's how to display tool activity:

```swift
@State private var toolsInProgress: Set<String> = []

private func fetchWithToolDisplay() {
    Task {
        try await service.fetchStreaming(
            userMessage: query
        ) { chunk in
            DispatchQueue.main.async {
                response.append(chunk)
                
                // Parse for tool markers (implementation-specific)
                if chunk.contains("web_search_perplexity") {
                    toolsInProgress.insert("web_search")
                }
            }
        }
        
        // After streaming completes, clarity all tools
        DispatchQueue.main.async {
            toolsInProgress.removeAll()
        }
    }
}

var body: some View {
    VStack {
        if !toolsInProgress.isEmpty {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Using: \(toolsInProgress.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
        }
        
        TextEditor(text: $response)
    }
}
```

---

## Migration from Non-Streaming

If you have existing non-streaming code:

**Before:**
```swift
let response = try await service.fetch(userMessage: query)
result = response
```

**After (with streaming):**
```swift
let response = try await service.fetchStreaming(
    userMessage: query
) { chunk in
    DispatchQueue.main.async {
        result.append(chunk)  // Incremental updates
    }
}
// result now contains full response
```

Both patterns coexist—use `fetch()` for simple requests, `fetchStreaming()` for better UX.

---

## Best Practices

1. **Always dispatch UI updates to main thread** - Use `DispatchQueue.main.async` in callbacks
2. **Handle both streaming and non-streaming paths** - Some requests may not benefit from streaming
3. **Clean up resources** - Cancel tasks when views disappear
4. **Batch UI updates** - Don't update for every single token
5. **Show progress indicators** - Users should see something happening
6. **Implement fallback** - Have non-streaming backup if streaming fails
7. **Monitor performance** - Profile before/after streaming in real scenarios

---

## Testing Streaming

```swift
#if DEBUG
struct MockStreamingService {
    func fetchStreaming(
        userMessage: String,
        onChunk: @escaping StreamingCallback
    ) async throws -> String {
        let mockResponse = "This is a mock streaming response for testing..."
        
        for character in mockResponse {
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms per char
            onChunk(String(character))
        }
        
        return mockResponse
    }
}
#endif

// In preview:
#Preview {
    StreamingQueryView()
        .environment(\.mockStreaming, true)
}
```
