//
//  ContentView.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI

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

#Preview {
    ContentView()
        .environmentObject(LogViewModel())
}
