# ExoCortex Scope System: Final Design Specification

## Executive Summary

**Three-tag system using `<<tag` / `>>tag` + `#tag` syntax**

```
<<2026-01-07               Block-open (accessible on German keyboards)
  Daily content
  <<meeting                Nested block
    Meeting notes
    - [ ] Task #urgent     Line-only tag
  >>meeting                Block-close
>>2026-01-07

- [ ] Todo #personal       Standalone line tag
```

**Rationale**:
- ✅ Equal keyboard access on US QWERTY and German QWERTZ
- ✅ Clear directionality (`<` open, `>` close)
- ✅ No markdown conflicts (double-char unambiguous)
- ✅ Mobile accessible
- ✅ Hierarchical scoping with explicit boundaries
- ✅ Three distinct semantic roles

---

## Part 1: Syntax Definition

### Tag Types

#### 1. Block-Open: `<<tagname`

```
<<2026-01-07
  content...
```

- **Syntax**: `<<` followed by valid tag name
- **Position**: Line start or after whitespace
- **Effect**: Pushes scope onto hierarchical stack
- **Nesting**: Can open multiple blocks sequentially or nested
- **Semantics**: "Entering scope"

#### 2. Block-Close: `>>tagname`

```
  >>meeting
```

- **Syntax**: `>>` followed by tag name (must match most recent `<<tagname`)
- **Position**: Line start or after whitespace
- **Effect**: Pops scope from stack
- **Validation**: Must match top of stack (error if mismatch)
- **Semantics**: "Exiting scope"

#### 3. Line-Only: `#tagname`

```
- [ ] Review docs #urgent
Evening reflection #personal
Followup post #follow-up #bob
```

- **Syntax**: `#` followed by tag name
- **Position**: Anywhere on line (start, middle, end)
- **Multiplicity**: Multiple per line (space-separated)
- **Effect**: Labels this line (no stack change)
- **Semantics**: "Metadata tag for this line"

---

### Tag Name Validation

```
VALID:
  <<2026-01-07         Date tag (special, recognized as structural)
  <<meeting            Simple name
  <<project-x          Hyphenated name
  <<action_items       Underscored name
  <<MeetingNotes       CamelCase (normalized to lowercase)
  #urgent              Line tag
  #follow-up           Hyphenated line tag

INVALID:
  <<2026-01-07-note    Date only YYYY-MM-DD (no extra)
  <<-leading           Hyphen cannot lead
  << tag               Space not allowed in tag name
  #                    Tag name required (not just hash)
```

**Format**: `[a-zA-Z][a-zA-Z0-9_-]*` (alphanumeric + hyphen/underscore, must start with letter)

**Case Handling**: Case-insensitive when matching
- `<<work` and `<<Work` refer to same scope
- Normalized to lowercase internally
- User can use any case when typing

---

## Part 2: Parsing Algorithm

### Pseudocode

```
STATE:
  blockStack: Stack<String>           // Tracks <<tag opens
  currentLine: String                 // Current line being parsed
  scopePath: [String]                 // All active scopes (block stack)
  lineTags: [String]                  // #tags on current line
  blocks: [ScopeBlock]                // Output: content blocks with scope
  errors: [ScopeError]                // Output: validation errors

FOR EACH line IN logText:
  lineTags = []
  
  // Scan line left-to-right for all markers
  WHILE scanning line:
    IF found "<<tagname":
      tagname_lower = tagname.lowercase()
      blockStack.push(tagname_lower)
      scopePath.append(tagname_lower)
    
    ELSE IF found ">>tagname":
      tagname_lower = tagname.lowercase()
      IF blockStack.top == tagname_lower:
        blockStack.pop()
        scopePath.dropLast()
      ELSE:
        errors.append(ScopeError.mismatchedClose(
          expected: blockStack.top,
          found: tagname_lower,
          line: currentLineNumber
        ))
    
    ELSE IF found "#tagname":
      tagname_lower = tagname.lowercase()
      lineTags.append(tagname_lower)
  
  // If line has content (not just markers), create block
  IF line has actualContent (stripped of markers):
    scopeForThisLine = scopePath + lineTags
    block = ScopeBlock(
      scopePath: scopeForThisLine,
      lineScopes: lineTags,
      content: actualContent,
      lineNumber: currentLineNumber,
      contentRange: calculateRange(in: originalText)
    )
    blocks.append(block)

// End-of-file validation
IF blockStack not empty:
  unclosedTags = blockStack.contents()
  FOR EACH tag IN unclosedTags:
    errors.append(ScopeError.unclosedAtEOF(
      tags: unclosedTags,
      openedAt: lineNumbers
    ))

RETURN ParseResult(blocks: blocks, errors: errors)
```

