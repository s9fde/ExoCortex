# Scope System Architecture Redesign

## Overview

Replace the current date-centric scoping model with a **unified, explicitly-paired tag-based hierarchical scoping system**. Use `#tagname` to open scope and `#/tagname` to close it. This approach combines simplicity (familiar HTML-like syntax) with explicitness (impossible to miss scope boundaries) and robustness (comprehensive validation and error detection).

---

## Core Principles

1. **Explicit Pairing**: `#tagname` opens, `#/tagname` closes - clear, unambiguous
2. **Uniform Tag Model**: All scope types (dates, projects, contexts) use same syntax
3. **Hierarchical Nesting**: Scopes can contain other scopes; parser maintains stack
4. **Robust Validation**: Detect mismatches, duplicates, unclosed/unopened tags; report all errors
5. **Mobile-Friendly**: `#` + name + `/` is quick to type, even on small keyboards
6. **Linear Parsing**: Single pass with explicit stack validation makes parsing trivial and fast
7. **HTML-like Semantics**: Familiar syntax from XML/HTML makes it intuitive for most users

---

## Exemplar Format

```
#2026-01-07
Some general thoughts today.

#work
- Task: implement scoping
- [ ] First step
- [ ] Second step
#/work

#personal
Evening reflection on day.
#/personal

#project-x
Specific work context.
More details here.
#/project-x

#/2026-01-07

#2026-01-08
Different day section continues.
#/2026-01-08
```

### Alternative (More Compact)

```
#2026-01-07
General content here.

#work
- Task 1
- Task 2
#/work

#personal
Evening notes.
#/personal

#/2026-01-07
```

**Key**: Every `#tag` must have a matching `#/tag`. Parser validates this and reports mismatches.

---

## Key Concepts

### 1. Scope Hierarchy

Tags create a **hierarchical namespace** with implicit scope boundaries:

