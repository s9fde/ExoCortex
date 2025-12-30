//
//  ExoCortexApp.swift
//  ExoCortex
//
//  Created by Tom Schlenkhoff on 30.12.25.
//

import SwiftUI

@main
struct ExoCortexApp: App {
    @StateObject private var viewModel = LogViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        viewModel.lock()
                    }
                }
        }
    }
}
