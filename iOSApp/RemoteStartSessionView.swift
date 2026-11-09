import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A compact composer control: the current choice, tappable to change it.
struct RemoteStartChip: View {
  let title: String
  let symbol: String
  var showsChevron = true

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.caption.weight(.semibold))
        .foregroundStyle(BeetTheme.accentBright).accessibilityHidden(true)
      Text(title).lineLimit(1).truncationMode(.middle)
      if showsChevron {
        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
          .foregroundStyle(RemoteInstrument.secondaryInk).accessibilityHidden(true)
      }
    }
    .font(.footnote.weight(.semibold)).foregroundStyle(RemoteInstrument.ink)
    .padding(.horizontal, 12).frame(minHeight: 34)
    .vampGlass(Capsule(), interactive: true)
    // 34-point capsule, 44-point target.
    .padding(.vertical, 5).contentShape(Rectangle())
  }
}

/// The permission flags stay independent and reach the same Mac gate.
struct RemoteAdvancedAccessBank: View {
  @Binding var autoMode: Bool
  @Binding var fullAccess: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Auto mode", isOn: $autoMode)
        .frame(minHeight: 44)
        .accessibilityHint("Runs the task without pausing for your approval.")
      RemotePageDivider()
      Toggle("Full access", isOn: $fullAccess)
        .frame(minHeight: 44)
        .accessibilityHint("Runs without approval prompts, including file writes and commands.")
      Text(autoMode || fullAccess
           ? "This run skips approval prompts."
           : "Your Mac's approval settings apply.")
        .font(.caption)
        .foregroundStyle(autoMode || fullAccess ? RemoteInstrument.orange : RemoteInstrument.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .font(.subheadline).tint(BeetTheme.accent)
  }
}