- **Root Level**: Lines before any tag (unscoped, or part of implicit "root" scope)
- **First-Level Tags**: #2026-01-07, #work, #personal (establish primary scope)
- **Nested Tags**: Tags introduced within a scope (sub-scopes inherit parent but don't override it)
  
```
#2026-01-07                    <- Opens "2026-01-07" scope
  content...
  #work                        <- Opens "work" subscope (parent: "2026-01-07")
    task content...
    #urgent                    <- Opens "urgent" subscope (parents: "2026-01-07", "work")
      urgent task...
  #personal                    <- Back to personal scope (closes "work", "urgent"; parent: "2026-01-07")
    personal content...
```

### 2. Scope Resolution

For any line of content, determine its complete scope hierarchy:

- **Scope Stack**: List of all active tags, from broadest to most specific
- **Tag Priority** (for equal-level tags):
  - Date tags (YYYY-MM-DD format) > Other tags
  - Later tags in file override earlier ones at same level
  - Indentation/whitespace **NOT** used for hierarchy (mobile constraint)

### 3. Tag Syntax

A tag is:
- **Format**: `#tagname` (case-insensitive internally)
- **Valid Names**: Alphanumeric, hyphens, underscores (a-zA-Z0-9_-)
- **Special**: Dates in YYYY-MM-DD format recognized as date tags
- **Position**: Tags can appear anywhere (start of line, mid-line, end of line)
- **Frequency**: Multiple tags on same line = open all simultaneously at same nesting level

Example valid tags:
```
#2026-01-07                   (date tag)
#work #urgent                 (two tags, same level)
#project-x                    (hyphenated)
#meeting_notes                (underscore)
#ProjectX                     (mixed case)
```

---

## Parsing Strategy: Tag Matching & Validation

### Tag Format

- **Open Tag**: `#tagname` - where `tagname` matches `[a-zA-Z0-9_-]+`
- **Close Tag**: `#/tagname` - **must** match most recent unclosed `#tagname`
- **Position**: Can appear anywhere on a line (start, middle, end)
- **Case Sensitivity**: Tags are case-insensitive (`#work` == `#Work`), normalized to lowercase internally
- **Multiple Tags on One Line**: Allowed, processed left-to-right
  - `#2026-01-07 #work` = open both in order
  - `#/work #/2026-01-07` = close both in order

### Core Validation Rules

1. **Every Open Must Have Close**: `#work` must be paired with `#/work`
2. **Matching Nesting**: If `#A` then `#B` then must be `#/B` then `#/A` (not crossed)
3. **No Unopened Closes**: `#/work` without preceding `#work` is error
4. **No Orphan Opens**: Unclosed `#work` at EOF is error (or auto-close with warning)

### Parsing Algorithm

```swift
INPUT: Full log text
OUTPUT:
  - success: [ScopeBlock] (content with scope paths)
  - errors: [ScopeError] (validation issues)

ALGORITHM:

1. TOKENIZE: Linear scan, extract all tags and content lines
   - Regex: #/(tagname)|#(tagname)
   - Record: { type: "openTag"|"closeTag", name: String, line: Int, col: Int }
   - Content lines between tags marked with current scope stack

2. VALIDATE: Check matching and nesting
   - Maintain stack of open tags: [String]
   - For each openTag: push to stack, record line
   - For each closeTag:
     IF stack.last == tagname.lowercase():
       pop from stack
       record closeTag line
     ELSE:
       ERROR: mismatched close (expected X, got tagname)
   - At EOF: IF stack not empty:
       ERROR: unclosed tags

3. BUILD BLOCKS: Assign scope path to each content line
   - Track which tags are open at each line
   - Each content line gets snapshot of current stack
   - Generate ScopeBlock for each line or content chunk

4. RETURN: Blocks + all errors (non-fatal and fatal)
```

### Error Types & Handling

```swift
enum ScopeError {
    case unopenedClose(tag: String, line: Int, suggestion: String)
    // Example: `#/work` without opening - maybe you meant to open it earlier?
    
    case mismatchedClose(expected: String, found: String, line: Int)
    // Example: opened `#work` but found `#/project` - matching fail
    
    case unclosedAtEOF(tags: [String])
    // Example: `#work` opened but never closed - autoclosed with warning
    
    case duplicateOpen(tag: String, previousLine: Int, line: Int)
    // Example: opened `#work` twice - outer one might be unclosed?
}
```

### Error Reporting

**Strategy**: Collect ALL errors before failing. Report with context.

```
Line 15: ERROR - Unopened close tag
  #/work
  ^^^^^^ No matching #work in scope (last opened: #project at line 10)
  
  Suggestion: Maybe you meant to close #project first?

Line 42: ERROR - Unclosed tag at end of file
  #work (opened at line 40)
  ^^^^ Add #/work to close scope

Status: 2 critical errors found. Parser produced best-effort blocks.
```

### Example Walkthrough

```
Input log:
1 | #2026-01-07
2 | morning notes
3 | #work
4 | - task 1
5 | - task 2
6 | #/work
7 | #personal
8 | evening notes
9 | #/personal
10| #/2026-01-07
11|

Parse result:
  Block 1: line 2, scope: ["2026-01-07"], content: "morning notes"
  Block 2: line 4, scope: ["2026-01-07", "work"], content: "- task 1"
  Block 3: line 5, scope: ["2026-01-07", "work"], content: "- task 2"
  Block 4: line 8, scope: ["2026-01-07", "personal"], content: "evening notes"
  
  Errors: [] (all valid)

Query: @tag:work
Result: "- task 1\n- task 2"
Scope context: ["2026-01-07", "work"]
```

### Complexity

- **Time**: O(n) - single linear pass + regex matching
- **Space**: O(n) - store all blocks + error info
- **Validation**: O(1) per tag (stack operations)
- **Query**: O(m) - filter m blocks for matching scope

---

## Data Structures

### ScopeError

```swift
enum ScopeError: Equatable {
    /// #/tagname without matching opening #tagname
    case unopenedClose(tag: String, line: Int, col: Int)
    
    /// #/expected found but #actual was last opened
    case mismatchedClose(expected: String, found: String, line: Int, col: Int)
    