---

### Step-by-Step Example

```
INPUT:
 1| <<2026-01-07
 2| Morning standup
 3|
 4| <<meeting
 5| Attendees: Alice, Bob
 6| - [ ] Review docs #urgent
 7| - [ ] Deploy hotfix #critical
 8|
 9| <<action-items
10| - [ ] Notify ops team #alice
11| - [ ] Run deploy tests #testing
12| >>action-items
13|
14| >>meeting
15|
16| Evening reflection #personal
17| >>2026-01-07


PARSING TRACE:

Line 1: <<2026-01-07
  → blockStack.push("2026-01-07")
  → scopePath = ["2026-01-07"]
  → No content (marker only)

Line 2: "Morning standup"
  → No markers
  → blockStack = ["2026-01-07"]
  → Create Block(scopePath: ["2026-01-07"], content: "Morning standup")

Line 3: (blank) → Skip (no content)

Line 4: <<meeting
  → blockStack.push("meeting")
  → scopePath = ["2026-01-07", "meeting"]
  → No content (marker only)

Line 5: "Attendees: Alice, Bob"
  → No markers
  → Create Block(scopePath: ["2026-01-07", "meeting"], content: "Attendees: Alice, Bob")

Line 6: "- [ ] Review docs #urgent"
  → Found #urgent → lineTags = ["urgent"]
  → scopePath = ["2026-01-07", "meeting"] + lineTags = ["urgent"]
  → Create Block(scopePath: ["2026-01-07", "meeting", "urgent"], content: "- [ ] Review docs")

Line 7: "- [ ] Deploy hotfix #critical"
  → Found #critical → lineTags = ["critical"]
  → Create Block(scopePath: ["2026-01-07", "meeting", "critical"], content: "- [ ] Deploy hotfix")

Line 9: <<action-items
  → blockStack.push("action-items")
  → scopePath = ["2026-01-07", "meeting", "action-items"]
  → No content

Line 10: "- [ ] Notify ops team #alice"
  → Found #alice → lineTags = ["alice"]
  → Create Block(scopePath: ["2026-01-07", "meeting", "action-items", "alice"], ...)

Line 11: "- [ ] Run deploy tests #testing"
  → Found #testing → lineTags = ["testing"]
  → Create Block(scopePath: ["2026-01-07", "meeting", "action-items", "testing"], ...)

Line 12: >>action-items
  → blockStack.top == "action-items" ✓ Match
  → blockStack.pop()
  → scopePath = ["2026-01-07", "meeting"]
  → No content

Line 14: >>meeting
  → blockStack.top == "meeting" ✓ Match
  → blockStack.pop()
  → scopePath = ["2026-01-07"]
  → No content

Line 16: "Evening reflection #personal"
  → Found #personal → lineTags = ["personal"]
  → Create Block(scopePath: ["2026-01-07", "personal"], ...)

Line 17: >>2026-01-07
  → blockStack.top == "2026-01-07" ✓ Match
  → blockStack.pop()
  → scopePath = []
  → No content

EOF:
  → blockStack.empty() ✓ All scopes closed
  → No errors

RESULT:
  8 content blocks, no errors
```

---

## Part 3: Data Structures

### ScopeBlock

```swift
struct ScopeBlock {
    /// Ordered tags active for this content (root to leaf)
    /// Example: ["2026-01-07", "meeting", "urgent"]
    let scopePath: [String]
    
    /// Line-only tags on this specific line (subset of scopePath)
    /// Example: ["urgent"] (if content was "- [ ] Task #urgent")
    let lineScopes: [String]
    
    /// The actual content text (trimmed of markers)
    let content: String
    
    /// Line number in original document
    let lineNumber: Int
    
    /// Range in original document (for edits/reference)
    let contentRange: Range<String.Index>
    
    /// Depth in hierarchy (0 = root, 1 = first level, etc.)
    var depth: Int { scopePath.count }
    
    /// Check if block matches a scope query
    func matchesQuery(_ tags: [String]) -> Bool {
        // Example: query ["meeting"] matches block with scopePath ["2026-01-07", "meeting", "urgent"]
        // Query must match as suffix of scope path
        guard !tags.isEmpty else { return true }  // Empty query matches all
        return tags.count <= scopePath.count &&
               zip(scopePath.suffix(tags.count), tags)
                   .allSatisfy { $0 == $1.lowercased() }
    }
}
```

