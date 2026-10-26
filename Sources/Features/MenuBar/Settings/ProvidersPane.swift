import SwiftUI

/// The providers added to rusage on the left, in the menu's order, which drag or Move Up and Move Down change, with +
/// and − under them as in Mail's accounts. The selected one's switch, account and options are on the right. Every
/// action runs through the coordinator, so its alerts still show.
struct ProvidersPane: View {
    @Bindable var settings: SettingsModel
    @Bindable var state: SettingsWindowState
    let actions: any SettingsActions

    static let sidebarWidth: CGFloat = 200
    static let detailWidth: CGFloat = 380

    /// Every provider's detail is laid out and only the selected one shows, so the pane is as tall as the longest one
    /// and choosing another provider never resizes the window.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            Divider()
            ZStack(alignment: .top) {
                ForEach(settings.general.toolOrder, id: \.self) { provider in
                    let isSelected = provider == selection
                    detail(for: provider)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                }
                if selection == nil {
                    Text("Add a provider with +")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: Self.detailWidth)
        }
        .frame(minWidth: Self.sidebarWidth + 1 + Self.detailWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Claude and Cursor while connected, Codex until it is removed, in the menu's order.
    private var addedProviders: [UsageProvider] {
        settings.general.toolOrder.filter { provider in
            provider == .codex ? settings.codex.isConnected : state.shownTools.contains(provider)
        }
    }

    private var notAddedProviders: [UsageProvider] {
        settings.general.toolOrder.filter { !addedProviders.contains($0) }
    }

    /// The provider chosen last, kept while rusage runs, else the first one added.
    private var selection: UsageProvider? {
        state.selectedProvider.flatMap { addedProviders.contains($0) ? $0 : nil } ?? addedProviders.first
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { selection }, set: { state.selectedProvider = $0 })) {
                ForEach(addedProviders, id: \.self) { provider in
                    row(provider)
                }
                .onMove(perform: moveAdded)
            }
            .listStyle(.sidebar)
            .help("Drag to set the menu order. The first one shown drives the menu bar icon.")
            .accessibilityHint("Drag to set the menu order. The first one shown drives the menu bar icon.")
            Divider()
            addRemoveBar
        }
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
    }

    /// The standard + and − under a source list.
    private var addRemoveBar: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(notAddedProviders, id: \.self) { provider in
                    Button(provider.copy.sectionTitle) {
                        state.selectedProvider = provider
                        actions.setTool(provider, shown: true)
                    }
                }
            } label: {
                Label("Add Provider", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(notAddedProviders.isEmpty || state.isBusy)
            .help("Add Provider")
            Divider().frame(height: 14)
            Button {
                if let selection { actions.removeProvider(selection) }
            } label: {
                Label("Remove Provider", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || state.isBusy)
            .help("Remove Provider")
            Spacer()
        }
        .frame(height: 22)
        .padding(.horizontal, 4)
    }

    /// Moves within the added providers keep the others where they are in the menu's order.
    private func moveAdded(from source: IndexSet, to destination: Int) {
        var added = addedProviders
        added.move(fromOffsets: source, toOffset: destination)
        var remaining = added.makeIterator()
        settings.general.toolOrder = settings.general.toolOrder.map { addedProviders.contains($0) ? remaining.next()! : $0 }
    }

    private func row(_ provider: UsageProvider) -> some View {
        let isShown = state.shownTools.contains(provider)
        let canMoveUp = canMove(provider, by: -1)
        let canMoveDown = canMove(provider, by: 1)
        return HStack(spacing: 8) {
            Image(provider.markAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.copy.sectionTitle)
                Text(subtitle(provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .opacity(isShown ? 1 : 0.5)
        .tag(provider)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if canMoveUp { Button("Move Up") { move(provider, by: -1) } }
            if canMoveDown { Button("Move Down") { move(provider, by: 1) } }
        }
        .contextMenu {
            Button("Move Up") { move(provider, by: -1) }.disabled(!canMoveUp)
            Button("Move Down") { move(provider, by: 1) }.disabled(!canMoveDown)
        }
    }

    private func subtitle(_ provider: UsageProvider) -> String {
        guard let section = section(provider) else {
            return provider == .codex && !state.isSignedInToCodex ? "Signed out" : "Hidden from the menu"
        }
        return section.activeLabel ?? section.card.title ?? ""
    }

    private func section(_ provider: UsageProvider) -> ToolSection? {
        state.toolSections.first { $0.provider == provider }
    }

    @ViewBuilder
    private func detail(for provider: UsageProvider) -> some View {
        Form {
            Section {
                Toggle("Show in Menu Bar", isOn: Binding(
                    get: { state.shownTools.contains(provider) },
                    set: { actions.setTool(provider, shown: $0) }
                ))
                .disabled(provider == .codex && state.isBusy)
            }
            Section("Account") {
                if let section = section(provider) {
                    accountRows(for: section)
                } else {
                    LabeledContent(notShownLabel(provider)) {
                        Button(connectTitle(provider)) { actions.setTool(provider, shown: true) }
                            .disabled(provider == .codex && state.isBusy)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if provider == .claude {
                Section("Options") {
                    Toggle(isOn: Binding(get: { state.showsModelLimits }, set: { actions.setShowsModelLimits($0) })) {
                        Text("Model Limits")
                        Text("Weekly limits per model, such as Fable, on the card.")
                    }
                    .disabled(section(provider) == nil)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func accountRows(for section: ToolSection) -> some View {
        let provider = section.provider
        if let label = section.activeLabel {
            LabeledContent {
                Text("Signed in").foregroundStyle(.secondary)
            } label: {
                Text(label)
                if let caption = section.signInSourceCaption {
                    Text(caption)
                }
            }
        } else {
            Text(section.card.title ?? "No account in use").foregroundStyle(.secondary)
        }
        if let followUp = section.followUp, followUp.action != .signIn {
            Button(followUp.title) { actions.perform(followUp.action, on: provider) }
        }
        if provider == .codex {
            HStack {
                Button("Use Another Account…") { actions.perform(.addAccount, on: provider) }
                    .help("Replaces the Codex sign-in on this Mac.")
                Button("Sign Out…") { actions.perform(.signOut, on: provider) }
                    .help("Signs the Codex app and CLI out on this Mac.")
            }
            .disabled(state.isBusy)
        } else if section.ownSignIn != .unsupported {
            HStack {
                Button("Use Another Account…") { actions.perform(.signIn, on: provider) }
                    .help("Signs in with rusage's own \(provider.copy.sectionTitle) sign-in. \(provider.copy.name) keeps its own.")
                // While the tool's own sign-in is in use, rusage can't sign it out, only stop reading it.
                if section.ownSignIn == .signedIn {
                    Button("Sign Out…") { actions.perform(.signOut, on: provider) }
                } else {
                    Button("Disconnect") { actions.setTool(provider, shown: false) }
                }
            }
        }
    }

    private func notShownLabel(_ provider: UsageProvider) -> String {
        provider == .codex && !state.isSignedInToCodex ? "Signed out" : "Not shown in the menu"
    }

    /// Codex signed out signs in first. Claude and Cursor ask for consent first.
    private func connectTitle(_ provider: UsageProvider) -> String {
        guard provider == .codex else { return "Connect…" }
        return state.isSignedInToCodex ? "Show" : "Sign In…"
    }

    private func canMove(_ provider: UsageProvider, by offset: Int) -> Bool {
        guard let index = addedProviders.firstIndex(of: provider) else { return false }
        return addedProviders.indices.contains(index + offset)
    }

    private func move(_ provider: UsageProvider, by offset: Int) {
        guard canMove(provider, by: offset), let index = addedProviders.firstIndex(of: provider) else { return }
        moveAdded(from: IndexSet(integer: index), to: offset > 0 ? index + offset + 1 : index + offset)
    }
}