    /// Unclosed tags at end of file
    case unclosedAtEOF(tags: [(name: String, openedAt: Int)])
    
    /// Tag opened multiple times without closing (nested)
    case duplicateOpen(tag: String, line: Int, col: Int, previousLine: Int)
    
    /// Invalid tag name syntax
    case invalidTagName(name: String, line: Int, col: Int)
    
    var severity: ErrorSeverity {
        switch self {
        case .unclosedAtEOF: .warning  // Can auto-close
        case .duplicateOpen: .warning  // User probably forgot close
        default: .error               // Fatal issues
        }
    }
}

enum ErrorSeverity {
    case warning
    case error
}
```

### ScopeBlock

```swift
struct ScopeBlock {
    /// Ordered tags active for this content (root to leaf)
    let scopePath: [String]
    
    /// The actual content (may be single line or multi-line chunk)
    let content: String
    
    /// Line number in original document
    let lineNumber: Int
    
    /// Range in original document (for edits)
    let contentRange: Range<String.Index>
    
    /// Depth in hierarchy (0 = root unscoped)
    var depth: Int { scopePath.count }
    
    /// Check if block matches scope query
    func matchesQuery(_ tags: [String]) -> Bool {
        // All query tags must be in scopePath (contiguous)
        return tags.isEmpty || (
            !scopePath.isEmpty &&
            zip(scopePath.suffix(tags.count), tags)
                .allSatisfy { $0.0 == $0.1.lowercased() }
        )
    }
}

struct ParseResult {
    /// Successfully parsed blocks
    let blocks: [ScopeBlock]
    
    /// All validation errors (warnings + errors)
    let errors: [ScopeError]
    
    /// Whether parsing was fully successful (no errors)
    var isValid: Bool { errors.filter { $0.severity == .error }.isEmpty }
    
    /// Human-readable error report
    var errorReport: String { /* formatted */ }
}
```

### ScopeParser

```swift
struct ScopeParser {
    /// Parse full log text - always attempts to parse even with errors
    /// Returns blocks + all detected errors for validation/display
    func parse(_ fullText: String) -> ParseResult
    
    /// Extract content matching scope query from parsed blocks
    func extract(scopePath: [String], from blocks: [ScopeBlock]) -> String
    
    /// Find all blocks matching a tag (regardless of path)
    func blocksMatching(tag: String, in blocks: [ScopeBlock]) -> [ScopeBlock]
    
    /// Detect common issues and suggest fixes
    func analyzeErrors(_ errors: [ScopeError]) -> [ScopeFix]  // suggestions
}
```

### ScopeFix

```swift
struct ScopeFix {
    let error: ScopeError
    let suggestion: String  // "Did you forget to close #work at line 5?"
    let canAutoFix: Bool
    let fixedText: String?  // Proposed correction
}
```

---

## Validation Strategy: When & How to Check

### Problem
- Validating while typing = constant errors (tags incomplete most of the time)
- Full-file validation = expensive for large logs
- Users need feedback before LLM queries, but not constant nagging

### Solution: Three-Tier Checking

```swift
enum ValidationTrigger {
    case onDemand        // User presses "Check" button
    case beforeQuery     // Before sending prompt to LLM
    case onTimerIdle     // After 2 seconds of no typing (silent)
    case limitedWindow   // Recent lines + 3 days back
}

struct ValidationScope {
    /// Check only recently edited lines (last 20 lines + edits in past 2sec)
    case recent
    
    /// Check last N days of content
    case lastDays(Int)
    
    /// Check full file
    case full
}
```

### Recommended Behavior

**While typing** (InputDelegate):
- No validation (don't distract)
- User might have open/close tags in progress

**After 2s idle** (optional, non-blocking):
- Validate recent window (~last 20 lines edited + last 24 hours)
- Show subtle indicator in gutter (orange dot = warnings)
- Do not show error popups

**Before LLM query** (required, blocking):
- Validate full file (or user-configured scope)
- Report ALL errors in a drawer/panel
- Offer: "Proceed anyway", "Auto-fix", "Cancel"

**Manual check** (on-demand):
- Full file validation
- Comprehensive error report with fixes
- Visual breadcrumb showing scope hierarchy

### Implementation

```swift
class ScopeValidator {
    /// Low-overhead background check for recent changes
    func validateRecent(_ text: String, lastEditedLines: Int = 20) -> [ScopeError]
    
