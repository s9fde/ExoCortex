An encrypted personal work log for iOS and macOS with AI assistance via OpenRouter.

![Platform: iOS & macOS](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- 🔐 **Encrypted Storage** - ChaCha20-Poly1305 encryption with PBKDF2 key derivation (150,000 iterations)
- 🔑 **Biometric Unlock** - Face ID / Touch ID support via Secure Enclave & Keychain
- 📝 **Markdown Editor** - Clean, monospaced editor for focused writing
- ✅ **Todo Management** - Track tasks with `- [ ]` checkbox syntax and smart filtering
- 🤖 **AI Integration** - Integrated Claude AI via OpenRouter for summaries, analysis, and editing
- 🔍 **Smart Filtering** - Powerful boolean query parser for tags, todos, and text
- ☁️ **iCloud Sync** - Automatic synchronization of filter views across devices

## Screenshots

*Coming soon*

## Requirements

- iOS 18.0+ / macOS 15.0+
- Xcode 16.0+
- OpenRouter API key (for AI features)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/ExoCortex.git
cd ExoCortex
```

### 2. Configure API Key (Optional)

For AI features, get an API key from [OpenRouter](https://openrouter.ai/keys) and set it in the app:

Open the app, tap Settings → OpenRouter API Key, and paste your key securely. It will be saved to your Keychain.

### 3. Build and Run

Open `ExoCortex.xcodeproj` in Xcode and run (⌘R).

## Usage

### Encryption

On first launch, you'll be prompted to create a password. This password encrypts your work log using AES-256-GCM encryption.

### Writing Entries

Just start typing! Your work log is automatically saved and encrypted.

### Todos

Create todos with checkbox syntax:
```markdown
- [ ] Open task
- [x] Completed task
```

Click checkboxes to toggle, or filter by `todo:open` or `todo:done`.

### Tags

Use hashtags to organize entries:
```markdown
#work Meeting notes from today
#personal Grocery list
```

Filter by clicking a tag or typing it in a filter view.

### AI Queries with `?`

ExoCortex uses a unified `?` query system integrated with the scope grammar. The LLM decides whether to append findings or modify content based on your instruction.

#### Single-Line Queries (`??`)

Ask the AI questions - responses are appended below:
```markdown
?? What were my main accomplishments @today?

?? How many open todos do I have @2026-01-08?

?? Summarize the key decisions @week
```

#### Multi-Line Queries (`<? >?`)

For complex prompts, use block syntax:
```markdown
<<?
  Analyze the following and provide:
  - Key themes
  - Action items
  - Blockers
  
  Context: @2026-01-08 @work
>><?

<<?
  Reorganize my todos by priority
  Format: critical → high → medium → low
  
  @today
>><?
```

#### How It Works

1. Type your query with `??` (single-line) or `<? >?` (multi-line)
2. Include one or more `@scope` references (e.g., `@2026-01-08`, `@today`, `@work`)
3. Press Enter
4. LLM receives your scope's context + instruction
5. **LLM decides**: Append analysis or modify content based on your wording
6. Response appears below your query

#### Scope References

Use `@scope` notation to specify which content to include:

| Reference | Description | Example |
|-----------|-------------|---------|
| `@2026-01-08` | Specific date entries | `?? analyze @2026-01-08` |
| `@today` | Today's entries only | `?? summarize @today` |
| `@week` | Last 7 days | `?? weekly review @week` |
| `@last:N` | Last N lines | `?? recap @last:50` |

**Combine scopes** with AND logic:
```markdown
?? What work did I do? @2026-01-08 @work

<<?
  Link related items
  @project-alpha @todo
>><?
```

#### Examples & Patterns

**Analysis (LLM appends):**
```markdown
?? Count open todos @2026-01-08

?? What themes do you see @week?

<<?
  Analyze these entries for:
  - Productivity patterns
  - Time distribution
  - Areas for improvement
  @2026-01-01 @work
>><?
```

**Editing (LLM modifies):**
```markdown
<<?
  Reformat these as bullet points
  @today
>><?

<<?
  Fix formatting and add timestamps
  @last:100
>><?
```

#### Configuration

Customize LLM behavior in Settings:

- **Model**: Enter OpenRouter model ID (e.g., `anthropic/claude-haiku-4.5`)
- **System Prompt**: Edit the instructions sent with every query

Changes save automatically and take effect on your next query.

#### Tips & Best Practices

- **Be specific**: "Count my open todos" vs "analyze todos" → different LLM behavior
- **Use relevant scopes**: `@today @work` instead of `@week` to reduce tokens and cost
- **Multi-line for complex**: Use `<? >?` when your instruction needs multiple lines
- **Reset defaults**: Settings → System Prompt → Reset button

#### Undo & Safety

- Press `⌘Z` or use the undo button to revert last query result (3-level history)
- Queries are validated before sending (catches scope errors)

## Scope System (Hierarchical Tag-Based Scoping)

ExoCortex uses a modern **hierarchical scope system** with explicit open/close markers for precise LLM context extraction:

```markdown
<<2026-01-08               Block-open (date root)
  Morning work session
  
  <<meeting                Nested block
    Attendees: Alice, Bob
    - [ ] Review designs !!urgent
  >>meeting                Block-close
  
  Evening notes !!personal
>>2026-01-08               Block-close
```

### Tag Syntax

| Syntax | Scope | Example | Use |
|--------|-------|---------|-----|
| `<<tag` / `>>tag` | Multi-line block | `<<meeting ...  >>meeting` | Documents, meetings, sections |
| `!!tag` | Single line only | `- [ ] Task !!urgent` | Metadata, labels, inline tags |

### Query System (AND Logic)

Use `@tag` notation in prompts to query scopes:

```markdown
#p @2026-01-08 @work summarize my work today
#p @meeting !!urgent what's the priority item?
```

- `@` prefix denotes a scope query
- Multiple tags use AND logic (all must match)
- Validation happens before LLM query (catches errors)

### Validation

- **Before-query**: Last 10 days validation (automatic)
- **Manual check**: "Check Scopes" menu item validates full document
- Clear error messages with suggestions for fixes

See [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`plans/SCOPE_SYSTEM_COMPLETION_SUMMARY.md`](plans/SCOPE_SYSTEM_COMPLETION_SUMMARY.md) for detailed documentation.

## Architecture

```
ExoCortex/
├── ExoCortexApp.swift      # App entry point
├── ContentView.swift       # Main UI with sidebar navigation
├── LogViewModel.swift      # Business logic and state management
├── LogRepository.swift     # Encrypted file storage
├── CryptoService.swift     # ChaCha20-Poly1305 encryption
├── KeychainService.swift   # Secure credential storage
├── OpenRouterService.swift # AI streaming API client
├── LLMConfig.swift         # AI configuration
├── NamedView.swift         # Sidebar view model
├── TagQueryParser.swift    # Filter query parsing
├── TextKit2View.swift      # Modern text editor UI
├── SettingsView.swift      # App settings UI
└── Scoping/                # Hierarchical scope system
    ├── ScopeParser.swift           # Core parser (<<tag / >>tag / !!tag)
    ├── ScopeBlock.swift            # Content block with scope path
    ├── ScopeError.swift            # Validation errors
    ├── ScopeQuery.swift            # Query parsing (@tag)
    ├── ScopeValidator.swift        # Validation engine
    ├── ScopeContextResolver.swift  # LLM integration
    └── ValidationSheet.swift       # Error UI
```

## Security

- Passwords are never stored in plaintext
- Encryption keys are derived using PBKDF2 with 150,000 iterations
- Data is encrypted at rest using ChaCha20-Poly1305
- Biometric authentication uses macOS Secure Enclave
- API keys can be set via environment variables to avoid hardcoding

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenRouter](https://openrouter.ai) for AI API access
- [Anthropic Claude](https://anthropic.com) for AI responses
