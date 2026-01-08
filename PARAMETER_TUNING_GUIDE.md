# OpenRouter Parameter Tuning Guide

## Overview
This guide explains each parameter in [`LLMConfig.swift`](ExoCortex/LLMConfig.swift) and provides recommendations for different use cases.

---

## Parameter Reference

### **temperature** (0.0 to 2.0)
Controls the randomness/creativity of responses. Higher values produce more diverse outputs.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| 0.0 | Deterministic, repetitive | Factual extraction, consistent formatting |
| 0.5 | Focused, consistent | Analysis, summarization |
| **0.7** | **Balanced (default)** | **General-purpose queries** |
| 1.0 | Standard variation | Creative writing, brainstorming |
| 1.5+ | High variability | Ideation, exploration |
| 2.0 | Maximum randomness | Unusual perspectives, edge cases |

```swift
// Tune temperature for your use case:
LLMConfig.temperature = 0.3  // Deterministic: "Extract all dates from logs"
LLMConfig.temperature = 0.9  // Creative: "Generate alternative titles for this section"
```

---

### **top_p** (0.0 to 1.0)
Nucleus sampling: only considers tokens within the top cumulative probability. Lower values restrict the model to most likely tokens.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| 0.5 | Very restricted | Highly factual, error-sensitive tasks |
| 0.7 | Moderately restricted | Technical documentation, code analysis |
| **1.0** | **No restriction (default)** | **All use cases equally** |
| 0.95 | Slight restriction | Balanced across all tasks |

```swift
// Combine with temperature for fine control:
LLMConfig.temperature = 0.7
LLMConfig.topP = 0.95  // Conservative: slightly restrict randomness

LLMConfig.temperature = 1.2
LLMConfig.topP = 0.8   // Creative but focused
```

**Relationship to temperature:**
- Use `temperature` for overall randomness level
- Use `top_p` to further refine by filtering unlikely tokens
- Typically adjust one, not both

---

### **frequency_penalty** (-2.0 to 2.0)
Penalizes tokens that appear frequently in the response, encouraging more varied vocabulary.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| -2.0 | Encourages repetition | Emphasis, repetitive structure |
| **0.0** | **No penalty (default)** | **Natural language flow** |
| 0.3 | Mild reduction | Slightly reduce repeated phrases |
| 0.6 | Moderate reduction | Encourage vocabulary variety |
| 1.0+ | Strong reduction | Very diverse language |

```swift
// Examples:
LLMConfig.frequency_penalty = 0.0  // Default: "the the the" might appear naturally
LLMConfig.frequency_penalty = 0.5  // "the" appears less frequently in output
```

---

### **presence_penalty** (-2.0 to 2.0)
Penalizes tokens that have appeared in the message history, encouraging discussion of new topics.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| -2.0 | Stays on topic | Depth exploration of one subject |
| **0.0** | **No penalty (default)** | **Natural topic flow** |
| 0.3 | Gentle encouragement | Explore related concepts |
| 0.6 | Strong encouragement | Comprehensive coverage |
| 1.0+ | Very strong | Force new topics |

```swift
// Example scenarios:
LLMConfig.presence_penalty = 0.0   // Analyze logs, naturally revisit topics
LLMConfig.presence_penalty = 0.7   // "Analyze logs from all perspectives"
```

---

### **repetition_penalty** (1.0 to 2.0+)
Alternative to frequency penalty; penalizes token-level repetition more strictly.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| 1.0 | No penalty (default) | Natural token sequence |
| 1.2 | Mild | Reduce local repetition |
| 1.5 | Moderate | Strongly discourage repetition |
| 2.0+ | Aggressive | Extreme anti-repetition |

```swift
// Use either frequency_penalty OR repetition_penalty, not both:
LLMConfig.frequencyPenalty = 0.5      // ✓ Standard approach
LLMConfig.repetitionsPenalty = 1.0    // ✓ Alternative (model-dependent)

// Don't combine:
LLMConfig.frequencyPenalty = 0.5        // ❌ Confusing to both apply
LLMConfig.repetitionsPenalty = 1.5      // ❌ penalties
```

---

### **min_p** (0.0 to 1.0)
Minimum token probability: ignores tokens below this threshold, ensuring higher quality outputs.

| Value | Characteristics | Use Case |
|-------|-----------------|----------|
| **0.0** | **No minimum (default)** | **Natural distribution** |
| 0.05 | Slight quality filter | Reduce obvious errors |
| 0.1 | Moderate quality filter | General-purpose improvement |
| 0.2+ | Aggressive filtering | Only very likely tokens |