    /// Check window: recent edits + N days back
    func validateWindow(_ text: String, daysBack: Int = 3) -> [ScopeError]
    
    /// Full file check before critical operation
    func validateFull(_ text: String) -> ParseResult
    
    /// Returns line ranges that are "safe" (no unclosed/unopened issues)
    func safeRanges(_ text: String) -> [Range<Int>]
}
```

**Gutter Indicator Style**:
```
   | Code
1  | #2026-01-07        ✓ (in editor)
2  | work content
3  | #work              ⚠ (warning: unclosed)
4  | - task 1
...
```

**Error Panel (before query)**:
```
SCOPE VALIDATION - 1 error found

Line 3: WARNING - Unclosed tag
  #work
  Auto-fixes available:
  [✓] Add #/work at line 8
  [ ] Remove #work tag
  [✓] Proceed anyway - include all content
```

---

## Tag Position & Scope Duration

### Current Design Issue
Tags can appear anywhere on a line. But this causes ambiguity:

```
- [ ] Buy groceries #work
Does this tag just the checkbox, or lines after it too?

Meeting notes #urgent
More notes
Should everything until #/urgent be urgent?
```

### Three-Tag System

**Option A: Hybrid Three-Tag Model** (RECOMMENDED)

```
#work              Line-only tag (this line only, no pairing needed)
#(work             Block-start tag (spans to next matching #)work)
#)work             Block-end tag (closes #(work)

Examples:

#2026-01-07        Line-only tag for organizational date marker
General content

#(project
Code snippet
Task list
Another section
#)project          Closes the project block

- [ ] Task #work   Tags only this line
- [ ] Task #work   Different task, different line
- [ ] Task #(important
      subtasks here
      #)important
```

**Syntax**:
- `#tagname` - scope applied to **rest of this line only** until `\n`
- `#(tagname` - opens **multi-line block scope**
- `#)tagname` - closes matching `#(tagname`
- No closing needed for `#tagname` (line-scoped)

**Parsing**:
```swift
enum TagType {
    case lineOnly(String)        // #work
    case blockOpen(String)       // #(work
    case blockClose(String)      // #)work
}

// Same validation rules but for block pairs only
// Line-only tags don't need closing
```

**Benefits**:
- ✅ Line-only tags for TODOs, single items (no closing needed)
- ✅ Block tags for multi-line content (explicit clear boundaries)
- ✅ Mix freely: `- [ ] Task #urgent` and `#(project ... #)project`
- ✅ Less verbose than always using block tags
- ✅ Familiar syntax: `#(` looks like "opening", `#)` looks like "closing"

**Edge Cases with Three-Tag System**:
```
#2026-01-07                   Line-only, just marks the date
Work content here

#(meeting
Notes from 10am
Actions: #urgent
More notes
#)meeting

- [ ] #work                   Line-only tag
- [ ] #personal               Line-only tag

#(urgent
CRITICAL FIX NEEDED
#(bug-type
  Database issue
  #)bug-type
#)urgent
```

**Code Complexity**: ~30% more code (additional regex + tag type enum), but much cleaner UX

---

### Option B: Keep Simple - Everywhere Always

If you prefer simplicity:
- Stick with `#tag` and `#/tag` pairing everywhere
- Tag position: anywhere on line (start, middle, end)
- Accept that line-only tagging requires `#tag ... #/tag` on same line

```
- [ ] Task #work #wait-for-feedback #/wait-for-feedback
- [ ] Task #personal
```

**Pros**: Uniform syntax, simpler parser
**Cons**: Verbose for single-line items

---

## Edge Cases & Solutions

### 1. Mismatched Close Tags

**Input**:
```
#work
content
#/project
```

**Behavior**: Parser detects mismatch. Reports error with context and suggestion.

