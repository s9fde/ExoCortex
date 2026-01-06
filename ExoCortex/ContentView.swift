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
    @Environment(LogViewModel.self) private var viewModel
    @State private var viewsManager = ViewsManager()
    
    /// Column visibility for NavigationSplitView
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    /// Current sidebar selection
    @State private var sidebarSelection: SidebarSelection? = .view(.all)

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
            SidebarView(viewsManager: viewsManager, selection: $sidebarSelection)
                .environment(viewModel)
        } detail: {
            // Detail pane based on selection
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: sidebarSelection) { _, newSelection in
            // Update viewsManager when a view is selected
            if case .view(let view) = newSelection {
                viewsManager.selectView(view)
            }
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch sidebarSelection {
        case .view:
            LogEditorView(viewModel: viewModel, viewsManager: viewsManager)
        case .settings:
            SettingsView(viewModel: viewModel, viewsManager: viewsManager)
        case nil:
            Text("Select a view")
                .foregroundStyle(.secondary)
        }
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
                .accessibilityHidden(true)
            
            Text("ExoCortex")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            
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
                .accessibilityLabel("Unlock with password")
                .accessibilityHint("Decrypts and opens your work log")
                
                Button {
                    viewModel.unlockWithBiometrics()
                } label: {
                    Image(systemName: "faceid")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Unlock with Face ID")
                .accessibilityHint("Use biometric authentication to unlock")
            }
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
    }
}

// MARK: - Sidebar Selection

/// Enum to represent what's selected in the sidebar
enum SidebarSelection: Hashable {
    case view(NamedView)
    case settings
}

// MARK: - Sidebar View

/// Simple Apple HIG-style sidebar with flat list of views.
struct SidebarView: View {
    var viewsManager: ViewsManager
    @Environment(LogViewModel.self) private var viewModel
    @Binding var selection: SidebarSelection?
    
    @State private var searchText = ""
    
    var body: some View {
        List(selection: $selection) {
            // Search/Filter field at the top
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter log...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if !searchText.isEmpty {
                                let newView = NamedView(name: "Search: \(searchText)", filter: searchText, icon: "magnifyingglass")
                                viewsManager.addView(newView)
                                selection = .view(newView)
                                searchText = ""
                            }
                        }
                }
            }
            
            // All views in a simple flat list
            ForEach(viewsManager.views) { view in
                NavigationLink(value: SidebarSelection.view(view)) {
                    Label(view.name, systemImage: view.icon)
                }
            }
            
            // Settings at the bottom as a regular list item
            NavigationLink(value: SidebarSelection.settings) {
                Label("Settings", systemImage: "gear")
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
/// Simple plain text editor - no syntax highlighting or complex scroll logic.
struct LogEditorView: View {
    var viewModel: LogViewModel
    var viewsManager: ViewsManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Simple text editor with save on focus lost
            SimpleTextEditor(
                text: editorText,
                onFocusLost: {
                    Task { await viewModel.forceSave() }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewsManager.selectedView.name)
        #if os(macOS)
        .navigationSubtitle(viewsManager.selectedView.filter.isEmpty ? "" : viewsManager.selectedView.filter)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Undo AI Edit button
                Button {
                    viewModel.undoLLM()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Undo last AI edit (⌘Z)")
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!viewModel.canUndoLLM)
                
                // Date separator button
                Button {
                    viewModel.insertDateLine()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .help("Insert date separator (--- YYYY-MM-DD ---)")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        #endif
        .onChange(of: viewsManager.selectedView) { _, newView in
            viewModel.filterText = newView.filter
        }
    }
    
    /// Text binding - shows full text for "All", filtered for others
    /// Both are now editable - changes in filtered view sync back to fullText
    private var editorText: Binding<String> {
        if viewsManager.selectedView.filter.isEmpty {
            return $viewModel.fullText
        } else {
            return $viewModel.filteredText
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
                .accessibilityLabel("Status: Ready")
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel("Status: Saving changes")
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityLabel("Status: All changes saved")
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(LogViewModel())
}
