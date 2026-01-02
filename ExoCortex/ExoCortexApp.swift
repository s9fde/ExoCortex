//
//  ExoCortexApp.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI

// MARK: - Main Application Entry Point

/// ExoCortex is an encrypted personal work log with AI assistant integration.
/// This app stores logs encrypted locally and provides Claude AI assistance via OpenRouter.
@main
struct ExoCortexApp: App {
    /// Shared view model managing log state, encryption, and AI interactions
    @StateObject private var viewModel = LogViewModel()
    
    /// App lifecycle phase for auto-locking
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                #if os(iOS)
                .onChange(of: scenePhase) { _, newPhase in
                    // iOS: Only lock when app goes to background (not just inactive)
                    // This prevents locking when opening notification center or control center
                    if newPhase == .background {
                        viewModel.lock()
                    }
                }
                #endif
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                    // macOS: Save and lock when window closes
                    if notification.object is NSWindow {
                        viewModel.lock()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // macOS: Save before app terminates
                    Task { await viewModel.forceSave() }
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) { }
            CommandGroup(replacing: .newItem) { }
        }
        #endif
    }
}