```
ERROR (Line 3): Mismatched close tag
  Expected: #/work (opened at line 1)
  Found: #/project
  Suggestion: Did you mean #/work?
```

### 2. Unopened Close Tags

**Input**:
```
#/work
content
```

**Behavior**: Error reported. No matching open tag found.

```
ERROR (Line 1): Unopened close tag
  #/work
  No opening #work found in scope stack
  Suggestion: Did you forget to open #work?
```

### 3. Unclosed Tags at EOF

**Input**:
```
#work
content
(end of file)
```

**Behavior**: Warning reported. Parser auto-closes with suggestion.

```
WARNING (Line 1): Unclosed tag at end of file
  #work opened but never closed
  Auto-closed. Consider adding #/work before EOF.
```

### 4. Multiple Tags on One Line

**Input**:
```
#2026-01-07 #work #urgent
content here
#/urgent #/work
#/2026-01-07
```

**Behavior**: All processed left-to-right. Stack maintained correctly.

```
Line 1: Opens ["2026-01-07", "work", "urgent"]
Line 2: Content with scope: ["2026-01-07", "work", "urgent"]
Line 3: Close #urgent → ["2026-01-07", "work"]
        Close #work → ["2026-01-07"]
Line 4: Close #2026-01-07 → []
```

### 5. Inline Tags (Mid-Line)

**Input**:
```
Meeting notes #urgent
more content
#/urgent
back to normal
```

**Behavior**: Tag activates immediately, affects rest of line + subsequent lines.

```
Line 1: Opens #urgent at column 14
        Content before tag: "Meeting notes " (scope: [])
        Content after tag: "" (scope: [urgent])
Line 2: Content "more content" (scope: [urgent])
Line 3: Close #urgent
Line 4: Content "back to normal" (scope: [])
```

**Question**: Should inline opens/closes produce separate content blocks, or merge with line?

→ **Decision**: Same-line content kept separate for precision. Split blocks at tag boundaries within line.

### 6. Whitespace and Tag Position

**Input**:
```
  #work
    content
  #/work
```

**Behavior**: Leading/trailing whitespace ignored in line content. Tags tracked by column for error context.

```
Parsed as:
  Line 1: Opens #work (at column 2, stripped)
  Line 2: Content "content" (scope: ["work"])
  Line 3: Closes #work
```

### 7. Empty Scopes

**Input**:
```
#work
#/work
```

**Behavior**: Valid. Creates no content blocks, but scope exists (useful for organizational markers).

```
Result: [] (empty blocks, no errors)
Scope ["work"] exists but has no content.
```

### 8. Nested Same Tag (Error Case)

**Input**:
```
#work
content 1
#work
content 2
#/work
#/work
```

**Behavior**: Detected as duplicate open. Parser warns.

```
WARNING (Line 3): Tag #work opened twice without closing
  Line 1: Previous open of #work
  Line 3: New open of #work
  Suggestion: Did you forget #/work at line 2?
```

---

## Integration Points

### 1. ContextResolver → ScopeResolver Migration

**Current Token Pattern**: `@today`, `@week`, `@last:N`, `@tag:xyz`, `@todos`

**New Pattern**:
```
@scope:work              # Extract all content in any #work scope
@scope:2026-01-07       # Extract all content in #2026-01-07 scope
@scope:2026-01-07/work  # Extract content in #2026-01-07 with #work nested
@scope:/personal        # Extract content tagged #personal
```

**Backward Compat Layer**:
```
@tag:work              # Maps to @scope:work
@today                 # Maps to @scope:2026-01-07 (current date)
@week                  # Maps to union of @scope:YYYY-MM-DD for last 7 days
@last:N                # Maps to last N content blocks
```

### 2. LLM Context Selection

**Before**: Extract by date ranges or tag names independently

**After**: Hierarchical paths enable more precise context

```swift
// Old API
let context = contextResolver.resolve(prompt: prompt, fullText: fullText)

// New API
let parser = ScopeParser()
let result = parser.parse(fullText)

if result.isValid {
    let workContent = parser.extract(scopePath: ["work"], from: result.blocks)
    let todayWorkContent = parser.extract(scopePath: ["2026-01-07", "work"], from: result.blocks)
} else {
    displayValidationErrors(result.errors)
}
```

