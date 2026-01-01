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
    @ObservedObject var viewModel: LogViewModel
    @ObservedObject var viewsManager: ViewsManager
    
    /// New view being created
    @State private var showingNewViewSheet = false
    @State private var showingEditViewSheet = false
    @State private var editingView: NamedView?

    var body: some View {
        Form {
            viewsSection
            securitySection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
                    HStack {
                        Label(view.name, systemImage: view.icon)
                        Spacer()
                        Text("Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // User view (editable)
                    HStack {
                        Label(view.name, systemImage: view.icon)
                        Spacer()
                        Text(view.filter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingView = view
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
            Text("Views filter your log content. Tap to edit, swipe to delete.")
        }
    }
    
    // MARK: - Security Section
    
    private var securitySection: some View {
        Section("Security") {
            Button {
                viewModel.rememberPasswordInKeychain()
            } label: {
                Label("Save Password with Biometrics", systemImage: "faceid")
            }
            .accessibilityHint("Stores your password securely for Face ID or Touch ID unlock")
            
            Button(role: .destructive) {
                viewModel.clearKeychainPassword()
            } label: {
                Label("Clear Saved Password", systemImage: "key.slash")
            }
            .accessibilityHint("Removes the stored password from the keychain")
            
            if let status = viewModel.keychainStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(status.contains("saved") || status.contains("cleared") ? .green : .red)
                    .textSelection(.enabled)
                    .accessibilityLabel("Keychain status: \(status)")
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text("Encryption")
                Spacer()
                Text("ChaCha20-Poly1305")
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Text("AI Model")
                Spacer()
                Text(LLMConfig.model.components(separatedBy: "/").last ?? LLMConfig.model)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - View Edit Sheet

/// Sheet for creating or editing a view.
struct ViewEditSheet: View {
    @ObservedObject var viewsManager: ViewsManager
    
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
        "tag", "folder", "link", "globe", "clock",
        "calendar", "bell", "bookmark", "heart", "bolt"
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        icon == iconName ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(icon == iconName ? Color.accentColor : .primary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    Text("Filter examples:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• `todo:open` - Open todos")
                        Text("• `todo:done` - Completed todos")
                        Text("• `#work` - Lines with #work tag")
                        Text("• `#opus45` - AI responses")
                        Text("• `http` - Lines containing URLs")
                        Text("• `#work && todo:open` - Work todos")
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
