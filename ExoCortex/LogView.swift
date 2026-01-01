//
//  LogView.swift
//  ExoCortex
//
//  Main log editor view with lock screen and unified styled editor.
//

import SwiftUI

// MARK: - Log View

/// Primary view for displaying and editing the encrypted work log.
/// Features a unified styled editor with syntax highlighting and clickable elements.
struct LogView: View {
    @ObservedObject var viewModel: LogViewModel

    var body: some View {
        Group {
            if viewModel.isLocked {
                lockedView
            } else {
                unlockedView
            }
        }
        .padding()
    }

    // MARK: - Lock Screen
    
    /// Password entry screen shown when the log is locked
    private var lockedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("ExoCortex")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            Text("Encrypted Work Log")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { viewModel.unlockWithPassword() }
            
            if let error = viewModel.unlockError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 12) {
                Button(action: { viewModel.unlockWithPassword() }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.password.isEmpty || viewModel.isLoading)

                Button("Biometrics") {
                    viewModel.unlockWithBiometrics()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
    }

    // MARK: - Main Editor
    
    /// Unlocked state showing the unified styled editor
    private var unlockedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            filterBar
            savedFiltersBar
            statusBar
            editor
        }
    }

    /// Top bar with title and lock button
    private var headerBar: some View {
        HStack {
            Text("Logbook")
                .font(.title2.bold())
            Spacer()
            Button {
                viewModel.lock()
            } label: {
                Label("Lock", systemImage: "lock.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// Filter input field and save button
    private var filterBar: some View {
        HStack {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter (#tag, todo:open, &&, ||)", text: $viewModel.filterText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !viewModel.filterText.isEmpty {
                    Button {
                        viewModel.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            
            Button {
                viewModel.addSavedFilter(viewModel.filterText)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.filterText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Horizontal scrolling list of saved filters
    private var savedFiltersBar: some View {
        Group {
            if !viewModel.savedFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.savedFilters, id: \.self) { filter in
                            Button { viewModel.applySavedFilter(filter) } label: {
                                HStack(spacing: 4) {
                                    Text(filter)
                                        .font(.caption)
                                    Button {
                                        viewModel.removeSavedFilter(filter)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    filter == viewModel.filterText ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Status bar showing save state and streaming progress
    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI responding…")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            } else {
                statusIndicator
            }
            
            Spacer()
            
            if let filterError = viewModel.filterError {
                Text(filterError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(height: 20)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.saveStatus {
        case .idle:
            Label("Ready", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    /// Main styled text editor
    private var editor: some View {
        StyledTextEditor(
            text: viewModel.filterText.isEmpty ? $viewModel.fullText : .constant(filteredText),
            onTodoToggle: { lineNumber in
                viewModel.toggleTodo(for: lineNumber)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    /// Filtered text when a filter is active
    private var filteredText: String {
        viewModel.filteredLines.map(\.text).joined(separator: "\n")
    }
}

// MARK: - Preview

#Preview {
    LogView(viewModel: LogViewModel())
}
