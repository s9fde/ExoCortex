# ExoCortex LLM Integration Plan

## Status: ✅ Complete

> Last updated: 2026-01-01

## Overview

Claude Opus 4.5 is integrated via OpenRouter directly into the work log editor using a tag-based prompt/reply system. Prompts and responses live naturally in the markdown log with no separate UI elements needed.

## Implementation Summary

### Completed Features

- [x] OpenRouter streaming API integration
- [x] Tag-based prompt detection (`#p`)
- [x] Streaming response insertion (`#opus45`)
- [x] Context references (`@log`, `@today`, `@week`, `@last:N`, `@tag:xyz`, `@todos`)
- [x] Error handling with `#error` tag
- [x] Stream cancellation on user edit
- [x] Visual indicator during streaming

## Configuration

Edit [`LLMConfig.swift`](../ExoCortex/LLMConfig.swift) before compiling:

```swift
enum LLMConfig {
    static let apiKey = "sk-or-v1-YOUR_API_KEY_HERE"  // Get from https://openrouter.ai/keys
    static let model = "anthropic/claude-opus-4.5"
    static let maxTokens = 12000
    static let promptTag = "#p"
    static let responseTag = "#opus45"
}
```

## User Experience

### Prompt Flow
```
#p What are the key principles of clean code?
```
User types a prompt prefixed with `#p` and presses Enter. The system:
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
...
---
```

## Context References

Include log content in prompts using `@` references:

| Reference | Description |
|-----------|-------------|
| `@log` | Entire work log (⚠️ token heavy) |
| `@today` | Lines with today's date header |
| `@week` | Last 7 days of entries |
| `@last:N` | Last N lines |
| `@tag:xyz` | All lines matching #xyz tag |
| `@todos` | All open todos |

### Example
```markdown
#p @todos Summarize my open tasks and suggest priorities
#opus45 Based on your open todos:
...
---
```

## Architecture

```
TextEditor → LogViewModel → detectAndProcessPrompt()
                                    ↓
                            ContextResolver (resolve @-references)
                                    ↓
                            OpenRouterService (stream API response)
                                    ↓
                            appendToText() → TextEditor
```

## Files

| File | Purpose |
|------|---------|
| [`LLMConfig.swift`](../ExoCortex/LLMConfig.swift) | API key, model, prompts configuration |
| [`OpenRouterService.swift`](../ExoCortex/OpenRouterService.swift) | OpenRouter API streaming client |
| [`ContextResolver.swift`](../ExoCortex/ContextResolver.swift) | @-reference parsing and context extraction |
| [`LogViewModel.swift`](../ExoCortex/LogViewModel.swift) | Prompt detection and response insertion |

## Error Handling

| Case | Handling |
|------|----------|
| Network error | Append `#error {message}` and `---` |
| User edits during stream | Cancel stream, keep partial response |
| Empty prompt | Ignore, don't trigger API |
| API key missing | Show inline error |
| Context too large | Truncate with warning |

## Security Notes

1. **API Key**: Stored in code (LLMConfig.swift), not in keychain
2. **No External Logging**: All prompts/responses encrypted in cortex.enc
3. **Context Limits**: Automatic truncation for large contexts

## Future Enhancements

- [ ] API key storage in Keychain with Settings UI
- [ ] Model selection in Settings
- [ ] Token usage tracking
- [ ] Conversation history (multi-turn)
- [ ] Custom system prompts
