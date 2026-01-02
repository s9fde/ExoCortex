//
//  StyledTextEditor.swift
//  ExoCortex
//
//  A simple text editor wrapper for SwiftUI.
//  Plain text only - no syntax highlighting or complex formatting.
//

import SwiftUI

// MARK: - Simple Text Editor

/// A simple text editor using native SwiftUI TextEditor.
/// Triggers save callback on focus lost.
struct SimpleTextEditor: View {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                if !newValue {
                    // Focus lost - trigger save
                    onFocusLost?()
                }
            }
            #if os(macOS)
            .scrollContentBackground(.visible)
            #endif
    }
}

// MARK: - Preview

#Preview {
    SimpleTextEditor(text: .constant("""
# 2026-01-01 Daily Log

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
