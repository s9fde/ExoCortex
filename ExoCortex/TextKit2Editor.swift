//
//  TextKit2Editor.swift
//  ExoCortex
//
//  High-performance text editor using TextKit 2.
//  Drop-in replacement for SimpleTextEditor with native rendering.
//

import SwiftUI

/// A high-performance text editor using native TextKit 2 (NSTextView on macOS, UITextView on iOS).
/// Renders large text buffers efficiently with automatic monospaced font styling.
struct TextKit2Editor: View {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    
    var body: some View {
        TextKit2View(text: $text, onFocusLost: onFocusLost)
            #if os(macOS)
            .scrollContentBackground(.visible)
            #endif
    }
}

// MARK: - Preview

#Preview {
    TextKit2Editor(text: .constant("""
# 260101 Daily Log

#p What should I focus on today?
#opus45 Here are my suggestions:
- Focus on the most important task
- Check your config.json file
---

## Tasks
- [ ] Buy groceries #personal
- [x] Review code #work
- [ ] Call mom #personal

Visit https://apple.com for more info.

#error Something went wrong here
"""))
}