### 3. Validation UI Integration

**Editor Enhancement**: Show validation status inline

```
#2026-01-07
✓ Opened (matching #/2026-01-07 found)

#work
✓ Opened (matching #/work found)

#/urgent
✗ ERROR: Unopened close tag - no matching #urgent
  Suggestion: Remove this line or add #urgent before it

#/work
✓ Closes matching #work from line 3

#/2026-01-07
✓ Closes matching #2026-01-07 from line 1
```

### 4. Backward Compatibility

**Old format detection**:
```
--- 2026-01-07           (old date header)
#work
#/work
--- 2026-01-08           (old date header)
```

**Auto-migration**:
1. Detect `---` followed by date
2. Convert to `#<date>` at file load
3. Add closing `#/<date>` at next `---` or EOF
4. Offer to save migrated format

Or: Support both formats transparently during parsing

---

## Implementation Phases

### Phase 1: Core Parser (Foundation)
- [ ] Tag regex patterns: `#(\w[\w-]*)`, `#\((\w[\w-]*)`, `#\)(\w[\w-]*)`
- [ ] Tokenizer: classify tags as line-scoped or block-scoped
- [ ] Stack-based validator:
  - Push `#(tag` to BlockStack
  - Match `#)tag` to top of BlockStack
  - Handle line-scoped `#tag` (no stack, current-line only)
- [ ] Error detection for block mismatches, unopened closes
- [ ] ScopeBlock generation (with line-scope vs block-scope awareness)
- [ ] Unit tests (30+ cases: line tags, block tags, mixed, inline, nesting)

### Phase 2: Validation with Scope Limits
- [ ] Implement `ScopeValidator.validateRecent()` - O(k) where k = recent lines
- [ ] Implement `ScopeValidator.validateWindow()` - limit to N days back
- [ ] Add gutter indicator logic (subtle warnings vs strict errors)
- [ ] Implement `ScopeValidator.safeRanges()` - identify validated sections

### Phase 3: Query & Extraction (Utility)
- [ ] Implement `extract(scopePath:)` - respect block vs line scope
- [ ] Implement scope path matching (account for line-scope breadcrumbs)
- [ ] Query parsing: `@scope:tag1/tag2`, `@line-tag:tag`, `@block-tag:tag`
- [ ] Integration tests for line-scoped queries

### Phase 4: ContextResolver Integration (Migration)
- [ ] Map old APIs to new:
  - `@today` → blocks with date tag in last 24h
  - `@week` → blocks with date tags from 7d ago
  - `@tag:xyz` → blocks matching line or block tag xyz
- [ ] Keep backward compatibility layer
- [ ] Update test cases in LogViewModel
- [ ] Add feature flag for gradual rollout

### Phase 5: Error Reporting & UX (Polish)
- [ ] Validation error drawer in editor
- [ ] Auto-fix suggestions displayed in UI
- [ ] Line-scope visual feedback (gutter highlights)
- [ ] Block-scope visual feedback (breadcrumb)
- [ ] Status bar show "✓ Validated" or "⚠ 2 errors"

### Phase 6: Migration Tools (Flexibility)
- [ ] Detect old `--- YYYY-MM-DD` format
- [ ] Auto-convert to `#YYYY-MM-DD` / `#)YYYY-MM-DD`
- [ ] Offer "Validate & Migrate" action
- [ ] Generate migration report
- [ ] Provide undo option

---

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| **Parse** | O(n) | Single linear pass, regex matching each line |
| **Validate** | O(n) | Stack operations are O(1) per tag |
| **Query** | O(m) | Filter m blocks for scope match |
| **Extract** | O(m log m) | Extract + sort by line number |
| **Memory** | O(n) | Store blocks, error info |

**Assumptions**:
- n = number of lines in log
- m = number of blocks (≤ n, typically m << n)
- Recompute on each edit (cache between edits)
- Logs up to 100k+ lines handle fine