```swift
// Improves quality without changing randomness:
LLMConfig.minP = 0.05  // Prevents obvious mistakes while preserving creativity
```

---

## Preset Configurations

### Preset 1: Factual Extraction (High Accuracy)
```swift
LLMConfig.temperature = 0.2
LLMConfig.topP = 1.0
LLMConfig.frequencyPenalty = 0.0
LLMConfig.presencePenalty = 0.0
LLMConfig.repetitionsPenalty = 1.0
LLMConfig.minP = 0.0
```
**Use for**: Parsing dates, extracting specific facts, structured data

---

### Preset 2: Balanced Analysis (Default)
```swift
LLMConfig.temperature = 0.7
LLMConfig.topP = 1.0
LLMConfig.frequencyPenalty = 0.0
LLMConfig.presencePenalty = 0.0
LLMConfig.repetitionsPenalty = 1.0
LLMConfig.minP = 0.0
```
**Use for**: General queries, summarization, log analysis *(current default)*

---

### Preset 3: Creative Ideation (High Diversity)
```swift
LLMConfig.temperature = 1.2
LLMConfig.topP = 0.9
LLMConfig.frequencyPenalty = 0.3
LLMConfig.presencePenalty = 0.5
LLMConfig.repetitionsPenalty = 1.2
LLMConfig.minP = 0.0
```
**Use for**: Brainstorming, alternative perspectives, creative writing

---

### Preset 4: Technical Documentation (Precise & Varied)
```swift
LLMConfig.temperature = 0.4
LLMConfig.topP = 0.95
LLMConfig.frequencyPenalty = 0.2
LLMConfig.presencePenalty = 0.1
LLMConfig.repetitionsPenalty = 1.1
LLMConfig.minP = 0.05
```
**Use for**: Code analysis, technical summaries, documentation

---

### Preset 5: Research Mode (Thorough & Reliable)
```swift
LLMConfig.temperature = 0.5
LLMConfig.topP = 0.98
LLMConfig.frequencyPenalty = 0.1
LLMConfig.presencePenalty = 0.3
LLMConfig.repetitionsPenalty = 1.0
LLMConfig.minP = 0.05
LLMConfig.enableToolUse = true
LLMConfig.enableStreaming = true
```
**Use for**: Research synthesis, cross-reference validation, web search queries

---

## Tuning Process

### Step 1: Start with Default
Use the balanced preset and observe results.

### Step 2: Identify Pain Points
- **Output too repetitive?** → Increase `frequency_penalty`
- **Output too inconsistent?** → Decrease `temperature`
- **Missing new topics?** → Increase `presence_penalty`
- **Too many grammatical errors?** → Increase `minP`

### Step 3: Adjust One Parameter
Change only one parameter at a time to observe effects clearly.

```swift
// ❌ Don't do this:
LLMConfig.temperature = 0.5
LLMConfig.topP = 0.9
LLMConfig.frequencyPenalty = 0.3

// ✓ Do this:
// Change 1: Try lower temperature
LLMConfig.temperature = 0.5

// Test, observe, then:
// Change 2: If still varying too much, try frequency penalty
LLMConfig.frequencyPenalty = 0.3
```

### Step 4: Verify with Real Queries
Test with your actual use cases (e.g., "Summarize @recent-work", "Extract all issues from @2026-01")

### Step 5: Document Changes
Leave comments in LLMConfig:

```swift
static let temperature: Double = 0.5
// Reduced from 0.7 for more consistent work log summaries
// Verified with 20+ test queries on 2026-01-08
```

---

## Streaming-Specific Parameters

Streaming doesn't require different parameter tuning, but affects perception:

| Aspect | Impact |
|--------|--------|
| **Temperature** | Perceived as more varied (tokens arrive individually) |
| **Frequency Penalty** | Better perceived quality (user sees repetition avoidance) |
| **Min-P** | More noticeable (users see fewer "weird" tokens) |

---

## Tool Use & Parameters

When using Claude's tool calling for web search:

```swift
LLMConfig.enableToolUse = true
LLMConfig.temperature = 0.5      // Deterministic: decides when to search
LLMConfig.frequency_penalty = 0.1  // Some variability in phrasing
```

**Recommendation**: Tool use decision-making is most reliable at `temperature: 0.3-0.7`, where Claude is focused but not locked into one pattern.

---

## Cost Optimization

Parameters don't directly affect cost, but they influence token usage:

