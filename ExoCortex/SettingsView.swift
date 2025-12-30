import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: LogViewModel
    @State private var newFilter: String = ""

    var body: some View {
        Form {
            Section(header: Text("Saved filters")) {
                HStack {
                    TextField("New filter", text: $newFilter)
                    Button("Add") {
                        viewModel.addSavedFilter(newFilter)
                        newFilter = ""
                    }
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

            Section(header: Text("Security")) {
                Button("Remember password with biometrics") {
                    viewModel.rememberPasswordInKeychain()
                }
                Button("Clear stored password", role: .destructive) {
                    viewModel.clearKeychainPassword()
                }
            }

            Section {
                Button("Lock now") { viewModel.lock() }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: LogViewModel())
}
