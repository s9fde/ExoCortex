//
//  ValidationSheet.swift
//  ExoCortex
//
//  SwiftUI sheet for displaying scope validation errors and options.
//

import SwiftUI

/// Sheet for displaying validation errors
///
/// Shows:
/// - List of all validation errors
/// - Error details (what went wrong, where)
/// - User options: Cancel, Proceed (for pre-query), or Fix
struct ValidationSheet: View {
    @Binding var isPresented: Bool
    let errors: [ScopeError]
    let mode: ValidationMode
    var onProceed: (() -> Void)?
    var onFix: (() -> Void)?
    
    enum ValidationMode {
        /// Manual "Check Scopes" from menu
        case manual
        
        /// Before LLM query
        case preQuery
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Scope Validation")
                        .font(.headline)
                    Spacer()
                    if errors.isEmpty {
                        Text("✓ Valid")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("\(errorCount) \(mode == .preQuery ? "issue(s)" : "error(s)")")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.bottom, 4)
                
                // Error list
                if errors.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("All scopes valid")
                            .font(.headline)
                        
                        Text("Your tags are properly paired and nested.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    List(errors) { error in
                        ErrorRow(error: error)
                    }
                    .frame(maxHeight: 300)
                    .listStyle(.plain)
                }
                
                Divider()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Cancel", role: .cancel) {
                        isPresented = false
                    }
                    .tint(.gray)
                    
                    Spacer()
                    
                    if mode == .preQuery && !errors.isEmpty {
                        Button("Proceed Anyway", action: {
                            isPresented = false
                            onProceed?()
                        })
                        .tint(.orange)
                    }
                    
                    if !errors.isEmpty && onFix != nil {
                        Button("Go to Editor", action: {
                            isPresented = false
                            onFix?()
                        })
                        .tint(.blue)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
    
    var errorCount: Int {
        errors.filter { $0.severity == .error }.count
    }
}

// MARK: - Error Row

struct ErrorRow: View {
    let error: ScopeError
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Severity indicator
                Image(systemName: error.severity == .error ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(error.severity == .error ? .red : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.message)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if let details = error.details {
                        Text(details)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            }
            
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    
                    Text(error.message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let details = error.details {
                        Text(details)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Contextual help
                    HelpText(error: error)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Help Text

struct HelpText: View {
    let error: ScopeError
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How to fix:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(suggestion)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
    
    var suggestion: String {
        switch error {
        case .tagCrossDate:
            return "All non-date tags must be nested within a date block (<<YYYY-MM-DD...>>YYYY-MM-DD)."
        case .unopenedClose:
            return "This close tag (>>) has no matching opening tag (<<). Remove it or add the opening tag."
        case .mismatchedClose:
            return "Close this tag with the matching name, or ensure tags are in the correct nesting order."
        case .unclosedAtEOF:
            return "Add the corresponding close tags (>>) before the end of the file."
        case .invalidTagName:
            return "Tag names must start with a letter and contain only letters, numbers, hyphens, and underscores."
        case .duplicateOpen:
            return "Close the first tag before opening it again, or remove the duplicate opening tag."
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ValidationSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            ValidationSheet(
                isPresented: .constant(true),
                errors: [
                    .unopenedClose(tag: "work", line: 5, col: 2),
                    .mismatchedClose(expected: "meeting", found: "work", line: 12, col: 1)
                ],
                mode: .preQuery
            )
        }
    }
}
#endif