| Tuning | Token Impact | Cost Impact |
|--------|--------------|-------------|
| Lower `temperature` | Fewer tokens (more focused) | -5-10% |
| Higher `top_p` + `min_p` | Slightly fewer unusual tokens | -2-3% |
| Streaming | No direct impact | 0% (same tokens) |
| Tool use | +1 extra request if triggered | +10-20% (if search needed) |

---

## Troubleshooting

### Problem: Responses are too short
```swift
// Not a parameter issue—check:
- Is max_tokens set too low? (currently 12000, usually fine)
- Try decreasing frequency_penalty if model is being overly conservative
LLMConfig.frequencyPenalty = -0.5  // Allow more natural length
```

### Problem: Responses are repetitive
```swift
// Increase any of these:
LLMConfig.frequency_penalty = 0.5
LLMConfig.presence_penalty = 0.3
LLMConfig.repetitionsPenalty = 1.3
```

### Problem: Inconsistent quality
```swift
// Decrease randomness:
LLMConfig.temperature = 0.4
LLMConfig.topP = 0.95
LLMConfig.minP = 0.05
```

### Problem: Responses miss obvious information
```swift
// Increase focus:
LLMConfig.temperature = 0.4  // Too creative?
LLMConfig.minP = 0.1         // Filtering out good tokens?
```

### Problem: Tool isn't deciding to search
```swift
// Web search is optional for Claude; if query doesn't need it:
// Claude won't search even with enableToolUse = true
// This is correct behavior—let Claude decide
// If you WANT to force search, consider prompting explicitly:

let systemPrompt = """
You are an analyst. Use web search for current information or facts \
you're uncertain about. Always search for recent events.
"""
LLMConfig.activeSystemPrompt = systemPrompt
```

---

## Advanced: Custom Presets

Add to LLMConfig.swift for easy switching:

```swift
enum ResponseStyle {
    case factual
    case balanced
    case creative
    case technical
    
    var config: (temperature: Double, topP: Double, frequency: Double, presence: Double) {
        switch self {
        case .factual:
            return (0.2, 1.0, 0.0, 0.0)
        case .balanced:
            return (0.7, 1.0, 0.0, 0.0)
        case .creative:
            return (1.2, 0.9, 0.3, 0.5)
        case .technical:
            return (0.4, 0.95, 0.2, 0.1)
        }
    }
}

func applyStyle(_ style: ResponseStyle) {
    let config = style.config
    temperature = config.temperature
    topP = config.topP
    frequencyPenalty = config.frequency
    presencePenalty = config.presence
}
```

Usage:
```swift
LLMConfig.applyStyle(.technical)  // Switch to technical mode instantly
```

---

## Testing & Validation

### Test Dataset
Create a set of representative queries:

```swift
let testQueries = [
    ("Extract dates from @2026-01", .factual),
    ("Summarize my work patterns", .balanced),
    ("Generate 5 alternative interpretations", .creative),
    ("Analyze architecture of @recent-design", .technical),
]

for (query, expectedStyle) in testQueries {
    let response = try await service.fetch(userMessage: query)
    // Manually evaluate if response matches expected style
    print("Query: \(query)")
    print("Result: \(response.prefix(200))...")
    print("---")
}
```

### Metrics to Monitor
- **Accuracy**: Factual correctness on extraction tasks
- **Consistency**: Same query → similar responses
- **Relevance**: Response addresses the query
- **Efficiency**: Short queries get short answers
- **Diversity**: Creative queries produce varied outputs

---

## OpenRouter-Specific Notes

OpenRouter supports all Claude and third-party models. Parameter support varies:

| Parameter | Claude 3.5 | Haiku | Persistence |
|-----------|-----------|-------|-------------|
| temperature | ✓ | ✓ | Full support |
| top_p | ✓ | ✓ | Full support |
| frequency_penalty | ✓ | ✓ | Full support |
| presence_penalty | ✓ | ✓ | Full support |
| repetition_penalty | ✓ | ~(model-specific) | OpenRouter-specific |
| min_p | ✓ | ✓ | Full support |

*Note: Haiku 4.5 supports all parameters. Some OpenRouter-only parameters may have limited model support.*

---

## Migration Path

If switching between models, adjust parameters:

```swift
// When upgrading to more capable model:
model: "anthropic/claude-opus-4.5"
temperature = 0.6  // Can handle lower temp for more complex reasoning

// When using faster model for simple queries:
model: "anthropic/claude-haiku-4.5"
temperature = 0.8  // Slightly higher for better coverage
frequency_penalty = 0.2  // Compensate for less capable model
```
