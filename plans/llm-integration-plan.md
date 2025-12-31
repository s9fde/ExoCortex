# ExoCortex LLM Integration Plan

## Overview

Integrate Claude Opus 4.5 via OpenRouter directly into the work log editor using a tag-based prompt/reply system. No separate UI elements needed - prompts and responses live naturally in the markdown log.

## Configuration (in code for easy adjustment)

```swift
// LLMConfig.swift - Edit before compiling
enum LLMConfig {
    static let apiKey = "sk-or-v1-YOUR_API_KEY_HERE"
    static let model = "anthropic/claude-sonnet-4-20250514"
    static let maxTokens = 12000
    static let systemPrompt = """
        You are a helpful assistant integrated into a personal encrypted work log called ExoCortex.
        Respond concisely in markdown format. Use bullet points and headers for structure.
        Keep responses focused and actionable. The user's context may include their notes, todos, and logs.
        """
}
```

## User Experience

### Prompt Flow
```
#p What are the key principles of clean code?
```
User types a prompt prefixed with `#p` and presses Enter (newline). The system:
1. Detects the `#p` tag on the completed line
2. Immediately inserts `#opus45 ` on the next line
3. Streams the response word-by-word into the editor
4. Appends `\n---\n` when complete

### Result in Editor
```markdown
#p What are the key principles of clean code?
#opus45 Clean code follows several key principles:

1. **Readability** - Code should read like well-written prose
2. **Single Responsibility** - Each function/class does one thing
3. **DRY** - Don't Repeat Yourself
4. **KISS** - Keep It Simple, Stupid
5. **Meaningful Names** - Variables and functions should be self-documenting

---
```

## Context References

Allow users to include log content in prompts using `@` references:

| Reference | Description |
|-----------|-------------|
| `@log` | Entire work log (⚠️ token heavy) |
| `@today` | Lines with today's date header |
| `@week` | Last 7 days of entries |
| `@last:N` | Last N lines |
| `@tag:xyz` | All lines matching #xyz tag |
| `@todos` | All open todos |

### Example with Context
```markdown
#p @todos Summarize my open tasks and suggest priorities
#opus45 Based on your open todos, here are your tasks prioritized:

**High Priority:**
- [ ] Finish quarterly report (deadline mentioned)
- [ ] Schedule team sync meeting

**Medium Priority:**
- [ ] Review pull requests
...
---
```

## Architecture

```mermaid
flowchart TB
    subgraph Editor
        A[TextEditor] -->|text changes| B[LogViewModel]
    end
    
    subgraph Prompt Detection
        B -->|newline detected| C{Line starts with #p?}
        C -->|yes| D[PromptService]
        C -->|no| E[Normal autosave]
    end
    
    subgraph Context Resolution
        D --> F[ContextResolver]
        F -->|@today| G[Extract todays lines]
        F -->|@todos| H[Extract open todos]
        F -->|@tag:x| I[Filter by tag]
        F --> J[Build full prompt with context]
    end
    
    subgraph API Layer
        J --> K[OpenRouterService]
        K -->|POST /chat/completions| L[OpenRouter API]
        L -->|SSE stream| K
    end
    
    subgraph Streaming Response
        K -->|chunk| M[Insert text at cursor]
        M --> A
        K -->|done| N[Append ---]
    end
```

## Components

### 1. OpenRouterService
New file: `OpenRouterService.swift`

```swift
actor OpenRouterService {
    private let apiKey: String
    private let model = "anthropic/claude-opus-4-20250514"
    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    
    func stream(prompt: String, context: String?) -> AsyncThrowingStream<String, Error>
}
```

**Responsibilities:**
- Make streaming POST request to OpenRouter
- Parse SSE chunks (`data: {...}`)
- Yield text deltas as they arrive
- Handle errors gracefully

### 2. ContextResolver
New file: `ContextResolver.swift`

```swift
struct ContextResolver {
    func resolve(prompt: String, fullText: String) -> (cleanPrompt: String, context: String?)
}
```

**Responsibilities:**
- Parse `@` references in prompt
- Extract relevant sections from fullText
- Build context string to prepend to prompt
- Return cleaned prompt without `@` tokens

### 3. PromptService
New file: `PromptService.swift`

