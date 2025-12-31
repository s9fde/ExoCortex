import SwiftUI

struct LogView: View {
    @ObservedObject var viewModel: LogViewModel
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        Group {
            if viewModel.isLocked {
                lockedView
            } else {
                unlockedView
            }
        }
        .padding()
    }

    private var lockedView: some View {
        VStack(spacing: 12) {
            Text("ExoCortex")
                .font(.largeTitle.bold())
            SecureField("Password", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit { viewModel.unlockWithPassword() }
            if let error = viewModel.unlockError {
                Text(error)
                    .foregroundColor(.red)
            }
            HStack {
                Button(action: { viewModel.unlockWithPassword() }) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Unlock")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Use Biometrics") { viewModel.unlockWithBiometrics() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var unlockedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar
            filterBar
            savedFiltersBar
            autosaveIndicator
            editor
            filteredList
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Logbook")
                .font(.title2.bold())
            Spacer()
            Button("Lock") { viewModel.lock() }
                .buttonStyle(.bordered)
        }
    }

    private var filterBar: some View {
        HStack {
            TextField("Filter (#tag, todo:open, &&, ||, !)", text: $viewModel.filterText)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button("Save filter") { viewModel.addSavedFilter(viewModel.filterText) }
                .buttonStyle(.bordered)
        }
    }

    private var savedFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.savedFilters, id: \.self) { filter in
                    Button(action: { viewModel.applySavedFilter(filter) }) {
                        Text(filter)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .contextMenu {
                        Button(role: .destructive) { viewModel.removeSavedFilter(filter) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var autosaveIndicator: some View {
        HStack(spacing: 8) {
            // Streaming indicator (AI response in progress)
            if viewModel.isStreaming {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI responding…")
                        .foregroundStyle(.purple)
                }
            } else {
                // Save status
                switch viewModel.saveStatus {
                case .idle:
                    Label("Idle", systemImage: "pause")
                        .foregroundStyle(.secondary)
                case .saving:
                    Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                case .saved:
                    Label("Saved", systemImage: "checkmark")
                        .foregroundStyle(.green)
                case .error(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if let filterError = viewModel.filterError {
                Text(filterError)
                    .foregroundColor(.red)
            }
        }
    }

    private var editor: some View {
        TextEditor(text: $viewModel.fullText)
            .font(.system(.body, design: .monospaced))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .disableAutocorrection(true)
            .frame(minHeight: 220)
            .focused($isEditorFocused)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    private var filteredList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.filteredLines) { line in
                    HStack(alignment: .top, spacing: 8) {
                        if line.isTodo {
                            Button(action: { viewModel.toggleTodo(for: line.id) }) {
                                Image(systemName: line.isDone ? "checkmark.square" : "square")
                                    .accessibilityLabel(line.isDone ? "Mark todo open" : "Mark todo done")
                            }
                            .buttonStyle(.plain)
                        }
                        coloredText(for: line.text)
                            .font(.system(.body, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func coloredText(for line: String) -> Text {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        
        // AI response tag
        if lower.hasPrefix(LLMConfig.responseTag.lowercased()) {
            return Text(line).foregroundColor(.purple)
        }
        // Error tag
        if lower.hasPrefix(LLMConfig.errorTag.lowercased()) {
            return Text(line).foregroundColor(.red)
        }
        // Prompt tag
        if lower.hasPrefix(LLMConfig.promptTag.lowercased()) {
            return Text(line).foregroundColor(.blue)
        }
        // Other tags (headers)
        if trimmed.hasPrefix("#") {
            return Text(line).foregroundColor(.accentColor)
        }
        // Lines with inline tags
        if trimmed.contains("#") {
            return Text(line).foregroundColor(.secondary)
        }
        return Text(line)
    }
}

#Preview {
    LogView(viewModel: LogViewModel())
}
