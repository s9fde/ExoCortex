//
//  StyledTextEditor.swift
//  ExoCortex
//
//  A rich text editor with markdown-style syntax highlighting,
//  clickable URLs, and interactive todo checkboxes.
//

import SwiftUI

#if os(macOS)
import AppKit

// MARK: - macOS Styled Text Editor

/// A styled text editor using NSTextView for macOS with syntax highlighting
struct StyledTextEditor: NSViewRepresentable {
    @Binding var text: String
    var searchTerm: String = ""
    var currentMatchIndex: Int = 0
    /// Generation counter - when this increments, scroll to bottom and focus the editor
    var scrollToBottomGeneration: Int = 0
    var onTodoToggle: ((Int) -> Void)?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // Configure text view
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        
        // Enable link clicking
        textView.isAutomaticLinkDetectionEnabled = true
        
        // Store reference for updates
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Update search state in coordinator
        let searchChanged = context.coordinator.searchTerm != searchTerm ||
                           context.coordinator.currentMatchIndex != currentMatchIndex
        context.coordinator.searchTerm = searchTerm
        context.coordinator.currentMatchIndex = currentMatchIndex
        
        // Check if generation incremented (means we should scroll to bottom & focus)
        let shouldScrollToBottom = scrollToBottomGeneration > context.coordinator.lastScrollGeneration
        
        // Only update text if it changed externally (not from user typing)
        if textView.string != text && !context.coordinator.isUserEditing {
            // Store cursor position relative to content
            let cursorLocation = textView.selectedRange().location
            
            textView.string = text
            
            // Restore cursor, clamped to valid range
            let maxLocation = textView.string.utf16.count
            let newLocation = min(cursorLocation, maxLocation)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
            
            // Apply highlighting after external text change
            context.coordinator.applySyntaxHighlighting()
        } else if searchChanged {
            // Only re-highlight if search changed (not on every update)
            context.coordinator.applySyntaxHighlighting()
        }
        
        // Handle scroll to bottom and focus - must happen AFTER text is set
        // This runs when generation increments (e.g., on unlock)
        if shouldScrollToBottom {
            // Delay slightly to ensure view is fully ready
            DispatchQueue.main.async {
                let endPosition = self.text.utf16.count
                textView.setSelectedRange(NSRange(location: endPosition, length: 0))
                textView.scrollToEndOfDocument(nil)
                // Make the text view first responder so user can type immediately
                textView.window?.makeFirstResponder(textView)
            }
            context.coordinator.lastScrollGeneration = scrollToBottomGeneration
        }
        
        // Scroll to current match if searching
        if !searchTerm.isEmpty && searchChanged {
            context.coordinator.scrollToCurrentMatch()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, searchTerm: searchTerm, currentMatchIndex: currentMatchIndex, onTodoToggle: onTodoToggle)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var searchTerm: String
        var currentMatchIndex: Int
        var onTodoToggle: ((Int) -> Void)?
        weak var textView: NSTextView?
        var isUserEditing = false
        /// Tracks which generation we last scrolled for
        var lastScrollGeneration: Int = 0
        private var searchMatches: [NSRange] = []
        private var highlightWorkItem: DispatchWorkItem?
        
        init(text: Binding<String>, searchTerm: String, currentMatchIndex: Int, onTodoToggle: ((Int) -> Void)?) {
            self.text = text
            self.searchTerm = searchTerm
            self.currentMatchIndex = currentMatchIndex
            self.onTodoToggle = onTodoToggle
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Mark as user editing to prevent updateNSView from overwriting
            isUserEditing = true
            text.wrappedValue = textView.string
            
            // Debounce syntax highlighting to avoid flickering during rapid typing
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.applySyntaxHighlighting()
                    self?.isUserEditing = false
                }
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
        
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Handle todo:// links for checkbox toggling
            if let urlString = link as? String, urlString.hasPrefix("todo://") {
                if let lineNumber = Int(urlString.replacingOccurrences(of: "todo://", with: "")) {
                    onTodoToggle?(lineNumber)
                    return true
                }
            }
            
