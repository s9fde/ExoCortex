//
//  SettingsView.swift
//  ExoCortex
//
//  Settings interface for views management and security options.
//

import SwiftUI

// MARK: - Settings View

/// Settings screen for managing views and security preferences.
struct SettingsView: View {
    var viewModel: LogViewModel
    var viewsManager: ViewsManager
    
    /// New view being created
    @State private var showingNewViewSheet = false
    @State private var showingEditViewSheet = false
    @State private var editingView: NamedView?

    @State private var modelInput: String = ""
    @State private var systemPromptInput: String = ""
    @State private var showResetAlert = false
    @State private var resetAction: ResetAction = .model
    
    enum ResetAction {
        case model
        case prompt
    }
    
    var body: some View {
        Form {
            viewsSection
            llmConfigSection
            securitySection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            modelInput = LLMConfig.activeModel
            systemPromptInput = LLMConfig.activeSystemPrompt
        }
        .sheet(isPresented: $showingNewViewSheet) {
            ViewEditSheet(
                viewsManager: viewsManager,
                view: nil,
                isPresented: $showingNewViewSheet
            )
        }
        .sheet(item: $editingView) { view in
            ViewEditSheet(
                viewsManager: viewsManager,
                view: view,
                isPresented: Binding(
                    get: { editingView != nil },
                    set: { if !$0 { editingView = nil } }
                )
            )
        }
    }
    
    // MARK: - Views Section
    
    private var viewsSection: some View {
        Section {
            ForEach(viewsManager.views) { view in
                if view.isBuiltIn {
                    // Built-in view (non-editable)
                    Label(view.name, systemImage: view.icon)
                        .foregroundStyle(.secondary)
                } else {
                    // User view (editable)
                    Button {
                        editingView = view
                    } label: {
                        HStack {
                            Label(view.name, systemImage: view.icon)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewsManager.removeView(view)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingView = view
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .onMove { from, to in
                viewsManager.moveViews(from: from, to: to)
            }
            
            Button {
                showingNewViewSheet = true
            } label: {
                Label("Add View", systemImage: "plus")
            }
        } header: {
            Text("Views")
        } footer: {
            Text("Tap a view to edit. Swipe left to delete, right to edit.")
        }
    }
    
    // MARK: - LLM Configuration Section
    
    private var llmConfigSection: some View {
        Group {
            Section {
                TextField("Model ID", text: $modelInput)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: modelInput) { _, newValue in
                        viewModel.saveLLMModel(newValue)
                    }
                
                TextEditor(text: $systemPromptInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .onChange(of: systemPromptInput) { _, newValue in
                        viewModel.saveSystemPrompt(newValue)
                    }
                
                Menu {
                    Button("Reset Model") {
                        resetAction = .model
                        showResetAlert = true
                    }
                    Button("Reset Prompt") {
                        resetAction = .prompt
                        showResetAlert = true
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .alert("Reset to Default?", isPresented: $showResetAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        switch resetAction {
                        case .model:
                            modelInput = LLMConfig.defaultModel
                            viewModel.saveLLMModel(LLMConfig.defaultModel)
                        case .prompt:
                            systemPromptInput = LLMConfig.defaultSystemPrompt
                            viewModel.saveSystemPrompt(LLMConfig.defaultSystemPrompt)
                        }
                    }
                }
            } header: {
                Text("LLM Configuration")
            } footer: {
                Text("Model ID and system prompt save automatically. Use the Reset menu to restore defaults.")
            }
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        Group {
            Section {
                HStack {
                    Text("Biometric Unlock")
                    Spacer()
                    Text(biometricStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    viewModel.rememberPasswordInKeychain()
                } label: {
                    Label("Enable Biometric Unlock", systemImage: biometricIcon)
                }
                
                Button(role: .destructive) {
                    viewModel.clearKeychainPassword()
                } label: {
                    Label("Clear Saved Password", systemImage: "key.slash")
                }
            } header: {
                Text("Biometric Security")
            } footer: {
                Text("Save your password to keychain for biometric unlock.")
            }
            
            Section(header: Text("OpenRouter API"), footer: Text("API key saves automatically to keychain.")) {
                SecureField("API Key", text: Binding(
                    get: { viewModel.apiKeyInput },
                    set: { viewModel.apiKeyInput = $0 }
                ))
                    .textContentType(.init(rawValue: ""))
                    .disableAutocorrection(true)
                    .onChange(of: viewModel.apiKeyInput) { _, _ in
                        viewModel.saveAPIKeyToKeychain()
                    }
                
                Button(role: .destructive) {
                    viewModel.clearAPIKeyFromKeychain()
                } label: {
                    Label("Clear API Key", systemImage: "key.slash")
                }
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("AI Model")
                Spacer()
                Text(LLMConfig.activeModel.components(separatedBy: "/").last ?? LLMConfig.activeModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    
    /// Human-readable biometric status for the settings display
    private var biometricStatusText: String {
        switch viewModel.biometricStatus {
        case .checking:
            return "Checking..."
        case .available(let type):
            switch type {
            case .faceID: return "Enabled (Face ID)"
            case .touchID: return "Enabled (Touch ID)"
            case .opticID: return "Enabled (Optic ID)"
            default: return "Enabled"
            }
        case .missingPassword:
            return "Password not saved"
        case .unavailable(let reason):
            return "Unavailable: \(reason)"
        }
    }
    
    /// System icon for biometric type
    private var biometricIcon: String {
        switch viewModel.biometricStatus {
        case .available(let type):
            switch type {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            default: return "person.badge.key"
            }
        default:
            return "faceid"
        }
    }
}

// MARK: - View Edit Sheet

/// Sheet for creating or editing a view.
struct ViewEditSheet: View {
    var viewsManager: ViewsManager
    
    /// The view being edited (nil for new view)
    var view: NamedView?
    
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var filter: String = ""
    @State private var icon: String = "doc.text"
    
    /// Available icons
    private let icons = [
        "doc.text", "checklist", "checkmark.circle", "sparkles",
        "briefcase", "person", "house", "star", "flag",
        "tag", "folder", "link", "globe", "clock"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("View Details") {
                    TextField("Name", text: $name)
                    TextField("Filter", text: $filter)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .foregroundStyle(icon == iconName ? Color.accentColor : .primary)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                
                Section("Filter Reference") {
                    VStack(alignment: .leading, spacing: 6) {
                        filterExample("todo:open", "Open todos")
                        filterExample("todo:done", "Completed todos")
                        filterExample("#work", "Lines with #work tag")
                        filterExample("http", "URLs")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(view == nil ? "New View" : "Edit View")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveView()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let existingView = view {
                    name = existingView.name
                    filter = existingView.filter
                    icon = existingView.icon
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }
    
    private func filterExample(_ filter: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(filter)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer()
            Text(description)
                .font(.caption)
        }
    }
    
    private func saveView() {
        if let existingView = view {
            // Update existing
            var updated = existingView
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.filter = filter.trimmingCharacters(in: .whitespaces)
            updated.icon = icon
            viewsManager.updateView(updated)
        } else {
            // Create new
            let newView = NamedView(
                name: name.trimmingCharacters(in: .whitespaces),
                filter: filter.trimmingCharacters(in: .whitespaces),
                icon: icon
            )
            viewsManager.addView(newView)
        }
        isPresented = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView(viewModel: LogViewModel(), viewsManager: ViewsManager())
    }
}
