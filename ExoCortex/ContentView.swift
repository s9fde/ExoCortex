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
                .environmentObject(viewModel)
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

// MARK: - Sidebar Selection

/// Enum to represent what's selected in the sidebar
enum SidebarSelection: Hashable {
    case view(NamedView)
    case settings
}

// MARK: - Sidebar View

/// Apple Mail-style sidebar with collapsible category groups.
struct SidebarView: View {
    @ObservedObject var viewsManager: ViewsManager
    @EnvironmentObject var viewModel: LogViewModel
    @Binding var selection: SidebarSelection?
    
    /// Tracks expansion state for each category
    @State private var expandedCategories: Set<SidebarCategory> = Set(SidebarCategory.allCases)
    
    /// Groups views by category
    private var groupedViews: [SidebarCategory: [NamedView]] {
        Dictionary(grouping: viewsManager.views) { $0.category }
    }
    
    /// Categories that have at least one view, in display order
    private var activeCategories: [SidebarCategory] {
        SidebarCategory.allCases.filter { groupedViews[$0]?.isEmpty == false }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Hierarchical views list
            List(selection: $selection) {
                ForEach(activeCategories) { category in
                    Section(isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCategories.insert(category)
                            } else {
                                expandedCategories.remove(category)
                            }
                        }
                    )) {
                        ForEach(groupedViews[category] ?? []) { view in
                            NavigationLink(value: SidebarSelection.view(view)) {
                                Label(view.name, systemImage: view.icon)
                            }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Settings button at bottom (separate from views)
            Button {
                selection = .settings
            } label: {
                HStack {
                    Label("Settings", systemImage: "gear")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(selection == .settings ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
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
    
    /// Search state
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var searchMatches: [Range<String.Index>] = []
    @State private var currentMatchIndex = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar (collapsible)
            if isSearchVisible {
                searchBar
                Divider()
            }
            
            // Status bar
            statusBar
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            Divider()
            
            // Editor
            StyledTextEditor(
                text: editorText,
                searchTerm: searchText,
                currentMatchIndex: currentMatchIndex,
                onTodoToggle: { lineNumber in
                    viewModel.toggleTodo(for: lineNumber)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(viewsManager.selectedView.name)
        #if os(macOS)
        .navigationSubtitle(viewsManager.selectedView.filter.isEmpty ? "" : viewsManager.selectedView.filter)
        .searchable(text: $searchText, isPresented: $isSearchVisible, prompt: "Search in log...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.insertDateLine()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .help("Insert date separator (--- YYYY-MM-DD ---)")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSearchVisible.toggle()
                    if !isSearchVisible {
                        searchText = ""
                        searchMatches = []
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
        #endif
        .onChange(of: viewsManager.selectedView) { _, newView in
            viewModel.filterText = newView.filter
        }
        .onChange(of: searchText) { _, newValue in
            updateSearchMatches(for: newValue)
        }
        .onChange(of: viewModel.fullText) { _, _ in
            updateSearchMatches(for: searchText)
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    goToNextMatch()
                }
            
            if !searchText.isEmpty {
                // Match counter
                Text(searchMatches.isEmpty ? "No matches" : "\(currentMatchIndex + 1) of \(searchMatches.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                
                // Navigation buttons
                Button {
                    goToPreviousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(searchMatches.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                
                Button {
                    goToNextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(searchMatches.isEmpty)
                .keyboardShortcut("g", modifiers: .command)
                
                // Clear button
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            
            // Close search bar
            Button {
                isSearchVisible = false
                searchText = ""
                searchMatches = []
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
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
    
    // MARK: - Search Logic
    
    private func updateSearchMatches(for query: String) {
        guard !query.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            return
        }
        
        let text = viewModel.fullText
        var matches: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            matches.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        
        searchMatches = matches
        
        // Reset index if needed
        if currentMatchIndex >= matches.count {
            currentMatchIndex = max(0, matches.count - 1)
        }
    }
    
    private func goToNextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        // TODO: Scroll to match in StyledTextEditor
    }
    
    private func goToPreviousMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        // TODO: Scroll to match in StyledTextEditor
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(LogViewModel())
}