struct StartSessionSheet: View {
  @Bindable var store: RemoteStore
  let initialBotID: String
  let initialModelID: String?
  let onStarted: (UUID) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.remoteAppearance) private var appearance
  @State private var source = "local"
  @State private var selectedModelID = ""
  @State private var selectedReasoningEffort: String?
  @State private var showModelPicker = false
  @State private var prompt = ""
  @State private var botComputers: [RemoteBotComputer] = []
  @State private var selectedBotComputerID: UUID?
  @State private var botComputerBusyID: UUID?
  @State private var consoleComputer: RemoteBotComputer?
  @State private var keyProviderID = "openAI"
  @State private var keyDraft = ""
  @State private var isSavingKey = false
  @State private var keyMessage: String?
  @State private var selectedBotID = ""
  @State private var sessionMode: RemoteSessionMode = .chat
  @State private var autoMode = true
  @State private var fullAccess = false
  @State private var isLoadingModels = false
  @State private var isStarting = false
  @State private var selectedWorkspacePath = ""
  @State private var newFolderName = ""
  @State private var showNewFolder = false
  @State private var folderPathDraft = ""
  @State private var showPathEntry = false
  @State private var didRestoreChoices = false
  @State private var showWorkspace = false
  @State private var showAPIKey = false
  private let focusOnOpen: Bool
  // Start choices follow the Mac's restored-project behavior without
  // becoming part of the remote protocol or a persisted prompt draft.
  @AppStorage("remoteStart.sessionMode") private var savedSessionModeRaw =
    RemoteSessionMode.chat.rawValue
  @AppStorage("remoteStart.source") private var savedSource = "local"
  @AppStorage("remoteStart.modelID") private var savedModelID = ""
  @AppStorage("remoteStart.reasoningEffort") private var savedReasoningEffort = ""
  @AppStorage("remoteStart.workspacePath") private var savedWorkspacePath = ""
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    store: RemoteStore, initialBotID: String, initialPrompt: String = "",
    initialModelID: String? = nil,
    onStarted: @escaping (UUID) -> Void
  ) {
    self.store = store
    self.initialBotID = initialBotID
    self.initialModelID = initialModelID
    self.onStarted = onStarted
    // Writing is the first step; reviewed quick starts keep the keyboard down.
    focusOnOpen = initialPrompt.isEmpty
    _prompt = State(initialValue: initialPrompt)
  }

  // The App Store Mac edition omits these; older hosts send no list and keep
  // every option.
  private var codeModeAvailable: Bool { store.hostStatus?.capabilities?.contains("workspaces") ?? true }
  private var botsAvailable: Bool { store.hostStatus?.capabilities?.contains("bots") ?? true }
  private var reasoningEfforts: [String] {
    models.first(where: { $0.id == selectedModelID })?.reasoningEfforts ?? []
  }

  private var codeFolderMissing: Bool {
    sessionMode == .code
      && selectedBotComputerID == nil
      && (selectedWorkspacePath.isEmpty || !store.workspacesSupported)
  }

  private var canStart: Bool {
    store.isConnected
      && !selectedModelID.isEmpty
      && store.startModels.contains(where: { $0.id == selectedModelID })
      && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !isLoadingModels
      && !isStarting
      && !codeFolderMissing
  }

  private var botProfile: RemoteBotProfile {
    RemoteBotProfile.profile(
      id: selectedBotID.isEmpty ? RemoteBotProfile.general.id : selectedBotID)
  }
  private var restoredSessionMode: RemoteSessionMode {
    RemoteSessionMode(rawValue: savedSessionModeRaw) ?? .chat
  }
  private var restoredReasoningEffort: String? {
    savedReasoningEffort.isEmpty ? nil : savedReasoningEffort
  }
  private var models: [RemoteStartModelOption] { store.startModels.filter { $0.source == source } }
  private var selectedWorkspaceTitle: String {
    guard !selectedWorkspacePath.isEmpty else { return "Choose a folder" }
    return store.workspaces.first(where: { $0.path == selectedWorkspacePath })?.name
      ?? selectedWorkspacePath
  }
  private var sourceIcon: String {
    switch source {
    case "chatgpt": "person.crop.circle"
    case "api": "cloud"
    default: "cpu"
    }
  }
  private var emptyModelsTitle: String {
    switch source {
    case "chatgpt": "No ChatGPT models"
    case "api": "No API models"
    default: "No local models"
    }
  }
  private var emptyModelsDescription: String {
    switch source {
    case "chatgpt": "Sign in with ChatGPT on your Mac to use GPT-6 Astra, then refresh."
    case "api": "Configure an API provider on your Mac first."
    default: "Download a model on your Mac first."
    }
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        ScrollView {
          VStack(spacing: 18) {
            if !store.isConnected { RemoteReconnectBanner(store: store) }
            greeting
            catalogNotice
            if let hint = startHint {
              Label(hint, systemImage: "info.circle")
                .font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
          .frame(maxWidth: RemoteInstrument.contentWidth)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .background { RemoteBackdrop() }
      .navigationTitle(sessionMode == .chat ? "New chat" : "New code session")
      .navigationBarTitleDisplayMode(.inline)
      .remotePageChrome()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
            .tint(RemoteInstrument.ink)
        }
        ToolbarItem(placement: .principal) {
          if codeModeAvailable {
            modePicker.pickerStyle(.segmented).frame(width: 190)
          } else {
            Text(sessionMode == .chat ? "New chat" : "New code session").font(.headline)
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
          setupChips
          RemoteComposer(
            draft: $prompt, isRunning: false, isReachable: store.isConnected, isSending: isStarting,
            onSend: start, onStop: {},
            modelName: store.startModels.contains(where: { $0.id == selectedModelID }) ? selectedModelName : nil,
            onSelectModel: { showModelPicker = true },
            modeName: sessionMode.title,
            editorID: "remote.start.prompt", primaryID: "remote.start.submit",
            sendLabel: sessionMode == .chat ? "Start chat" : "Start session",
            placeholderText: sessionMode == .chat ? "Message Vamp…" : "What should Vamp work on?",
            canSend: canStart, autoFocus: focusOnOpen)
        }
      }
      .sheet(isPresented: $showModelPicker) {
        RemoteModelPickerSheet(
          models: store.startModels,
          source: $source,
          selectedModelID: $selectedModelID,
          onSelect: { selectedReasoningEffort = $0.defaultReasoningEffort },
          onRefresh: { await store.loadStartModels() },
          loadedLocalModel: store.loadedLocalModel,
          isUnloadingModel: store.isUnloadingModel,
          isConnected: store.isConnected,
          onUnload: { await store.unloadLocalModel() }
        )
        .environment(\.remoteAppearance, appearance)
      }
      .sheet(isPresented: $showWorkspace) {
        NavigationStack {
          workspacePage
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWorkspace = false } } }
        }
        .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $showAPIKey) {
        NavigationStack { apiKeyPage }
          .presentationDetents([.medium])
      }
      .task {
        guard !didRestoreChoices else { return }
        didRestoreChoices = true
        selectedBotID = botsAvailable ? initialBotID : ""
        source = savedSource
        selectedModelID = savedModelID
        selectedReasoningEffort = restoredReasoningEffort
        sessionMode = codeModeAvailable ? restoredSessionMode : .chat
        selectedWorkspacePath = savedWorkspacePath
        // Unsupported routes answer 403, which would surface as an alert.
        async let models: Void = loadModels()
        async let computers: Void = botsAvailable ? loadBotComputers() : ()
        async let folders: Void = codeModeAvailable ? store.loadWorkspaces() : ()
        _ = await (models, computers, folders)
        if let initialModelID,
           let model = store.startModels.first(where: { $0.id == initialModelID }) {
          source = model.source
          selectedModelID = model.id
          selectedReasoningEffort = model.defaultReasoningEffort
        }
        attachMatchingBotComputer()
        selectFirstModel(allowSourceFallback: true)
        if store.workspacesSupported {
          if !store.workspaces.contains(where: { $0.path == selectedWorkspacePath }) {
            selectedWorkspacePath =
              store.workspaces.first(where: { $0.isCurrent == true })?.path
              ?? store.workspaces.first?.path
              ?? ""
          }
        } else {
          selectedWorkspacePath = ""
        }
        savedWorkspacePath = selectedWorkspacePath
      }
      .onChange(of: source) { _, newValue in
        savedSource = newValue
        selectFirstModel()
      }
      .onChange(of: selectedModelID) { _, newValue in
        savedModelID = newValue
      }
      .onChange(of: selectedReasoningEffort) { _, newValue in
        savedReasoningEffort = newValue ?? ""
      }
      .onChange(of: selectedWorkspacePath) { _, newValue in
        savedWorkspacePath = newValue
      }
      .onChange(of: sessionMode) { _, mode in
        savedSessionModeRaw = mode.rawValue
        handleModeChange(mode)
      }
      .onChange(of: selectedBotID) { _, _ in attachMatchingBotComputer() }
      .keyboardDismissToolbar()
    }
    .remotePageErrors(store: store)
  }

  // MARK: Shared pieces

  private var modePicker: some View {
    Picker("Session mode", selection: $sessionMode) {
      ForEach(RemoteSessionMode.allCases) { Text($0.title).tag($0) }
    }
  }

  private var greeting: some View {
    VStack(spacing: 10) {
      RemoteBeaconMark(size: 46, isActive: isLoadingModels || isStarting)
      Text(sessionMode == .chat ? "Ask Vamp anything" : "What should Vamp work on?")
        .font(.title2.weight(.bold)).multilineTextAlignment(.center)
      Text(summary).font(.subheadline).foregroundStyle(RemoteInstrument.secondaryInk)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  /// One line that says where and how the chat will run.
  private var summary: String {
    var parts = [store.activeComputerName]
    if sessionMode == .code { parts.append(selectedBotComputerID == nil ? selectedWorkspaceTitle : "Bot computer") }
    if botsAvailable { parts.append(botProfile.name) }
    parts.append(permissionTitle)
    return parts.joined(separator: " · ")
  }

  private var permissionTitle: String { fullAccess ? "Full access" : autoMode ? "Auto mode" : "Asks first" }
  private var permissionSymbol: String { autoMode || fullAccess ? "bolt.shield" : "checkmark.shield" }
  private var whereTitle: String {
    selectedBotComputerID == nil ? selectedWorkspaceTitle
      : botComputers.first(where: { $0.id == selectedBotComputerID }).map { displayName(for: $0) } ?? "Bot computer"
  }

  private var botMenu: some View {
    Picker("Bot", selection: $selectedBotID) {
      ForEach(RemoteBotProfile.profiles) { profile in
        Label(profile.name, systemImage: profile.symbol).tag(RemoteBotProfile.resolvedID(profile.id) ?? "")
      }
    }
  }

  @ViewBuilder private var permissionMenu: some View {
    Toggle("Auto mode", isOn: $autoMode)
    Toggle("Full access", isOn: $fullAccess)
    Divider()
    Text(autoMode || fullAccess ? "This run skips approval prompts." : "Your Mac's approval settings apply.")
  }

  private var reasoningMenu: some View {
    Picker("Reasoning", selection: $selectedReasoningEffort) {
      Text("Auto").tag(String?.none)
      ForEach(reasoningEfforts, id: \.self) { Text($0.capitalized).tag(Optional($0)) }
    }
  }

  /// The choices sit right above the message as glass chips, so setting up
  /// the chat never leaves the chat.

  private var setupChips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        if sessionMode == .code {
          Button { showWorkspace = true } label: {
            RemoteStartChip(title: whereTitle, symbol: selectedBotComputerID == nil ? "folder" : "square.stack.3d.up")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Project folder, \(whereTitle)")
        }
        if botsAvailable {
          Menu { botMenu } label: { RemoteStartChip(title: botProfile.name, symbol: botProfile.symbol) }
            .accessibilityLabel("Bot, \(botProfile.name)")
        }
        Menu { permissionMenu } label: { RemoteStartChip(title: permissionTitle, symbol: permissionSymbol) }
          .accessibilityLabel("Permissions, \(permissionTitle)")
          .accessibilityIdentifier("remote.start.options")
        if !reasoningEfforts.isEmpty {
          Menu { reasoningMenu } label: {
            RemoteStartChip(title: selectedReasoningEffort?.capitalized ?? "Reasoning", symbol: "brain.head.profile")
          }
          .accessibilityLabel("Reasoning, \(selectedReasoningEffort?.capitalized ?? "Auto")")
        }
        if source == "api" {
          Button { showAPIKey = true } label: { RemoteStartChip(title: "API key", symbol: "key", showsChevron: false) }
            .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 14)
    }
    .scrollIndicators(.hidden)
    .scrollClipDisabled()
  }

  // MARK: Second-level pages

  private var workspacePage: some View {
    RemotePageScroll {
      workspaceSection
      if botsAvailable { botComputerSection }
    }
    .navigationTitle("Where Vamp works").navigationBarTitleDisplayMode(.inline)
    .remotePageChrome()
    .sheet(item: $consoleComputer) { computer in
      RemoteBotConsoleView(store: store, computer: computer)
    }
    .modifier(workspaceAlerts)
    .remotePageErrors(store: store)
  }

  private var apiKeyPage: some View {
    RemotePageScroll { apiKeySection.padding(14).remotePageCard() }
      .navigationTitle("API key").navigationBarTitleDisplayMode(.inline)
      .remotePageChrome()
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAPIKey = false } } }
  }

  private var workspaceAlerts: RemoteWorkspaceAlerts {
    RemoteWorkspaceAlerts(showNewFolder: $showNewFolder, newFolderName: $newFolderName,
      showPathEntry: $showPathEntry, folderPathDraft: $folderPathDraft,
      parent: store.workspaceCreateParent, onCreate: createFolder, onOpen: openFolderPath)
  }

  @ViewBuilder
  private var catalogNotice: some View {
    if isLoadingModels {
      RemoteNoticeLabel(title: "Loading models…", detail: "Asking your Mac what it can run.", isWorking: true)
    } else if let notice = store.backgroundNotice {
      Button { loadModels() } label: {
        RemoteNoticeLabel(title: "Model catalog unavailable", detail: notice, actionTitle: "Retry",
          symbol: "exclamationmark.triangle.fill")
      }
      .buttonStyle(.plain)
    } else if store.isConnected, store.startModels.isEmpty {
      RemoteNoticeLabel(title: emptyModelsTitle, detail: emptyModelsDescription, symbol: sourceIcon)
    }
  }

  private var startHint: String? {
    if !store.isConnected { return "Connect to your Mac to start." }
    if isLoadingModels { return "Finding your models…" }
    if selectedModelID.isEmpty { return "Choose a model to start." }
    if codeFolderMissing { return "Choose a project folder to start." }
    return nil
  }

  private var selectedModelName: String {
    guard let selected = store.startModels.first(where: { $0.id == selectedModelID }) else {
      return models.isEmpty ? emptyModelsTitle : "Choose a model"
    }
    return selected.name
  }

  private func loadModels() async {
    isLoadingModels = true
    await store.loadStartModels()
    isLoadingModels = false
    selectFirstModel(allowSourceFallback: true)
  }

  private func loadModels() {
    Task { await loadModels() }
  }

  private func handleModeChange(_ mode: RemoteSessionMode) {
    guard mode == .chat else { return }
    selectedBotComputerID = nil
  }

  private func selectFirstModel(allowSourceFallback: Bool = false) {
    let selected = Self.preferredModel(in: store.startModels, source: source,
      selectedID: selectedModelID, loadedID: store.loadedLocalModel?.id,
      allowSourceFallback: allowSourceFallback)
    if selectedModelID != selected?.id
      || !(selected?.reasoningEfforts ?? []).contains(selectedReasoningEffort ?? "") {
      selectedReasoningEffort = selected?.defaultReasoningEffort
    }
    selectedModelID = selected?.id ?? ""
    if let selected { source = selected.source }
  }

  /// Opening a new chat should reuse a valid choice, then a resident model,
  /// then an available source. Explicit source changes stay in that source.
  static func preferredModel(in catalog: [RemoteStartModelOption], source: String,
    selectedID: String, loadedID: String?, allowSourceFallback: Bool
  ) -> RemoteStartModelOption? {
    let candidates = allowSourceFallback ? catalog : catalog.filter { $0.source == source }
    if let saved = candidates.first(where: { $0.id == selectedID }) { return saved }
    if let loadedID, let loaded = candidates.first(where: { $0.id == loadedID }) { return loaded }
    let inSource = candidates.filter { $0.source == source }
    return inSource.first(where: \.isLatest) ?? inSource.first
      ?? candidates.first(where: \.isLatest) ?? candidates.first
  }

  @ViewBuilder
  private var workspaceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Project folder").font(.footnote.weight(.semibold))
        Spacer()
        if selectedBotComputerID != nil {
          Text("Bot computer")
            .font(.caption)
        }
      }.foregroundStyle(BeetTheme.secondaryText(appearance))
      if !store.workspacesSupported {
        Text("Update Vamp Companion on your Mac to open or create a project folder from here.")
          .font(.subheadline)
          .foregroundStyle(BeetTheme.secondaryText(appearance))
      } else if selectedBotComputerID != nil {
        Text("This session uses the selected bot computer’s workspace and private browser.")
          .font(.subheadline)
          .foregroundStyle(BeetTheme.secondaryText(appearance))
      } else {
        if store.workspaces.isEmpty {
          Text("No recent folders yet. Create one or open a path on your Mac.")
            .font(.subheadline)
            .foregroundStyle(BeetTheme.secondaryText(appearance))
        } else {
          VStack(spacing: 0) {
            ForEach(store.workspaces) { folder in
              Button {
                selectedWorkspacePath = folder.path
              } label: {
                HStack(spacing: 12) {
                  Image(
                    systemName: selectedWorkspacePath == folder.path
                      ? "checkmark.circle.fill" : "folder.fill"
                  )
                  .foregroundStyle(
                    selectedWorkspacePath == folder.path
                      ? BeetTheme.accentBright : BeetTheme.secondaryText(appearance)
                  )
                  .frame(width: 24)
                  .accessibilityHidden(true)
                  VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name).font(.body.weight(.semibold))
                    Text(folder.path).font(.caption).foregroundStyle(
                      BeetTheme.secondaryText(appearance)
                    ).lineLimit(1)
                  }
                  Spacer()
                }.padding(13).contentShape(Rectangle())
                  .accessibilityAddTraits(selectedWorkspacePath == folder.path ? .isSelected : [])
              }.buttonStyle(.plain)
              if folder.path != store.workspaces.last?.path {
                Divider().overlay(BeetTheme.line(appearance))
              }
            }
          }
          .remotePageCard()
        }
        HStack(spacing: 10) {
          Button {
            showNewFolder = true
          } label: {
            Label("New folder", systemImage: "folder.badge.plus")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(RemotePageButtonStyle())
          Button {
            showPathEntry = true
          } label: {
            Label("Path", systemImage: "text.alignleft")
              .font(.subheadline.weight(.semibold))
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(RemotePageButtonStyle())
        }
      }
    }
  }

  private func createFolder() {
    let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    newFolderName = ""
    guard !name.isEmpty else { return }
    Task {
      if let created = await store.createWorkspace(name: name) {
        selectedWorkspacePath = created.path
      }
    }
  }

  private func openFolderPath() {
    let path = folderPathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    folderPathDraft = ""
    guard !path.isEmpty else { return }
    Task {
      if let opened = await store.openWorkspace(path: path) {
        selectedWorkspacePath = opened.path
      }
    }
  }

  @ViewBuilder
  private var botComputerSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Bot computer").font(.footnote.weight(.semibold))
        Spacer()
        Text(
          botComputers.isEmpty
            ? "None prepared on Mac"
            : (selectedBotComputerID == nil ? "Optional — tap to attach" : "Attached")
        )
        .font(.caption)
      }.foregroundStyle(BeetTheme.secondaryText(appearance))
      if !botComputers.isEmpty {
        VStack(spacing: 0) {
          ForEach(botComputers) { computer in
            HStack(spacing: 11) {
              Button {
                guard canAttachBotComputer(computer) else { return }
                selectedBotComputerID = selectedBotComputerID == computer.id ? nil : computer.id
                if selectedBotComputerID != nil { sessionMode = .code }
              } label: {
                HStack(spacing: 11) {
                  Image(
                    systemName: selectedBotComputerID == computer.id
                      ? "checkmark.circle.fill" : "square.stack.3d.up.fill"
                  )
                  .foregroundStyle(
                    selectedBotComputerID == computer.id
                      ? BeetTheme.accentBright : BeetTheme.secondaryText(appearance))
                  VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(for: computer)).font(.body.weight(.semibold))
                    Text(botComputerSubtitle(computer))
                      .font(.caption).foregroundStyle(BeetTheme.secondaryText(appearance))
                  }
                  Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(!canAttachBotComputer(computer))
              .accessibilityLabel(
                selectedBotComputerID == computer.id
                  ? "Detach \(displayName(for: computer))" : "Attach \(displayName(for: computer))"
              )
              .accessibilityValue(botComputerSubtitle(computer))
              .accessibilityAddTraits(selectedBotComputerID == computer.id ? .isSelected : [])
              // A bot computer has no screen to stream; its console is the shell,
              // the workspace, and the output.
              Button {
                consoleComputer = computer
              } label: {
                Image(systemName: "terminal")
              }
              .buttonStyle(RemotePageButtonStyle())
              .accessibilityLabel("Open \(displayName(for: computer)) console")
              if computer.state == "running" {
                Button(botComputerBusyID == computer.id ? "Stopping…" : "Stop") {
                  stopBotComputer(computer)
                }
                .buttonStyle(RemotePageButtonStyle())
                .disabled(botComputerBusyID != nil)
              } else if computer.backend != "isolatedWorkspace" {
                Button(botComputerBusyID == computer.id ? "Starting…" : "Start") {
                  startBotComputer(computer)
                }
                .buttonStyle(RemotePageButtonStyle(primary: true)).tint(BeetTheme.accentBright)
                .disabled(botComputerBusyID != nil)
              }
            }
            .padding(13)
            if computer.id != botComputers.last?.id {
              Divider().overlay(BeetTheme.line(appearance))
            }
          }
        }
        .remotePageCard()
      }
      if let profileID = RemoteBotProfile.resolvedID(selectedBotID),
        !botComputers.contains(where: { $0.profileID == profileID })
      {
        Button {
          prepareBotComputer(profileID: profileID)
        } label: {
          Label("Create \(botProfile.name) computer on Mac", systemImage: "plus")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(RemotePageButtonStyle())
        .disabled(botComputerBusyID != nil || !store.isConnected)
      } else if botComputers.isEmpty {
        Button {
          prepareBotComputer(profileID: nil)
        } label: {
          Label("Prepare bot computers on Mac", systemImage: "plus")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(RemotePageButtonStyle())
        .disabled(botComputerBusyID != nil || !store.isConnected)
      }
    }
  }

  private func displayName(for computer: RemoteBotComputer) -> String {
    computer.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(
      "Beet") == .orderedSame
      ? "Assistant computer"
      : computer.name
  }

  private func canAttachBotComputer(_ computer: RemoteBotComputer) -> Bool {
    computer.state == "running" || computer.backend == "isolatedWorkspace"
  }

  private func botComputerSubtitle(_ computer: RemoteBotComputer) -> String {
    let backend: String
    switch computer.backend {
    case "appleContainer": backend = "Linux micro-VM"
    case "isolatedWorkspace": backend = "Private workspace"
    default: backend = computer.backend
    }
    return computer.state.capitalized + " · " + backend + " · private browser"
  }

  private func attachMatchingBotComputer() {
    guard let profileID = RemoteBotProfile.resolvedID(selectedBotID) else { return }
    if let match = botComputers.first(where: {
      $0.profileID == profileID && canAttachBotComputer($0)
    }) {
      selectedBotComputerID = match.id
      sessionMode = .code
    }
  }

  private func prepareBotComputer(profileID: String?) {
    guard store.isConnected, botComputerBusyID == nil else { return }
    botComputerBusyID = UUID()
    Task {
      let computers = await store.prepareBotComputers(profileID: profileID)
      if !computers.isEmpty {
        botComputers = computers
        attachMatchingBotComputer()
      } else {
        await loadBotComputers()
      }
      botComputerBusyID = nil
    }
  }

  private func loadBotComputers() async {
    if let envelope = await store.botComputers() {
      botComputers = envelope.computers
      if let selected = selectedBotComputerID,
        !envelope.computers.contains(where: {
          $0.id == selected && ($0.state == "running" || $0.backend == "isolatedWorkspace")
        })
      {
        selectedBotComputerID = nil
      }
    }
  }

  private var apiKeySection: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("API key").font(.footnote.weight(.semibold)).foregroundStyle(
        BeetTheme.secondaryText(appearance))
      HStack(spacing: 8) {
        Picker("Provider", selection: $keyProviderID) {
          Text("OpenAI").tag("openAI")
          Text("Gemini").tag("gemini")
          Text("OpenRouter").tag("openRouter")
          Text("Anthropic").tag("anthropic")
          Text("DeepSeek").tag("deepSeek")
          Text("OpenCode Zen").tag("openCode")
          Text("OpenCode Go").tag("openCodeGo")
        }.pickerStyle(.menu)
        SecureField("Paste key", text: $keyDraft)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
        Button(isSavingKey ? "Saving…" : "Save") { saveAPIKey() }
          .disabled(!store.isConnected || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingKey)
      }
      if let keyMessage {
        Text(keyMessage).font(.caption).foregroundStyle(BeetTheme.secondaryText(appearance))
      }
      Text("Stored securely in the Mac Keychain; the key is never saved on this device or in chat.")
        .font(.caption2).foregroundStyle(BeetTheme.secondaryText(appearance))
    }
  }

  private func saveAPIKey() {
    guard store.isConnected, !isSavingKey,
      !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    isSavingKey = true
    let key = keyDraft
    let providerID = keyProviderID
    Task {
      let saved = await store.saveAPIKey(providerID: providerID, key: key)
      if saved {
        if keyDraft == key { keyDraft = "" }
        source = "api"
        await store.loadStartModels()
        selectFirstModel()
        let count = store.startModels.filter { $0.source == "api" }.count
        keyMessage =
          count == 0
          ? "Saved on Mac, but no models came back yet."
          : "Saved. Loaded \(count) API models."
      } else {
        keyMessage = "Could not save the key."
      }
      isSavingKey = false
    }
  }

  private func startBotComputer(_ computer: RemoteBotComputer) {
    guard store.isConnected, botComputerBusyID == nil else { return }
    botComputerBusyID = computer.id
    Task {
      if await store.startBotComputer(computer.id) {
        await loadBotComputers()
        selectedBotComputerID = computer.id
        sessionMode = .code
      }
      botComputerBusyID = nil
    }
  }

  private func stopBotComputer(_ computer: RemoteBotComputer) {
    guard store.isConnected, botComputerBusyID == nil else { return }
    botComputerBusyID = computer.id
    Task {
      if await store.stopBotComputer(computer.id) {
        await loadBotComputers()
        if selectedBotComputerID == computer.id { selectedBotComputerID = nil }
      }
      botComputerBusyID = nil
    }
  }
  private func start() {
    guard canStart else { return }
    isStarting = true
    let selectedModelID = selectedModelID
    let selectedBotID = selectedBotID
    let selectedBotComputerID = selectedBotComputerID
    let selectedWorkspacePath = selectedWorkspacePath
    let firstMessage = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedReasoningEffort = selectedReasoningEffort
    let autoMode = autoMode
    let fullAccess = fullAccess
    let sessionMode = sessionMode
    Task {
      if let id = await store.startSession(
        modelID: selectedModelID,
        message: firstMessage,
        botProfileID: RemoteBotProfile.resolvedID(selectedBotID),
        botComputerID: selectedBotComputerID,
        workspacePath: sessionMode == .code && selectedBotComputerID == nil
          ? selectedWorkspacePath : nil,
        chatOnly: sessionMode == .chat && selectedBotComputerID == nil,
        autoMode: autoMode,
        fullAccess: fullAccess,
        reasoningEffort: selectedReasoningEffort)
      {
        onStarted(id)
      }
      isStarting = false
    }
  }
}

/// Folder prompts live with whichever page shows the folder list, so the
/// alert is presented by the visible sheet.
struct RemoteWorkspaceAlerts: ViewModifier {
  @Binding var showNewFolder: Bool
  @Binding var newFolderName: String
  @Binding var showPathEntry: Bool
  @Binding var folderPathDraft: String
  let parent: String?
  let onCreate: () -> Void
  let onOpen: () -> Void

  func body(content: Content) -> some View {
    content
      .alert("New folder on Mac", isPresented: $showNewFolder) {
        TextField("Folder name", text: $newFolderName)
        Button("Cancel", role: .cancel) { newFolderName = "" }
        Button("Create", action: onCreate)
      } message: {
        Text(parent.map { "Created inside \($0)." } ?? "Created in the app’s Documents folder on your Mac.")
      }
      .alert("Open a folder path", isPresented: $showPathEntry) {
        TextField("~/Developer/my-app", text: $folderPathDraft)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Cancel", role: .cancel) { folderPathDraft = "" }
        Button("Open", action: onOpen)
      } message: {
        Text("The folder must already exist inside your Mac home directory.")
      }
  }
}