```swift
@MainActor
class PromptService {
    func detectAndProcess(text: String, cursorPosition: Int, onChange: (String) -> Void) async
}
```

**Responsibilities:**
- Detect when user presses Enter after `#p` line
- Coordinate context resolution
- Start streaming response
- Insert `#opus45 ` prefix
- Stream chunks into editor
- Append `---` on completion

### 4. LogViewModel Extensions
Modify: `LogViewModel.swift`

```swift
// Add to LogViewModel
private let promptService: PromptService

func processPromptIfNeeded() {
    // Called on newline detection
    // Check if previous line starts with #p
    // If so, trigger prompt processing
}
```

### 5. Settings Extensions
Modify: `SettingsView.swift`

```swift
Section(header: Text("AI Assistant")) {
    SecureField("OpenRouter API Key", text: $apiKey)
    Button("Save API Key") { saveToKeychain() }
    Button("Clear API Key", role: .destructive) { clearFromKeychain() }
    Toggle("Enable AI prompts (#p)", isOn: $aiEnabled)
}
```

## Data Flow

1. **User types:** `#p @todos What should I focus on today?` + Enter
2. **ViewModel detects:** Previous line starts with `#p`
3. **ContextResolver parses:** Finds `@todos`, extracts open todos from log
4. **Prompt built:**
   ```
   Context from your work log:
   - [ ] Finish quarterly report #work
   - [ ] Schedule team sync meeting #work
   - [ ] Review pull requests
   
   User prompt: What should I focus on today?
   ```
5. **OpenRouterService streams:** Response arrives chunk by chunk
6. **Editor updates:** Each chunk appended to `fullText`
7. **Completion:** `---` appended, autosave triggers

## OpenRouter API Details

**Endpoint:** `POST https://openrouter.ai/api/v1/chat/completions`

**Headers:**
```
Authorization: Bearer $API_KEY
Content-Type: application/json
HTTP-Referer: https://exocortex.app
X-Title: ExoCortex
```

**Request Body:**
```json
{
  "model": "anthropic/claude-opus-4-20250514",
  "stream": true,
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant integrated into a personal work log. Respond concisely in markdown format."
    },
    {
      "role": "user",
      "content": "Context:\n{context}\n\nPrompt: {user_prompt}"
    }
  ]
}
```

**SSE Response Format:**
```
data: {"choices":[{"delta":{"content":"Hello"}}]}
data: {"choices":[{"delta":{"content":" world"}}]}
data: [DONE]
```

## Security Considerations

1. **API Key Storage:** Use existing `KeychainService` with biometric protection
2. **No External Logging:** Prompts/responses stay local (encrypted in cortex.enc)
3. **Context Limits:** Warn if context exceeds ~100k tokens
4. **Rate Limiting:** Throttle requests to prevent accidental spam

## Edge Cases

| Case | Handling |
|------|----------|
| Network error mid-stream | Append `[Error: {message}]` and `---` |
| User edits during stream | Cancel stream, keep partial response |
| Empty prompt (`#p` only) | Ignore, don't trigger API |
| API key missing | Show inline error: `#opus45 [Configure API key in Settings]` |
| Context too large | Truncate with warning in response |

## File Changes Summary

| File | Change |
|------|--------|
| `OpenRouterService.swift` | **New** - API communication |
| `ContextResolver.swift` | **New** - Parse @ references |
| `PromptService.swift` | **New** - Orchestrate prompt flow |
| `LogViewModel.swift` | **Modify** - Add prompt detection |
| `SettingsView.swift` | **Modify** - Add API key config |
| `KeychainService.swift` | **Modify** - Add API key storage methods |

## Implementation Order

1. `OpenRouterService` - Get basic streaming working
2. `ContextResolver` - Parse @ references
3. `PromptService` - Wire up detection and response insertion
4. `LogViewModel` - Integrate prompt detection on text change
5. `SettingsView` + `KeychainService` - API key management
6. Edge case handling and polish

## Questions for User

1. Should failed prompts be marked with a special tag (e.g., `#error`)?
2. Preferred behavior if user starts typing before stream completes?
3. Should there be a visual indicator (subtle animation) during streaming?
4. Maximum context size preference (default: 50k tokens)?
