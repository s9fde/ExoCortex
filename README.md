# ExoCortex

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

### AI Prompts

ExoCortex supports two modes of AI interaction:

#### Read-Only Mode (`#p` or `#ro`)
Ask the AI questions - responses are appended below your prompt:
```markdown
#p @today What did I accomplish?
#ro @week Give me a weekly summary
```

#### Edit Mode (`#do`)
Let the AI directly modify sections of your log:
```markdown
#do @today Mark all completed todos as done
#do @week Summarize each day into 3 bullet points
#do @last:20 Fix any typos
```

**Important:** Edit mode requires a contiguous scope (`@today`, `@week`, `@last:N`, `@log`). Non-contiguous scopes like `@tag:xyz` or `@todos` don't support edit mode.

**Undo AI edits:** Press `⌘Z` or click the undo button to revert the last AI edit (up to 3 levels).

#### Context References

Use `@-references` to scope which parts of your log are sent with the prompt. This helps reduce costs and keeps context relevant.

| Reference | Description | Example |
|-----------|-------------|---------|
| `@log` | Entire log (truncated if too large) | `#p @log summarize my work` |
| `@today` | Today's entries only | `#p @today what did I accomplish?` |
| `@week` | Last 7 days of entries | `#p @week weekly summary` |
| `@last:N` | Last N lines | `#p @last:50 recent context` |
| `@tag:xyz` | Lines containing `#xyz` | `#p @tag:work summarize work tasks` |
| `@todos` | All open todo items `[ ]` | `#p @todos prioritize my tasks` |

**Combine references** for precise scoping:
```markdown
#p @todos @week What should I focus on this week?
#p @tag:project-alpha @todos list remaining tasks
#p @today @tag:meeting summarize today's meetings
```

**Without references**, only your prompt text is sent (no log context):
```markdown
#p explain how async/await works in Swift
```

#### Cost & Privacy Tips

- **Use specific scopes**: `@today` or `@tag:xyz` instead of `@log` to minimize tokens
- **Combine filters**: `@todos @tag:work` sends only work-related todos
- **Line limits**: `@last:100` for quick context without full history
- **No context needed?** Omit all `@-references` for general questions

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
├── ContextResolver.swift   # AI context extraction
├── StyledTextEditor.swift  # Markdown text editor
└── SettingsView.swift      # App settings UI
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
