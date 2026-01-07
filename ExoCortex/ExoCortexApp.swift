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
    @State private var viewModel = LogViewModel()
    

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                    if notification.object is NSWindow {
                        viewModel.lock()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await viewModel.forceSave() }
                }
                #endif
        }
        #if os(macOS)
        .commands {
            SidebarCommands()
            
            CommandGroup(after: .newItem) {
                Button("New Date Entry") {
                    viewModel.insertDateLine()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .appInfo) {
                Button("Lock Log") {
                    viewModel.lock()
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    Task { await viewModel.forceSave() }
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        #endif
    }
    
}
