# ExoCortex Architecture

## Overview

ExoCortex is an encrypted personal work log for iOS and macOS with AI assistance via OpenRouter. The codebase follows modern Swift architecture patterns with strict concurrency, clear separation of concerns, and comprehensive error handling.

## Core Principles

- **Encryption-first**: All data encrypted at rest with ChaCha20-Poly1305
- **Async/await**: Full Swift Concurrency compliance (Swift 6 strict mode)
- **Actor-based services**: Thread-safe isolation for crypto, keychain, and API operations
- **Observable state**: SwiftUI integration via @Observable pattern
- **Scope-based queries**: Hierarchical block syntax for LLM context extraction

## Project Structure

```
ExoCortex/
├── ExoCortexApp.swift           # App entry point
├── ContentView.swift            # Main UI with sidebar and lock screen
├── LogViewModel.swift           # Central state management
├── LogRepository.swift          # Encrypted file persistence (actor)
├── CryptoService.swift          # ChaCha20-Poly1305 encryption (actor)
├── KeychainService.swift        # Biometric password storage (actor)
├── OpenRouterService.swift      # LLM streaming API client (actor)
├── LLMConfig.swift              # LLM configuration and defaults
├── TagQueryParser.swift         # Filter query parsing (tags, booleans)
├── LLMQuery.swift               # LLM query detection and parsing
├── SettingsView.swift           # App configuration UI
├── TextKit2View.swift           # Multi-platform text editor
├── NamedView.swift              # Saved filter model
├── TextKit2Editor.swift         # TextKit2 wrapper (macOS)
└── Scoping/                     # Hierarchical scope system
    ├── ScopeParser.swift         # Core parser (<<tag ... >>tag / !!tag)
    ├── ScopeBlock.swift          # Content block with scope path
    ├── ScopeError.swift          # Validation error types
    ├── ScopeQuery.swift          # @scope reference parsing
    ├── ScopeValidator.swift      # Multi-day validation
    ├── ScopeContextResolver.swift # LLM context extraction
    └── ValidationSheet.swift     # Error UI component
```

## Key Components

### Authentication & Security

**CryptoService (Actor)**
- ChaCha20-Poly1305 symmetric encryption
- PBKDF2 key derivation (150,000 iterations)
- Envelope format: [version (1 byte) | salt (16 bytes) | ciphertext]

**KeychainService (Actor)**
- Biometric-protected password storage (Face ID / Touch ID)
- Pre-authentication pattern for sandboxed apps
- API key and LLM configuration persistence
- UserDefaults tracking for biometric state

### State Management

**LogViewModel (@Observable)**
- Central coordinator for all app state
- Manages lock/unlock lifecycle
- Handles text change detection and autosave
- Coordinates LLM query detection and execution
- Maintains 3-level undo stack for LLM edits

### Data Persistence

**LogRepository (Actor)**
- Loads/saves encrypted log files
- Supports both local and iCloud storage
- Device-native file handling

### AI Integration

**OpenRouterService (Actor)**
- Streaming LLM API client
- Claude Opus 4.5 by default
- Configurable models and system prompts
- Error handling and retry logic

**LLMQuery & LLMQueryDetector**
- Detects `??` (single-line) and `<? >?` (block) queries
- Extracts @scope references from prompts
- Coordinates with ScopeContextResolver

### Scope System (Hierarchical Block Syntax)

**Core Syntax**
```
<<tag          Block open (e.g., <<260108)
  Content
>>tag          Block close (e.g., >>260108)

!!tag          Inline tag (e.g., !!urgent)
```

**Query References**
- `@scope_name` in prompts references scope blocks
- AND logic: multiple @scopes all must match
- Validation: checks scopes exist before LLM execution

**ScopeParser**
- Full document parse with nested block support
- Validates matching open/close tags
- Reports unclosed/mismatched blocks
- Date boundaries enforcement

**ScopeValidator**
- Pre-query validation (last 10 days by default)
- Manual full-document checks
- Error collection with fix suggestions

**ScopeContextResolver**
- Extracts content from matched scopes
- Integrates with LogViewModel for LLM execution
- Handles multi-scope AND queries

### Filtering

**TagQueryParser**
- Boolean expression parser (&&, ||, !, parentheses)
- Shunting-yard algorithm for precedence
- Pattern matching: tags (#tag), todos (todo:open, todo:done), text
- AST evaluation

### UI Architecture

**ContentView**
- Conditional rendering: lock screen or split view
- Sidebar with views navigation
- Main editor area with filtered text
- Top toolbar with save status and LLM indicators

**SettingsView**
- View management (create, edit, delete)
- API key configuration
- Keychain password management
- LLM model and system prompt customization
- Biometric unlock setup

**TextKit2View**
- macOS: NSView-based wrapper around NSTextView
- iOS: UIView-based wrapper around UITextView
- Efficient rendering for large buffers

## Data Flow: LLM Query Execution

```
User types query (?? or <? >?)
  ↓
TextDidChange detected
  ↓
LLMQueryDetector finds completed query
  ↓
Extract @scope references
  ↓
ScopeContextResolver resolves scopes → context
  ↓
Validate: check scopes exist
  ↓
[Push undo checkpoint]
  ↓
Build LLM message (system prompt + context + instruction)
  ↓
OpenRouterService.fetch(streaming)
  ↓
Append/replace response
  ↓
Update filtered view
```

## Configuration

**LLMConfig** (static properties)
- `apiKey`: User-provided OpenRouter key (loaded from Keychain)
- `activeModel`: Selected model ID
- `activeSystemPrompt`: Custom instructions
- `maxTokens`: Response length limit (12,000)
- `baseURL`: OpenRouter API endpoint

**Default Model**: `anthropic/claude-opus-4.5`

**Default System Prompt**: Instructs Claude to be a direct, scoped editor/analyzer for the personal work log.

## Error Handling

### CryptoServiceError
- `derivationFailed`, `encryptionFailed`, `decryptionFailed`, `invalidEnvelope`

### KeychainServiceError
- `biometryUnavailable`, `biometryFailed`, `itemNotFound`, `unexpectedStatus`

### ScopeError
- `unclosedTag`, `mismatchedClose`, `noMatches`, `parseError`, `invalidScope`

### LLM Errors
- Pre-execution validation catches missing scopes
- Run-time errors append error messages to log
- 3-level undo stack for recovery

## File Deletion & iCloud Sync

- When deleting views, content is not removed (soft delete pattern not used)
- iCloud sync via NamedView observation of KeyValueStore
- Fallback to local storage if iCloud unavailable

## Best Practices Implemented

✅ **Swift 6 Strict Concurrency**
- All mutable state in @Observable classes or actors
- Proper async/await throughout
- No data races or force-unwrapping

✅ **Memory Management**
- No retain cycles (weak refs where needed)
- Actor isolation prevents common concurrency issues

✅ **Error Handling**
- All errors typed (no generic Error)
- LocalizedError trait for user-facing messages
- Graceful fallbacks (e.g., iCloud → local storage)

✅ **Code Organization**
- MARK comments for clarity
- Single responsibility per file
- Clear public/private boundaries

## Testing Recommendations

- Unit tests for ScopeParser (complex parsing logic)
- Integration tests for LLM query flow
- Security tests for encryption key derivation
- UI snapshot tests for Views

## Future Improvements

- Full-text search index for large logs
- Query history and saved searches
- LLM query composition (results as input to next query)
- Plugin system for custom scope handlers
- Export to Markdown/JSON
