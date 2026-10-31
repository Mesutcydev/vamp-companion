import SwiftUI

/// Live view into one bot's computer from the phone: its shell, its workspace, and its output.
///
/// There is no screen to stream. A bot computer is a headless Alpine container running
/// `sleep infinity` with CLI tooling only, so "viewing the Linux VM" means these three things
/// rather than a framebuffer.
struct RemoteBotConsoleView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case shell = "Shell"
        case files = "Files"
        var id: String { rawValue }
    }

    let store: RemoteStore
    let computer: RemoteBotComputer

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: Tab = .shell
    @State private var command = ""
    @State private var transcript: [String] = []
    @State private var entries: [RemoteBotWorkspaceEntry] = []
    @State private var directory = ""
    @State private var preview: (path: String, contents: String)?
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemotePageSegments(selection: $tab,
                    options: Tab.allCases.map { ($0.rawValue, $0) })
                    .accessibilityLabel("Console view")
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if !store.isConnected {
                    RemoteReconnectBanner(store: store)
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                switch tab {
                case .shell: shell
                case .files: files
                }
            }
            .navigationTitle(computer.name)
            .navigationBarTitleDisplayMode(.inline)
            .remotePageChrome()
            .frame(maxWidth: RemoteInstrument.contentWidth).frame(maxWidth: .infinity)
            .background(RemoteInstrument.canvas)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }.vampUtilityAction()
            }
            .task(id: store.isConnected) { await loadFiles() }
        }
    }

    private var shell: some View {
        VStack(spacing: 8) {
            ScrollViewReader { scroll in
                ScrollView {
                    Text(transcript.isEmpty
                         ? "Commands run in /workspace inside this bot's computer."
                         : transcript.joined(separator: "\n"))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(transcript.isEmpty ? RemoteInstrument.secondaryInk : RemoteInstrument.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .id("transcript")
                }
                .padding(14).remotePageCard().padding(.horizontal, 16)
                .onChange(of: transcript.count) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { scroll.scrollTo("transcript", anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                TextField("ls -la", text: $command)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(run)
                    .accessibilityIdentifier("remote.bot.command")
                if isBusy {
                    ProgressView()
                } else {
                    Button("Run", action: run)
                        .accessibilityIdentifier("remote.bot.runCommand")
                        .buttonStyle(RemotePageButtonStyle(primary: true))
                        .disabled(!store.isConnected || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(10)
            .remotePageField()
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var files: some View {
        RemotePageForm {
            if !directory.isEmpty {
                Button {
                    directory = directory.contains("/")
                        ? String(directory[..<directory.lastIndex(of: "/")!])
                        : ""
                    Task { await loadFiles() }
                } label: {
                    Label("Up a level", systemImage: "arrow.up.left")
                }.disabled(!store.isConnected)
            }
            Section("/workspace" + (directory.isEmpty ? "" : "/\(directory)")) {
                if entries.isEmpty {
                    Text("This folder is empty.")
                        .font(.footnote)
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                }
                ForEach(entries) { entry in
                    Button {
                        open(entry)
                    } label: {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            Text(entry.name)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            if !entry.isDirectory {
                                Text(byteText(entry.byteSize))
                                    .font(.caption2)
                                    .foregroundStyle(RemoteInstrument.secondaryInk)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.isConnected)
                }
            }
            if let preview {
                Section(preview.path) {
                    Text(preview.contents)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .refreshable { await loadFiles() }
    }

    private func byteText(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private func run() {
        guard store.isConnected else {
            errorMessage = "Reconnect to your Mac before running a command."
            return
        }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        command = ""
        isBusy = true
        errorMessage = nil
        transcript.append("$ \(text)")
        Task {
            do {
                let output = try await store.execInBotComputer(computer.id, command: text)
                transcript.append(output.isEmpty ? "(no output)" : output)
            } catch {
                errorMessage = error.localizedDescription
            }
            // Bounded: this is a console, not a log store.
            if transcript.count > 200 { transcript.removeFirst(transcript.count - 200) }
            isBusy = false
        }
    }

    private func open(_ entry: RemoteBotWorkspaceEntry) {
        guard store.isConnected else { return }
        if entry.isDirectory {
            directory = entry.path
            preview = nil
            Task { await loadFiles() }
        } else {
            Task {
                do {
                    preview = (path: entry.path, contents: try await store.botComputerFile(computer.id, path: entry.path))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadFiles() async {
        guard store.isConnected else { return }
        do {
            entries = try await store.botComputerFiles(computer.id, path: directory)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }
}