### ScopeError

```swift
enum ScopeError: Equatable {
    /// Attempted to close a block that wasn't the most recent open
    case mismatchedClose(expected: String, found: String, line: Int, col: Int)
    //   Expected to close >>meeting but found >>action-items
    
    /// Attempted to close a block that was never opened
    case unopenedClose(tag: String, line: Int, col: Int)
    //   >>work without matching <<work
    
    /// One or more blocks opened but never closed
    case unclosedAtEOF(tags: [(name: String, openedAt: Int)])
    //   <<meeting opened but no >>meeting before EOF
    
    /// Block opened multiple times without closing
    case duplicateOpen(tag: String, line: Int, col: Int, previousLine: Int)
    //   <<work already open at line 5, trying to open again at line 10
    
    /// Invalid tag name syntax
    case invalidTagName(invalid: String, line: Int, col: Int)
    //   <<-invalid or <<123 (must start with letter)
    
    var severity: ErrorSeverity {
        switch self {
        case .unclosedAtEOF: .warning   // Can auto-close
        case .duplicateOpen: .warning   // Likely user forgot close
        default: .error                 // Fatal issue
        }
    }
}

enum ErrorSeverity {
    case warning
    case error
}
```

### ParseResult

```swift
struct ParseResult {
    /// Successfully parsed content blocks
    let blocks: [ScopeBlock]
    
    /// All detected validation errors
    let errors: [ScopeError]
    
    /// Whether parsing succeeded completely
    var isValid: Bool {
        errors.filter { $0.severity == .error }.isEmpty
    }
    
    /// Human-readable error report
    var errorReport: String { /* formatted output */ }
}
```

---

## Part 4: Query System

### Scope Query Syntax

```
@scope:work              # All blocks with "work" in scope path
@scope:2026-01-07       # All blocks tagged with date
@scope:2026-01-07/meeting  # "meeting" blocks nested within date

@line-tag:urgent        # Blocks specifically tagged #urgent on that line
@line-tag:personal      # Blocks specifically tagged #personal
```

### Query Matching

```swift
// Query: @scope:meeting
// Matches blocks where scopePath includes "meeting"
// Examples:
//   scopePath: ["2026-01-07", "meeting"] ✓ Match
//   scopePath: ["2026-01-07", "meeting", "urgent"] ✓ Match
//   scopePath: ["meeting"] ✓ Match
//   scopePath: ["2026-01-07"] ✗ No match

// Query: @scope:2026-01-07/meeting
// Matches with exact path suffix
//   scopePath: ["2026-01-07", "meeting"] ✓ Match
//   scopePath: ["2026-01-07", "meeting", "urgent"] ✓ Match
//   scopePath: ["2026-01-07"] ✗ No match (missing "meeting")
//   scopePath: ["meeting", "2026-01-07"] ✗ No match (wrong order)

// Query: @line-tag:urgent
// Matches blocks with "urgent" in lineScopes
//   lineScopes: ["urgent"] ✓ Match
//   lineScopes: ["urgent", "critical"] ✓ Match
//   lineScopes: ["critical"] ✗ No match
```

### Backward Compatibility

```
OLD SYSTEM → NEW SYSTEM mapping:

@today              → @scope:{current-date}
                      (calculate today's date tag)

@week               → Union of @scope:{YYYY-MM-DD} for last 7 days

@last:20            → Last 20 content blocks (independent of scopes)

@tag:work           → @line-tag:work
                      (work tags on individual lines)

@todos              → @line-tag:[ ]
                      (unchecked checkboxes, treated as line tag)

EXAMPLES:

Old:   "Analyze @today and @tag:work"
New:   "Analyze @scope:2026-01-07 and @line-tag:work"

Old:   "Summary @week #urgent"
New:   "Summary @scope:2026-01-06 @scope:2026-01-05 ... @scope:2025-12-31"
       (or implemented as range query in new system)

Old:   "@last:10 items"
New:   "Last 10 content blocks" (independent of scope syntax)
```