            // Handle regular URLs
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let urlString = link as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                return true
            }
            
            return false
        }
        
        @MainActor func applySyntaxHighlighting() {
            guard let textView = textView else { return }
            guard let textStorage = textView.textStorage else { return }
            
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let text = textStorage.string
            
            // Preserve selection
            let selectedRanges = textView.selectedRanges
            
            // Begin editing
            textStorage.beginEditing()
            
            // Reset to default style
            let defaultFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            textStorage.setAttributes([
                .font: defaultFont,
                .foregroundColor: NSColor.textColor,
                .backgroundColor: NSColor.clear
            ], range: fullRange)
            
            // Apply syntax highlighting line by line
            let lines = text.components(separatedBy: "\n")
            var currentIndex = 0
            
            for (lineNumber, line) in lines.enumerated() {
                let lineRange = NSRange(location: currentIndex, length: line.utf16.count)
                applyLineStyles(line: line, lineNumber: lineNumber, range: lineRange, textStorage: textStorage)
                currentIndex += line.utf16.count + 1 // +1 for newline
            }
            
            // Apply search highlighting on top of syntax highlighting
            applySearchHighlighting(text: text, textStorage: textStorage)
            
            textStorage.endEditing()
            
            // Restore selection
            textView.selectedRanges = selectedRanges
        }
        
        /// Apply yellow background to search matches, with strong yellow for current match (marker-style)
        private func applySearchHighlighting(text: String, textStorage: NSTextStorage) {
            searchMatches = []
            
            guard !searchTerm.isEmpty else { return }
            
            // Find all matches
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: searchTerm, options: .caseInsensitive, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                searchMatches.append(nsRange)
                searchRange = range.upperBound..<text.endIndex
            }
            
            // Highlight all matches with yellow background (marker-style)
            for (index, match) in searchMatches.enumerated() {
                let backgroundColor: NSColor
                if index == currentMatchIndex {
                    // Current match - strong yellow like a highlighter marker
                    backgroundColor = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.0, alpha: 0.85)
                } else {
                    // Other matches - subtle yellow background
                    backgroundColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.6, alpha: 0.5)
                }
                textStorage.addAttribute(.backgroundColor, value: backgroundColor, range: match)
            }
        }
        
        /// Scroll the text view to show the current search match
        @MainActor func scrollToCurrentMatch() {
            guard let textView = textView else { return }
            guard !searchMatches.isEmpty else { return }
            guard currentMatchIndex >= 0 && currentMatchIndex < searchMatches.count else { return }
            
            let matchRange = searchMatches[currentMatchIndex]
            
            // Scroll to make the match visible
            textView.scrollRangeToVisible(matchRange)
            
            // Optionally also select the match
            textView.setSelectedRange(matchRange)
        }
        
        private func applyLineStyles(line: String, lineNumber: Int, range: NSRange, textStorage: NSTextStorage) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // AI response tag - purple
            if lower.hasPrefix(LLMConfig.responseTag.lowercased()) {
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
                deemphasizePrefix(LLMConfig.responseTag, in: line, range: range, textStorage: textStorage)
                return
            }
            
            // Error tag - red
            if lower.hasPrefix(LLMConfig.errorTag.lowercased()) {
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                deemphasizePrefix(LLMConfig.errorTag, in: line, range: range, textStorage: textStorage)
                return
            }
            
            // Prompt tag - blue
            if lower.hasPrefix(LLMConfig.promptTag.lowercased()) {
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
                deemphasizePrefix(LLMConfig.promptTag, in: line, range: range, textStorage: textStorage)
                return
            }
            
            // Headers (# at start of line)
            if trimmed.hasPrefix("#") && !trimmed.hasPrefix("#p") && !trimmed.hasPrefix("#opus") && !trimmed.hasPrefix("#error") {
                let headerFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .bold)
                textStorage.addAttribute(.font, value: headerFont, range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
                // De-emphasize the # symbols
                if let hashRange = findPrefixRange(matching: "^#+\\s*", in: line, offset: range.location) {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: hashRange)
                }
                return
            }
            
            // Date separator lines (--- YYYY-MM-DD ---)
            let dateSeparatorPattern = "^---\\s*\\d{4}-\\d{2}-\\d{2}\\s*---$"
            if let regex = try? NSRegularExpression(pattern: dateSeparatorPattern),
               regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
                return
            }
            
            // Separator lines
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
                return
            }
            
            // Apply inline styles
            applyInlineStyles(line: line, lineNumber: lineNumber, range: range, textStorage: textStorage)
        }
        
        private func applyInlineStyles(line: String, lineNumber: Int, range: NSRange, textStorage: NSTextStorage) {
            // Todo checkboxes - make clickable
            applyTodoStyle(line: line, lineNumber: lineNumber, range: range, textStorage: textStorage)
            
            // Inline tags (#tag) - gray
            applyTagStyle(line: line, range: range, textStorage: textStorage)
            
            // URLs - blue, underlined, clickable
            applyURLStyle(line: line, range: range, textStorage: textStorage)
            
            // Bold text (**text**)
            applyBoldStyle(line: line, range: range, textStorage: textStorage)
            
            // Inline code (`code`)
            applyInlineCodeStyle(line: line, range: range, textStorage: textStorage)
        }
        
        private func applyTodoStyle(line: String, lineNumber: Int, range: NSRange, textStorage: NSTextStorage) {
            // Open todo [ ]
            if let todoRange = line.range(of: "[ ]") {
                let nsRange = NSRange(todoRange, in: line)
                let absoluteRange = NSRange(location: range.location + nsRange.location, length: nsRange.length)
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemOrange,
                    .link: "todo://\(lineNumber)",
                    .cursor: NSCursor.pointingHand
                ], range: absoluteRange)
            }
            
            // Completed todo [x] or [X]
            if let doneRange = line.range(of: "[x]", options: .caseInsensitive) {
                let nsRange = NSRange(doneRange, in: line)
                let absoluteRange = NSRange(location: range.location + nsRange.location, length: nsRange.length)
                textStorage.addAttributes([
                    .foregroundColor: NSColor.systemGreen,
                    .link: "todo://\(lineNumber)",
                    .cursor: NSCursor.pointingHand
                ], range: absoluteRange)
            }
        }
        
        private func applyTagStyle(line: String, range: NSRange, textStorage: NSTextStorage) {
            // Match #tag (not at line start, or inline)
            let pattern = "(?<=\\s|^)#[a-zA-Z][a-zA-Z0-9_]*"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                let absoluteRange = NSRange(location: range.location + match.range.location, length: match.range.length)
                // Skip if this is a header line
                let matchText = (line as NSString).substring(with: match.range).lowercased()
                if matchText == LLMConfig.promptTag.lowercased() ||
                   matchText == LLMConfig.responseTag.lowercased() ||
                   matchText == LLMConfig.errorTag.lowercased() {
                    continue
                }
                textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: absoluteRange)
            }
        }
        
        private func applyURLStyle(line: String, range: NSRange, textStorage: NSTextStorage) {
            let pattern = "https?://[^\\s]+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                let absoluteRange = NSRange(location: range.location + match.range.location, length: match.range.length)
                let urlString = (line as NSString).substring(with: match.range)
                if let url = URL(string: urlString) {
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .link: url
                    ], range: absoluteRange)
                }
            }
        }
        
        private func applyBoldStyle(line: String, range: NSRange, textStorage: NSTextStorage) {
            let pattern = "\\*\\*([^*]+)\\*\\*"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                // Style the content
                if match.numberOfRanges > 1 {
                    let contentRange = match.range(at: 1)
                    let absoluteRange = NSRange(location: range.location + contentRange.location, length: contentRange.length)
                    let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
                    textStorage.addAttribute(.font, value: boldFont, range: absoluteRange)
                }
                // De-emphasize the asterisks
                let fullRange = match.range
                // Leading **
                let leadingRange = NSRange(location: range.location + fullRange.location, length: 2)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: leadingRange)
                // Trailing **
                let trailingRange = NSRange(location: range.location + fullRange.location + fullRange.length - 2, length: 2)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: trailingRange)
            }
        }
        
        private func applyInlineCodeStyle(line: String, range: NSRange, textStorage: NSTextStorage) {
            let pattern = "`([^`]+)`"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                let absoluteRange = NSRange(location: range.location + match.range.location, length: match.range.length)
                textStorage.addAttributes([
                    .backgroundColor: NSColor.quaternaryLabelColor,
                    .foregroundColor: NSColor.systemOrange
                ], range: absoluteRange)
                // De-emphasize backticks
                let leadingRange = NSRange(location: absoluteRange.location, length: 1)
                let trailingRange = NSRange(location: absoluteRange.location + absoluteRange.length - 1, length: 1)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: leadingRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: trailingRange)
            }
        }
        
        private func deemphasizePrefix(_ prefix: String, in line: String, range: NSRange, textStorage: NSTextStorage) {
            if let prefixRange = line.range(of: prefix, options: .caseInsensitive) {
                let nsRange = NSRange(prefixRange, in: line)
                let absoluteRange = NSRange(location: range.location + nsRange.location, length: nsRange.length)
                // Make prefix slightly faded
                let currentColor = textStorage.attribute(.foregroundColor, at: absoluteRange.location, effectiveRange: nil) as? NSColor ?? .textColor
                textStorage.addAttribute(.foregroundColor, value: currentColor.withAlphaComponent(0.6), range: absoluteRange)
            }
        }
        
        private func findPrefixRange(matching pattern: String, in line: String, offset: Int) -> NSRange? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(location: 0, length: line.utf16.count)
            if let match = regex.firstMatch(in: line, range: range) {
                return NSRange(location: offset + match.range.location, length: match.range.length)
            }
            return nil
        }
    }
}