---

## Three-Tag Parser Implementation Notes

### Regex Patterns

```swift
// Line-scoped tag: #work, #2026-01-07, #project-x
let lineTagPattern = #"#([a-zA-Z][a-zA-Z0-9_-]*)"#

// Block-open tag: #(work, #(2026-01-07
let blockOpenPattern = #"#\(([a-zA-Z][a-zA-Z0-9_-]*)"#

// Block-close tag: #)work, #)2026-01-07
let blockClosePattern = #"#\)([a-zA-Z][a-zA-Z0-9_-]*)"#

// Position in line: column number for error reporting
// Inline: mid-line vs line-start (affects scope application)
```

### Parsing Algorithm (Three-Tag Version)

```
STATE:
  blockStack: Stack<String>          // Tracks open #(tag
  lineScopes: [String]               // #tag tags for current line
  currentScopePath: [String]         // All active scopes: line + block
  
FOR EACH line:
  lineScopes = []
  
  // Extract all tags from line (in order, left-to-right)
  FOR EACH token in line:
    IF token matches #(tagname:
      blockStack.push(tagname)
      currentScopePath.append(tagname)
    ELSE IF token matches #)tagname:
      IF blockStack.top == tagname:
        blockStack.pop()
        currentScopePath = currentScopePath.dropLast()
      ELSE:
        ERROR: mismatchedClose
    ELSE IF token matches #tagname:
      lineScopes.append(tagname)
  
  // Content on this line has scope = blockStack + lineScopes
  scopeAtLine = blockStack + lineScopes
  
  IF line has content (not just tags):
    create ScopeBlock(content, scopePath: scopeAtLine, lineScopes: lineScopes)
```

### Key Differences from Simple `#tag`/`#/tag`

| Aspect | Simple | Three-Tag |
|--------|--------|-----------|
| **Parse tree** | Single stack (blocks only) | Two stacks (blocks + line tags) |
| **Scope path** | `[tag1, tag2, tag3]` | `[block1, block2] + [lineTag1]` |
| **Validation** | Validate all pairs | Validate only block pairs |
| **Query matching** | Check if tag in path | Check block path + line tags |
| **Error types** | 6 types | 7 types (add: invalid line tag syntax) |
| **Regex count** | 2 patterns | 3 patterns |
| **Lines of code** | ~200 | ~250 (+25% overhead) |

### Inline Tag Handling

**Challenge**: What if user writes `Text #(work more text #)work on same line`?

**Solution**:
- Split line into segments at tag boundaries
- Each segment gets its active scopes
- Produces multiple ScopeBlocks per line

```
Input:  "Before #(proj middle #)proj after"
Parse:
  Segment 1: "Before " → scope: []
  Segment 2: "middle " → scope: ["proj"]
  Segment 3: "after" → scope: []
Blocks: 3 entries for 1 line (rare case)
```

---

## Design Decisions

### Why Three-Tag System?

| Syntax | Use Case | Complexity |
|--------|----------|-----------|
| `#tag` only | Line tags always | Simplest, but verbose |
| `#tag` / `#/tag` | Explicit pairing | Medium, familiar to XML/HTML devs |
| `#tag` / `#(tag` / `#)tag` | **Line + block** | Medium+, but cleaner UX |

**Decision**: Three-tag system. The 50 LOC overhead is worth the UX improvement for very common case (line-only tags on TODOs).

### Why Explicit `#tag` vs `#)tag`?

| Approach | Pros | Cons |
|----------|------|------|
| **Explicit pairs** `#tag`/`#/tag` | Impossible to miss boundaries; easy validation; like HTML | Slightly more typing (one `/` per close) |
| **Implicit (nesting)** | Fewer characters | Ambiguous on manual input; hard to validate |
| **Extra symbols** `(())`, `[[]]` | Visually distinct | Harder to type on iPhone; more complex parsing |

**Decision**: Explicit pairs. Manual input is error-prone; clear delimiters prevent scope confusion.

### Why No Indentation for Hierarchy?

