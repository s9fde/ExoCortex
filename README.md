# ExoCortex

An encrypted personal work log for macOS with AI assistance via OpenRouter.

![Platform: macOS](https://img.shields.io/badge/platform-macOS-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

## Features

- 🔐 **Encrypted Storage** - AES-256-GCM encryption with password-derived keys
- 🔑 **Biometric Unlock** - Touch ID/Face ID support via macOS Keychain
- 📝 **Markdown Editor** - Rich text editing with syntax highlighting
- ✅ **Todo Management** - Track tasks with `- [ ]` checkbox syntax
- 🤖 **AI Integration** - Ask questions with `#p` tag, get responses from Claude
- 🔍 **Smart Filtering** - Filter by tags, todos, and custom queries
- 📂 **Hierarchical Sidebar** - Apple Mail-style collapsible view groups

## Screenshots

*Coming soon*

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16.0 or later
- OpenRouter API key (for AI features)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/ExoCortex.git
cd ExoCortex
```

### 2. Configure API Key (Optional)

For AI features, get an API key from [OpenRouter](https://openrouter.ai/keys) and set it:

**Option A:** Environment Variable (recommended)
```bash
export OPENROUTER_API_KEY="sk-or-v1-your-key-here"
```

**Option B:** Edit the config file
Edit `ExoCortex/LLMConfig.swift` and replace `YOUR_API_KEY_HERE` with your key.

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

Ask the AI questions using the `#p` tag:
```markdown
#p What are my open todos for today?
```

The AI will analyze your log context and respond with helpful insights.

## Architecture

```
ExoCortex/
├── ExoCortexApp.swift      # App entry point
├── ContentView.swift       # Main UI with sidebar navigation
├── LogViewModel.swift      # Business logic and state management
├── LogRepository.swift     # Encrypted file storage
├── CryptoService.swift     # AES-256-GCM encryption
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
- Encryption keys are derived using PBKDF2 with 100,000 iterations
- Data is encrypted at rest using AES-256-GCM
- Biometric authentication uses macOS Secure Enclave
- API keys can be set via environment variables to avoid hardcoding

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenRouter](https://openrouter.ai) for AI API access
- [Anthropic Claude](https://anthropic.com) for AI responses