#else
import UIKit

// MARK: - iOS Styled Text Editor

/// A styled text editor using UITextView for iOS with syntax highlighting and search support
struct StyledTextEditor: UIViewRepresentable {
    @Binding var text: String
    var searchTerm: String = ""
    var currentMatchIndex: Int = 0
    /// Generation counter - when this increments, scroll to bottom and focus the editor
    var scrollToBottomGeneration: Int = 0
    var onTodoToggle: ((Int) -> Void)?
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.isEditable = true
        textView.isSelectable = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.dataDetectorTypes = .link
        
        context.coordinator.textView = textView
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        // Update search state in coordinator
        let searchChanged = context.coordinator.searchTerm != searchTerm ||
                           context.coordinator.currentMatchIndex != currentMatchIndex
        context.coordinator.searchTerm = searchTerm
        context.coordinator.currentMatchIndex = currentMatchIndex
        
        // Check if generation incremented (means we should scroll to bottom & focus)
        let shouldScrollToBottom = scrollToBottomGeneration > context.coordinator.lastScrollGeneration
        
        // Only update text if it changed externally (not from user typing)
        if textView.text != text && !context.coordinator.isUserEditing {
            // Store cursor position
            let cursorLocation = textView.selectedRange.location
            
            textView.text = text
            
            // Restore cursor, clamped to valid range
            let maxLocation = (textView.text ?? "").utf16.count
            let newLocation = min(cursorLocation, maxLocation)
            textView.selectedRange = NSRange(location: newLocation, length: 0)
            
            // Apply highlighting after external text change
            context.coordinator.applySyntaxHighlighting()
        } else if searchChanged {
            // Only re-highlight if search changed (not on every update)
            context.coordinator.applySyntaxHighlighting()
        }
        
