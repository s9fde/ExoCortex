//
//  TextKit2View.swift
//  ExoCortex
//
//  High-performance text editor using NSTextView + TextKit 2
//  Provides native text rendering for iOS 16+ and macOS 13+
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit

// MARK: - macOS TextKit 2 Implementation

struct TextKit2View: NSViewRepresentable {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure text view
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        
        // Add internal text container insets for spacing
        textView.textContainerInset = NSSize(width: 16, height: 8)
        
        // Dark mode support
        if #available(macOS 10.14, *) {
            textView.appearance = NSAppearance(named: .darkAqua)
        }
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        // Set initial text
        textView.string = text
        
        // Store reference in coordinator for later access
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Update text only if it changed externally
        if textView.string != text {
            let selectedRange = textView.selectedRange
            textView.string = text
            // Restore selection if possible
            if selectedRange.location <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
        }
    }
    
    func makeCoordinator() -> TextKit2Coordinator {
        TextKit2Coordinator(text: $text, onFocusLost: onFocusLost)
    }
}

// MARK: - macOS Coordinator

class TextKit2Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    var textView: NSTextView?
    
    init(text: Binding<String>, onFocusLost: (() -> Void)?) {
        self._text = text
        self.onFocusLost = onFocusLost
    }
    
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        text = textView.string
    }
    
    func textDidEndEditing(_ notification: Notification) {
        onFocusLost?()
    }
    
    /// Scroll to bottom of text and position cursor at end
    @MainActor
    func scrollToBottomAndFocus() {
        guard let textView = textView else { return }
        
        // Position cursor at end of text
        let endPosition = textView.string.count
        textView.setSelectedRange(NSRange(location: endPosition, length: 0))
        
        // Scroll to bottom (using delegate parameter is nil since we're calling directly)
        textView.scrollToEndOfDocument(nil)
        
        // Focus the text view for immediate typing
        textView.window?.makeFirstResponder(textView)
    }
}

#elseif os(iOS)
import UIKit

// MARK: - iOS TextKit 2 Implementation

struct TextKit2View: UIViewRepresentable {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        
        // Configure text view
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = UIColor.label
        
        // Dark mode support
        if #available(iOS 13, *) {
            textView.overrideUserInterfaceStyle = .dark
        }
        
        // Set initial text
        textView.text = text
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Update text only if it changed externally
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            // Restore selection if possible
            if selectedRange.location <= uiView.text.count {
                uiView.selectedRange = selectedRange
            }
        }
    }
    
    func makeCoordinator() -> TextKit2Coordinator {
        TextKit2Coordinator(text: $text, onFocusLost: onFocusLost)
    }
}

// MARK: - iOS Coordinator

class TextKit2Coordinator: NSObject, UITextViewDelegate {
    @Binding var text: String
    var onFocusLost: (() -> Void)?
    
    init(text: Binding<String>, onFocusLost: (() -> Void)?) {
        self._text = text
        self.onFocusLost = onFocusLost
    }
    
    func textViewDidChange(_ textView: UITextView) {
        text = textView.text
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        onFocusLost?()
    }
}

#endif

// MARK: - Preview

#Preview {
    TextKit2View(text: .constant("""
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
