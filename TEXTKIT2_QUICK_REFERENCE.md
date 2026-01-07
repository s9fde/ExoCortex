# TextKit 2 Integration Quick Reference

## Using TextKit2Editor

### Basic Usage
```swift
import SwiftUI

struct MyEditorView: View {
    @State private var text = ""
    
    var body: some View {
        TextKit2Editor(
            text: $text,
            onFocusLost: {
                print("User finished editing")
                // Save to disk, sync, etc.
            }
        )
    }
}
```

### With ViewModel
```swift
struct LogEditorView: View {
    @Bindable var viewModel: LogViewModel
    
    var body: some View {
        TextKit2Editor(
            text: $viewModel.fullText,
            onFocusLost: {
                Task { await viewModel.forceSave() }
            }
        )
    }
}
```

## Architecture Overview

### Component Stack
```
TextKit2Editor (SwiftUI wrapper)
    ↓
TextKit2View (NSViewRepresentable / UIViewRepresentable)
    ↓
NSTextView or UITextView (native text engine)
    ↓
TextKit 2 Rendering Engine
```

### Files

| File | Purpose |
|------|---------|
| [`TextKit2Editor.swift`](ExoCortex/TextKit2Editor.swift) | Public SwiftUI component (use this) |
| [`TextKit2View.swift`](ExoCortex/TextKit2View.swift) | Platform adapter (internal implementation) |

## Customization

### Change Font Size
Edit [`TextKit2View.swift`](ExoCortex/TextKit2View.swift:1):

**macOS**:
```swift
textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
```

**iOS**:
```swift
textView.font = UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
```

### Change Font Family
```swift
// macOS
textView.font = NSFont(name: "Menlo", size: 13)

// iOS
textView.font = UIFont(name: "Menlo", size: 16)
```

### Change Text Color
```swift
// macOS
textView.textColor = NSColor.label

// iOS
textView.textColor = UIColor.label
```

### Change Background Color
```swift
// macOS
textView.backgroundColor = NSColor.textBackgroundColor

// iOS
textView.backgroundColor = UIColor.systemBackground
```

## Advanced: Adding Syntax Highlighting

To add syntax highlighting to TextKit 2:

```swift
// In TextKit2View, after creating NSTextView:
let contentManager = NSTextContentManager()
let textLayoutManager = NSTextLayoutManager()
textLayoutManager.addObserver(SyntaxHighlighter())
contentManager.addTextLayoutManager(textLayoutManager)
```

See Apple's [TextKit 2 tutorial](https://developer.apple.com/documentation/textkit) for full implementation.

## Debugging

### Enable Logging
Add to `TextKit2View.swift` coordinator:

```swift
func textViewDidChange(_ notification: Notification) {
    print("Text changed, length: \(text.count)")
    text = textView.string
}
```

### Check Text Binding
```swift
struct DebugView: View {
    @State private var text = ""
    
    var body: some View {
        VStack {
            TextKit2Editor(text: $text)
            Text("Length: \(text.count)")
            Text(text)
        }
    }
}
```

### View Hierarchy
Use Xcode's View Debugger (Debug → View Hierarchy) to inspect NSTextView rendering.

## Performance Tips

1. **Large Files (10MB+)**: TextKit 2 handles natively—no special optimizations needed
2. **Scrolling**: Native scroll handling is automatically efficient
3. **Text Updates**: Avoid binding to every keystroke; let platform handle batching
4. **Memory**: NSTextView uses copy-on-write for text storage

## Known Limitations

1. **visionOS**: Not yet supported (would require `RealityKit` integration)
2. **Syntax Highlighting**: Requires custom TextKit 2 layout manager
3. **RTL Languages**: Full RTL support via TextKit 2 (default)

## API Changes from Old Implementation

### Old (SwiftUI TextEditor)
```swift
SimpleTextEditor(text: $text, onFocusLost: callback)
```

### New (TextKit 2)
```swift
TextKit2Editor(text: $text, onFocusLost: callback)
```

**✅ API is identical—drop-in replacement**

## Testing on Both Platforms

### macOS
```bash
xcodebuild build -scheme ExoCortex -destination 'platform=macOS'
```

### iOS Simulator
```bash
xcodebuild build -scheme ExoCortex -destination 'platform=iOS Simulator,name=iPhone 16'
```

### iOS Device
```bash
xcodebuild build -scheme ExoCortex -destination 'platform=iOS,name=My iPhone'
```

## Resources

- [TextKit 2 Documentation](https://developer.apple.com/documentation/textkit)
- [NSTextView Reference](https://developer.apple.com/documentation/appkit/nstextview)
- [UITextView Reference](https://developer.apple.com/documentation/uikit/uitextview)
- [NSViewRepresentable Guide](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- [Mastering TextKit 2 (WWDC 2022)](https://developer.apple.com/videos/play/wwdc2022/10091/)

## Support

For issues or questions about TextKit 2 integration:
1. Check the architecture diagram in [`TEXTKIT2_MIGRATION.md`](TEXTKIT2_MIGRATION.md)
2. Review the coordinator pattern in [`TextKit2View.swift`](ExoCortex/TextKit2View.swift)
3. Test in View Debugger to verify text binding
4. Profile with Instruments to identify performance bottlenecks