        // Handle scroll to bottom and focus - must happen AFTER text is set
        // This runs when generation increments (e.g., on unlock)
        if shouldScrollToBottom {
            let endPosition = text.utf16.count
            textView.selectedRange = NSRange(location: endPosition, length: 0)
            // Scroll to bottom after layout and make first responder
            DispatchQueue.main.async {
                let bottom = CGPoint(x: 0, y: max(0, textView.contentSize.height - textView.bounds.height))
                textView.setContentOffset(bottom, animated: false)
                textView.becomeFirstResponder()
            }
            context.coordinator.lastScrollGeneration = scrollToBottomGeneration
        }
        
        // Scroll to current match if searching
        if !searchTerm.isEmpty && searchChanged {
            context.coordinator.scrollToCurrentMatch()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, searchTerm: searchTerm, currentMatchIndex: currentMatchIndex, onTodoToggle: onTodoToggle)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var searchTerm: String
        var currentMatchIndex: Int
        var onTodoToggle: ((Int) -> Void)?
        weak var textView: UITextView?
        var isUserEditing = false
        /// Tracks which generation we last scrolled for
        var lastScrollGeneration: Int = 0
        private var searchMatches: [NSRange] = []
        private var highlightWorkItem: DispatchWorkItem?
        
        init(text: Binding<String>, searchTerm: String, currentMatchIndex: Int, onTodoToggle: ((Int) -> Void)?) {
            self.text = text
            self.searchTerm = searchTerm
            self.currentMatchIndex = currentMatchIndex
            self.onTodoToggle = onTodoToggle
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // Mark as user editing to prevent updateUIView from overwriting
            isUserEditing = true
            text.wrappedValue = textView.text
            
            // Debounce syntax highlighting to avoid flickering during rapid typing
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting()
                self?.isUserEditing = false
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
            // Handle todo:// scheme
            if URL.scheme == "todo" {
                if let lineNumber = Int(URL.host ?? "") {
                    onTodoToggle?(lineNumber)
                    return false
                }
            }
            // Allow default handling for http/https
            return true
        }
        