- iPhone keyboard constraint (no tabs/spaces easily typo'd)
- Avoid accidental space misalignment
- Hierarchy determined by tag order, not whitespace
- Cleaner for plain-text editing

### Why Stack-Based Validation?

- Exact scope matching is necessary
- Wrong nesting catches errors immediately
- Mirrors familiar XML/HTML parsing
- Standard compiler technique

---

## Final Design Decision: Three-Tag Syntax (Recommended)

Combine all approaches into **one clean system**:

| Syntax | Scope | Example | Use Case |
|--------|-------|---------|----------|
| `#tag` | Current line only | `- [ ] Buy milk #errand` | Single-line items, inline labels |
| `#(tag` | Multi-line block | `#(project\n...\n#)project` | Sections, meetings, projects |
| `#)tag` | Closes block | End marker | Pair with `#(tag` |

**Grammar**:
```
LineScope = Line with zero or more #tagname
BlockStart = #(tagname anywhere on line
BlockEnd = #)tagname must match most recent unclosed #(tagname
```

**Validation**:
- `#tag` needs **no** closing (line-scoped)
- `#(tag` **must** have `#)tag` somewhere later (block-scoped)
- Block pairs must match (nesting, no crossing)
- Line tags can coexist with block tags

**Example Usage**:

```
#2026-01-07
Morning standup notes

#(meeting
Attendees: Alice, Bob
- [ ] Review docs #urgent
- [ ] Deploy #(hotfix
      database fix
      tested locally
      #)hotfix
- [ ] Followup #personal
#)meeting

#(project-x #urgent
Major refactor in progress.
Status: 60% complete.
#)project-x #/urgent

Evening: More notes #personal
```

---

## Syntax Comparison Table

| Aspect | `#tag/#/tag` (Simple) | `#tag`/`#(tag`/`#)tag` (Three-Tag) | `#tag`/`#/tag` everywhere (Current) |
|--------|--------|--------|--------|
| **Line-only items** | `#item #/item` on same line | `#item` (clean) | `#item #/item` on same line |
| **Multiline blocks** | `#block ... #/block` | `#(block ... #)block` (clear) | `#block ... #/block` (works) |
| **Typing effort** | High (close needed everywhere) | Medium (use `#` for lines) | High |
| **Visual clarity** | Good (uniform) | Excellent (`()` is obvious) | Good |
| **Parser complexity** | ~200 lines | ~250 lines | ~200 lines |
| **Mobile-friendly** | Medium | High (less closing) | Medium |
| **User mental model** | Always pair | "If multi-line, use parens" | Always pair |

**Recommendation**: **Three-Tag System**. The slight parser overhead (50 LOC) pays for itself in UX.

---

## Validation Integration Architecture

```
┌─ Editor (TextKit2View)
│  └─ InputDelegate.textDidChange()
│     ├─ No validation (don't distract)
│     └─ Schedule validator.validateRecent() in 2s
│
├─ ScopeValidator (background)
│  ├─ validateRecent() - quick check, recent lines
│  │  └─ GUI: subtle gutter indicator
│  ├─ validateWindow() - 3 days back
│  │  └─ GUI: warning count in status bar
│  └─ validateFull() - before critical ops
│     └─ GUI: error drawer with fixes
│
└─ Before LLM Query
   ├─ Call validateFull()
   ├─ Show error report if issues
   ├─ User chooses: Proceed / Auto-fix / Cancel
   └─ Send context with validated scopes
```

---

## Benefits of Final Design

✅ **Three-in-one**: Line tags, block tags, inline tags in one system
✅ **Optimized typing**: Single `#tag` for 80% of cases (lines)
✅ **Clear delimiters**: `#(` vs `#)` visually distinct
✅ **iPhone-friendly**: Fewer parentheses needed
✅ **Unobtrusive validation**: Only checks when needed
✅ **Smart scoping**: Recent edits + 3-day window for background checks
✅ **Deterministic**: Stack-based parsing, no ambiguity
✅ **Helpful errors**: Suggestions & auto-fixes before LLM queries
✅ **Familiar**: HTML-like semantics with line-scoping bonus

