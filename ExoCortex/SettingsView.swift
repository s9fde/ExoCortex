//
//  SettingsView.swift
//  ExoCortex
//
//  Settings interface for filter management and security options.
//

import SwiftUI

// MARK: - Settings View

/// Settings screen for managing saved filters and security preferences.
struct SettingsView: View {
    @ObservedObject var viewModel: LogViewModel
    
    /// Text input for new filter creation
    @State private var newFilter = ""

    var body: some View {
        Form {
            filterSection
            securitySection
            lockSection
        }
    }
    
    // MARK: - Sections
    
    /// Section for managing saved tag query filters
    private var filterSection: some View {
        Section("Saved Filters") {
            HStack {
                TextField("New filter", text: $newFilter)
                Button("Add") {
                    viewModel.addSavedFilter(newFilter)
                    newFilter = ""
                }
                .disabled(newFilter.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            
            ForEach(viewModel.savedFilters, id: \.self) { filter in
                HStack {
                    Text(filter)
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.removeSavedFilter(filter)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    /// Section for biometric and password security settings
    private var securitySection: some View {
        Section("Security") {
            Button("Remember password with biometrics") {
                viewModel.rememberPasswordInKeychain()
            }
            Button("Clear stored password", role: .destructive) {
                viewModel.clearKeychainPassword()
            }
        }
    }
    
    /// Section for manual lock control
    private var lockSection: some View {
        Section {
            Button("Lock now") {
                viewModel.lock()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView(viewModel: LogViewModel())
}