        func applySyntaxHighlighting() {
            guard let textView = textView else { return }
            let text = textView.text ?? ""
            let selectedRange = textView.selectedRange
            
            let attributedString = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: attributedString.length)
            
            // Default attributes
            attributedString.addAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.label
            ], range: fullRange)
            
            // Apply line-by-line styling
            let lines = text.components(separatedBy: "\n")
            var currentIndex = 0
            
            for (lineNumber, line) in lines.enumerated() {
                let lineRange = NSRange(location: currentIndex, length: line.utf16.count)
                applyLineStyles(line: line, lineNumber: lineNumber, range: lineRange, attributedString: attributedString)
                currentIndex += line.utf16.count + 1
            }
            
            // Apply search highlighting on top of syntax highlighting
            applySearchHighlighting(text: text, attributedString: attributedString)
            
            textView.attributedText = attributedString
            textView.selectedRange = selectedRange
        }
        
        /// Apply yellow background to search matches, with strong yellow for current match
        private func applySearchHighlighting(text: String, attributedString: NSMutableAttributedString) {
            searchMatches = []
            
            guard !searchTerm.isEmpty else { return }
            
            // Find all matches
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: searchTerm, options: .caseInsensitive, range: searchRange) {
                let nsRange = NSRange(range, in: text)
                searchMatches.append(nsRange)
                searchRange = range.upperBound..<text.endIndex
            }
            
            // Highlight all matches with yellow background
            for (index, match) in searchMatches.enumerated() {
                let backgroundColor: UIColor
                if index == currentMatchIndex {
                    // Current match - strong yellow like a highlighter marker
                    backgroundColor = UIColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 0.85)
                } else {
                    // Other matches - subtle yellow background
                    backgroundColor = UIColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 0.5)
                }
                attributedString.addAttribute(.backgroundColor, value: backgroundColor, range: match)
            }
        }
        
        /// Scroll the text view to show the current search match
        func scrollToCurrentMatch() {
            guard let textView = textView else { return }
            guard !searchMatches.isEmpty else { return }
            guard currentMatchIndex >= 0 && currentMatchIndex < searchMatches.count else { return }
            
            let matchRange = searchMatches[currentMatchIndex]
            textView.scrollRangeToVisible(matchRange)
            textView.selectedRange = matchRange
        }
        
        private func applyLineStyles(line: String, lineNumber: Int, range: NSRange, attributedString: NSMutableAttributedString) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // AI response - purple
            if lower.hasPrefix(LLMConfig.responseTag.lowercased()) {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: range)
                return
            }
            
            // Error - red
            if lower.hasPrefix(LLMConfig.errorTag.lowercased()) {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemRed, range: range)
                return
            }
            
            // Prompt - blue
            if lower.hasPrefix(LLMConfig.promptTag.lowercased()) {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                return
            }
            
            // Headers
            if trimmed.hasPrefix("#") && !trimmed.hasPrefix("#p") && !trimmed.hasPrefix("#opus") && !trimmed.hasPrefix("#error") {
                let headerFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
                attributedString.addAttribute(.font, value: headerFont, range: range)
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                return
            }
            
            // Date separator lines (--- YYYY-MM-DD ---)
            let dateSeparatorPattern = "^---\\s*\\d{4}-\\d{2}-\\d{2}\\s*---$"
            if let regex = try? NSRegularExpression(pattern: dateSeparatorPattern),
               regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemTeal, range: range)
                return
            }
            
            // Separator lines (horizontal rules)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                attributedString.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: range)
                return
            }
            
            // Todo checkboxes
            applyTodoStyle(line: line, lineNumber: lineNumber, range: range, attributedString: attributedString)
            
            // Tags
            applyTagStyle(line: line, range: range, attributedString: attributedString)
            
            // URLs
            applyURLStyle(line: line, range: range, attributedString: attributedString)
        }
        
        private func applyTodoStyle(line: String, lineNumber: Int, range: NSRange, attributedString: NSMutableAttributedString) {
            if let todoRange = line.range(of: "[ ]") {
                let nsRange = NSRange(todoRange, in: line)
                let absoluteRange = NSRange(location: range.location + nsRange.location, length: nsRange.length)
                if let url = URL(string: "todo://\(lineNumber)") {
                    attributedString.addAttributes([
                        .foregroundColor: UIColor.systemOrange,
                        .link: url
                    ], range: absoluteRange)
                }
            }
            
            if let doneRange = line.range(of: "[x]", options: .caseInsensitive) {
                let nsRange = NSRange(doneRange, in: line)
                let absoluteRange = NSRange(location: range.location + nsRange.location, length: nsRange.length)
                if let url = URL(string: "todo://\(lineNumber)") {
                    attributedString.addAttributes([
                        .foregroundColor: UIColor.systemGreen,
                        .link: url
                    ], range: absoluteRange)
                }
            }
        }
        
        private func applyTagStyle(line: String, range: NSRange, attributedString: NSMutableAttributedString) {
            let pattern = "(?<=\\s|^)#[a-zA-Z][a-zA-Z0-9_]*"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                let absoluteRange = NSRange(location: range.location + match.range.location, length: match.range.length)
                attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: absoluteRange)
            }
        }
        
        private func applyURLStyle(line: String, range: NSRange, attributedString: NSMutableAttributedString) {
            let pattern = "https?://[^\\s]+"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                let absoluteRange = NSRange(location: range.location + match.range.location, length: match.range.length)
                let urlString = (line as NSString).substring(with: match.range)
                if let url = URL(string: urlString) {
                    attributedString.addAttributes([
                        .foregroundColor: UIColor.link,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .link: url
                    ], range: absoluteRange)
                }
            }
        }
    }
}
#endif

// MARK: - Preview

#Preview {
    StyledTextEditor(text: .constant("""
# 2026-01-01 Daily Log

#p What should I focus on today?
#opus45 Here are my suggestions:
- **Focus** on the most important task
- Check your `config.json` file
---

## Tasks
- [ ] Buy groceries #personal
- [x] Review code #work
- [ ] Call mom #personal

Visit https://apple.com for more info.

#error Something went wrong here
"""))
}
