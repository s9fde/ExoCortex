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
    
    /// App lifecycle phase for auto-locking on background
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onChange(of: scenePhase) { _, newPhase in
                    // Auto-lock when app goes to background for security
                    if newPhase != .active {
                        viewModel.lock()
                    }
                }
        }
    }
}
