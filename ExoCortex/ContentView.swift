//
//  ContentView.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI

// MARK: - Main Content View

/// Root view with Apple Notes-style sidebar navigation.
/// Shows lock screen when locked, split view when unlocked.
struct ContentView: View {
    @EnvironmentObject var viewModel: LogViewModel
    @StateObject private var viewsManager = ViewsManager()
    
    /// Column visibility for NavigationSplitView
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if viewModel.isLocked {
                LockScreen(viewModel: viewModel)
            } else {
                mainContent
            }
        }
    }
    
    // MARK: - Main Content (Unlocked)
    
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(viewsManager: viewsManager)
                .environmentObject(viewModel)
        } detail: {
            // Editor
            LogEditorView(viewModel: viewModel, viewsManager: viewsManager)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Lock Screen

/// Password entry screen shown when the log is locked.
struct LockScreen: View {
    @ObservedObject var viewModel: LogViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App icon/branding
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            
            Text("ExoCortex")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            
            Text("Encrypted Work Log")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Password field
            VStack(spacing: 12) {
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { viewModel.unlockWithPassword() }
                
                if let error = viewModel.unlockError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            // Unlock buttons
            HStack(spacing: 12) {
                Button(action: { viewModel.unlockWithPassword() }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Unlock")
                            .frame(minWidth: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.password.isEmpty || viewModel.isLoading)
                
                Button {
                    viewModel.unlockWithBiometrics()
                } label: {
                    Image(systemName: "faceid")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar View

/// Apple Notes-style sidebar with view navigation.
struct SidebarView: View {
    @ObservedObject var viewsManager: ViewsManager
    @EnvironmentObject var viewModel: LogViewModel
    
    var body: some View {
        List(selection: Binding(
            get: { viewsManager.selectedView },
            set: { if let view = $0 { viewsManager.selectView(view) } }
        )) {
            Section {
                ForEach(viewsManager.views) { view in
                    NavigationLink(value: view) {
                        Label(view.name, systemImage: view.icon)
                    }
                }
            }
            
            Section {
                NavigationLink {
                    SettingsView(viewModel: viewModel, viewsManager: viewsManager)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ExoCortex")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        #endif
    }
}

// MARK: - Log Editor View

/// Main editor view showing filtered content based on selected view.
struct LogEditorView: View {
    @ObservedObject var viewModel: LogViewModel
    @ObservedObject var viewsManager: ViewsManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Editor
            StyledTextEditor(
                text: editorText,
                onTodoToggle: { lineNumber in
                    viewModel.toggleTodo(for: lineNumber)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewsManager.selectedView.name)
        #if os(macOS)
        .navigationSubtitle(viewsManager.selectedView.filter.isEmpty ? "All notes" : viewsManager.selectedView.filter)
        #endif
        .onChange(of: viewsManager.selectedView) { _, newView in
            viewModel.filterText = newView.filter
        }
    }
    
    /// Text binding - shows full text for "All", filtered for others
    private var editorText: Binding<String> {
        if viewsManager.selectedView.filter.isEmpty {
            return $viewModel.fullText
        } else {
            return .constant(viewModel.filteredLines.map(\.text).joined(separator: "\n"))
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack(spacing: 8) {
            statusIndicator
            Spacer()
            
            if viewModel.isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI responding…")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
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
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(LogViewModel())
}
