//
//  ContentView.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI

// MARK: - Main Content View

/// Root view containing tab navigation between Log and Settings.
struct ContentView: View {
    @EnvironmentObject var viewModel: LogViewModel

    var body: some View {
        TabView {
            LogView(viewModel: viewModel)
                .tabItem {
                    Label("Log", systemImage: "note.text")
                }

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(LogViewModel())
}
