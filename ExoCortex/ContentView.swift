//
//  ContentView.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI
import LocalAuthentication

#if os(macOS)
import AppKit
#endif

// MARK: - Main Content View

/// Root view with standard sidebar navigation.
/// Shows lock screen when locked, split view when unlocked.
struct ContentView: View {
    @Environment(LogViewModel.self) private var viewModel
    @State private var viewsManager = ViewsManager()
    
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
        NavigationSplitView {
            SidebarView(viewsManager: viewsManager, selection: $sidebarSelection)
                .environment(viewModel)
        } detail: {
            detailContent
        }
        .onChange(of: sidebarSelection) { _, newSelection in
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

/// Clean, modern lock screen with animated tornado logo
struct LockScreen: View {
    @Bindable var viewModel: LogViewModel
    @FocusState private var passwordFocused: Bool
    @State private var tornadoDrawProgress: CGFloat = 0
    
    /// Biometric unlock available: device supports + password saved
    private var biometricAvailable: Bool {
        if case .available = viewModel.biometricStatus { return true }
        return false
    }
    
    /// Get biometric type from status (only available when enabled)
    private var biometricType: LABiometryType {
        if case let .available(type) = viewModel.biometricStatus { return type }
        return .none
    }
    
    /// Apple HIG-compliant biometric icon
    private var biometricIcon: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "person.badge.key"
        }
    }
    
    /// Apple HIG-compliant biometric label
    private var biometricLabel: String {
        switch biometricType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        case .opticID: return "Unlock with Optic ID"
        default: return "Unlock with Biometrics"
        }
    }
    
    var body: some View {
        ZStack {
            // Subtle gray background (matching main view)
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            #else
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #endif
            
            // Content
            VStack(spacing: 0) {
                Spacer()
                
                // Animated tornado logo with "Draw On" effect
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.12 * tornadoDrawProgress), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "tornado")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(tornadoDrawProgress)
                        .scaleEffect(0.8 + (0.2 * tornadoDrawProgress))
                        .shadow(color: .cyan.opacity(0.3 * tornadoDrawProgress), radius: 20, y: 5)
                }
                .padding(.bottom, 24)
                
                // App name
                Text("ExoCortex")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .opacity(tornadoDrawProgress)
                
                Text("Encrypted Work Log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .opacity(tornadoDrawProgress)
                
                Spacer()
                
                // Unlock card
                VStack(spacing: 16) {
                    // Password field - disabled autofill to prevent system password manager
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.init(rawValue: ""))  // Disables password autofill suggestions
                        .focused($passwordFocused)
                        .disabled(viewModel.isLoading)
                        .onSubmit { viewModel.unlockWithPassword() }
                    
                    // Unlock button
                    Button {
                        viewModel.unlockWithPassword()
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "lock.open.fill")
                            }
                            Text("Unlock")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.password.isEmpty || viewModel.isLoading)
                    
                    // Biometric unlock button (only shown if available)
                    if biometricAvailable {
                        Button {
                            viewModel.unlockWithBiometrics()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: biometricIcon)
                                Text(biometricLabel)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.isLoading)
                    }
                    
                    // Error message
                    if let error = viewModel.unlockError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .opacity(tornadoDrawProgress)
                
                Spacer()
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            passwordFocused = true
            viewModel.refreshBiometricStatus()
            startDrawOnAnimation()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    
    /// Draw-on animation: single ease-out animation on app start
    private func startDrawOnAnimation() {
        withAnimation(.easeOut(duration: 1.0)) {
            tornadoDrawProgress = 1.0
        }
    }
}

// MARK: - Sidebar Selection

/// Enum to represent what's selected in the sidebar
enum SidebarSelection: Hashable {
    case view(NamedView)
    case settings
}

// MARK: - Sidebar View

/// Standard sidebar with section headers for Views and Settings.
struct SidebarView: View {
    var viewsManager: ViewsManager
    @Environment(LogViewModel.self) private var viewModel
    @Binding var selection: SidebarSelection?
    
    var body: some View {
        List(selection: $selection) {
            Section("Views") {
                ForEach(viewsManager.views) { view in
                    sidebarRow(for: .view(view), label: view.name, icon: view.icon)
                }
            }
            
            Section {
                sidebarRow(for: .settings, label: "Settings", icon: "gear")
            }
        }
        .listStyle(.sidebar)
    }
    
    /// Creates a sidebar row that works with List selection
    @ViewBuilder
    private func sidebarRow(for value: SidebarSelection, label: String, icon: String) -> some View {
        #if os(macOS)
        // macOS: Simple selectable row (selection handled by List)
        Label(label, systemImage: icon)
            .tag(value)
        #else
        // iOS: Use NavigationLink for navigation
        NavigationLink(value: value) {
            Label(label, systemImage: icon)
        }
        #endif
    }
}

// MARK: - Log Editor View

/// Main editor view showing filtered content based on selected view.
/// Simple plain text editor - no syntax highlighting or complex scroll logic.
struct LogEditorView: View {
    @Bindable var viewModel: LogViewModel
    var viewsManager: ViewsManager
    
    var body: some View {
        TextKit2Editor(
            text: editorText,
            onFocusLost: {
                Task { await viewModel.forceSave() }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Scroll to bottom and position cursor at end on view appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                scrollToBottomAndFocus()
            }
        }
        .onChange(of: viewsManager.selectedView) { _, newView in
            viewModel.filterText = newView.filter
        }
    }
    
    /// Scroll to bottom and position cursor for immediate typing
    private func scrollToBottomAndFocus() {
        #if os(macOS)
        // Get the key window and find the NSTextView
        if let window = NSApplication.shared.keyWindow,
           let textView = findTextView(in: window.contentView) {
            // Position cursor at end
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
            // Scroll to end
            textView.scrollToEndOfDocument(self)
            // Focus
            window.makeFirstResponder(textView)
        }
        #elseif os(iOS)
        // For iOS, UITextView handles this natively
        // The cursor will be positioned at the end via binding
        #endif
    }
    
    /// Recursively find NSTextView in view hierarchy
    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let textView = view as? NSTextView {
            return textView
        }
        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }
        return nil
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
    
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(LogViewModel())
}