---

## Part 5: Validation Strategy

### Multi-Tier Validation

#### Tier 1: Real-Time While Typing (Silent)
- **When**: User actively typing
- **What**: Nothing (don't distract)
- **Output**: None

#### Tier 2: Background After Idle (Non-Blocking)
- **When**: 2 seconds without edits
- **What**: Validate recent window (last 20 lines + 24 hours back)
- **Output**: Gutter indicators, no popups

```
Gutter display:
  ✓ Green check — scope properly paired
  ⚠️ Orange warning — unclosed at EOF
  ✗ Red X — unopened close or mismatch
  🔵 Blue dot — current scope breadcrumb (on hover)
```

#### Tier 3: Pre-Query (Blocking)
- **When**: User presses "Ask AI" button
- **What**: Full file validation
- **Output**: Error drawer if issues

```
SCOPE VALIDATION - 1 error found

Line 12: ERROR - Unopened close tag
  >>meeting
  ^^^^^ No matching <<meeting in scope stack
  Last opened: <<project at line 5

  Suggestion: Did you forget to close >>project first?

[Proceed Anyway] [Auto-Fix] [Cancel]
```

#### Tier 4: On-Demand (Comprehensive)
- **When**: User clicks "Check Scopes" button
- **What**: Full file validation with suggestions
- **Output**: Comprehensive report with fixes

### Validation Scope Options

```swift
enum ValidationScope {
    case recent(lines: Int = 20)      // Recent edits only
    case window(days: Int = 3)        // Last N days back
    case full                          // Entire file
}
```

---

## Part 6: Editor Integration

### Visual Indicators

```
1 | <<2026-01-07                   ✓
2 |   Morning notes
3 |   
4 |   <<meeting                    [← Breadcrumb on hover: [2026-01-07 > meeting]]
5 |   Attendees: Alice, Bob
6 |   - [ ] Review docs #urgent
7 |   >>meeting                    ✓ Closes matching <<meeting
8 |
9 | Evening #personal
10|   >>2026-01-07                  ✓
```

### Breadcrumb Display

When cursor is over a scope marker:
```
Scope path: 2026-01-07 > meeting > (current line)
```

When hovering over content:
```
Scope path: 2026-01-07 > personal
```

### Error Panel Layout

```
┌─ SCOPE VALIDATION
├─ Status: 1 critical error, 1 warning
├─
├─ Line 12 (ERROR):
│  >>meeting
│  ✗ Unopened close tag
│    Last opened: <<project (line 5)
│    Did you mean >>project?
├─
├─ Line 20 (WARNING):
│  <<followup
│  ⚠️ Unclosed at end of file
│    Auto-closed (line 20)
│
└─ [Proceed] [Auto-Fix] [Cancel]
```

---

## Part 7: Keyboard Accessibility

### Table: Key Sequences by Keyboard

| Keystroke | US QWERTY | German QWERTZ | Effort |
|-----------|-----------|---------------|--------|
| `<` | Shift+, | Shift+, | ✅ Identical (easy) |
| `>` | Shift+. | Shift+. | ✅ Identical (easy) |
| `<<` | Shift+,, Shift+, | Shift+,, Shift+, | ✅ Two presses (rhythmic) |
| `>>` | Shift+., Shift+. | Shift+., Shift+. | ✅ Two presses (rhythmic) |
| `#` | Shift+3 | Shift+{ (hard) | ⚠️ US easy, German hard |

### Mobile Accessibility

- `<` and `>` available on most soft keyboards
- `#` universally supported (social media familiarity)
- Double tap (`<<`, `>>`) natural and fast

---

## Part 8: Example Log File

```
<<2026-01-07
Morning standup notes

<<meeting
Attendees: Alice, Bob, Carol
Location: Conference room A
Time: 10:00-11:00

- [ ] Approve designs #urgent #bob
- [ ] Review pull requests #alice
- [ ] Schedule follow-up #carol

<<action-items
- [ ] Send email to design team #bob
- [ ] Deploy hotfix to staging #alice
- [ ] Set up 1:1 with PM #carol #follow-up
>>action-items

<<decisions
Approved design spec for v2.0 #product
Timeline: 3 weeks #sprint
>>decisions

>>meeting

Afternoon:
- [ ] Gym session #personal #health
- [ ] Read documentation #learning
- [ ] Grocery shopping #errand

Evening reflection #personal

>>2026-01-07

<<2026-01-08
New day begins...
>>2026-01-08
```

---

## Part 9: Migration from Old System

### Old Format Detection

```
--- 2026-01-07          ← Detect old date header
content
--- 2026-01-08
```

### Auto-Migration Process

1. Detect `---` followed by date pattern
2. Convert to `<<YYYY-MM-DD`
3. Insert matching `>>YYYY-MM-DD` at next `---` or EOF
4. Offer "Save in new format?" dialog

### Example Migration

```
OLD:
--- 2026-01-07
Morning notes
content
--- 2026-01-08
More content

MIGRATED TO:
<<2026-01-07
Morning notes
content
>>2026-01-07

<<2026-01-08
More content
>>2026-01-08
```

---

## Part 10: Implementation Roadmap

### Phase 1: Core Parser ✓
- [ ] Regex tokenization for `<<tag`, `>>tag`, `#tag`
- [ ] Stack-based scope tracking
- [ ] Error detection (mismatches, unopened, unclosed)
- [ ] ScopeBlock generation with hierarchical paths
- [ ] Unit tests (50+ test cases)

### Phase 2: Validation Engine ✓
- [ ] Three-tier validation (real-time, idle, pre-query)
- [ ] Gutter indicators
- [ ] Error panel UI
- [ ] Breadcrumb display
- [ ] Integration tests

### Phase 3: Query & Extraction ✓
- [ ] New `@scope:` query syntax
- [ ] Backward compatibility layer (old `@` syntax)
- [ ] Scope path matching
- [ ] Union queries (multiple scopes)
- [ ] Query tests

### Phase 4: UI Integration ✓
- [ ] Editor gutter rendering
- [ ] Breadcrumb on hover
- [ ] Error drawer implementation
- [ ] Status bar indicator
- [ ] Auto-fix suggestions

### Phase 5: Migration Tools (Optional)
- [ ] Detect old `---` format
- [ ] Auto-conversion UI
- [ ] Migration preview
- [ ] Undo migration option

---

## Part 11: Design Rationale

### Why `<<` and `>>` instead of `{}`?

| Factor | `<<tag`/`>>tag` | `{tag`/`}tag` |
|--------|---|---|
| **US Keyboard** | Shift+, / Shift+. | Shift+[ / Shift+] |
| **German Keyboard** | Shift+, / Shift+. | AltGr+7 / AltGr+0 |
| **Mobile** | Easy (`<>` standard) | Moderate (less common) |
| **Visual pairing** | Angle brackets clear | Curly brackets clear |
| **Markdown conflict** | None (`<<` unambiguous) | None (literal characters) |
| **International** | Identical access | US worst, German hard |

**Decision**: `<<tag`/`>>tag` provides equal accessibility across keyboard layouts.

### Why Three Tags Instead of Two?

| System | Block | Line | Verdict |
|--------|-------|------|---------|
| **One tag** | Would need closing everywhere | Tedious | ❌ Verbose |
| **Two tags** | `<<` and `>>` | Combine with `#` | ✅ **Combined** |
| **Three tags** | `{` / `}` | `#` (some designs) | Would work but less accessible |

**Decision**: Three tags (`<<`, `>>`, `#`) provide clean separation of concerns.

### Why Markdown Stays True

- Uses literal ASCII characters (no special rendering)
- `<<` double-char prevents conflicts with single-`<` email syntax
- `#` at mid/end-line is literal in markdown (not heading)
- No interference with CommonMark spec
- Renders as plain text in markdown viewers

---

## Conclusion

This design delivers:

✅ **International accessibility** — Equal keyboard access US and German
✅ **Clear semantics** — Three distinct tag types for three jobs
✅ **Explicit scoping** — Open/close markers unambiguous
✅ **Hierarchical** — Stack-based nesting with validation
✅ **Markdown-safe** — No conflicts, renders as plain text
✅ **Mobile-friendly** — Standard keyboard characters
✅ **Backward-compatible** — Maps old `@` queries automatically
✅ **Parseable** — O(n) algorithm, simple validation
✅ **Well-integrated** — Gutter indicators, breadcrumbs, error panels

**Ready for implementation.**
