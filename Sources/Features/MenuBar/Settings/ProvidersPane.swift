import SwiftUI

/// Every provider in the menu's order on the left, which drag or Move Up and Move Down change, and the selected one's
/// switch, account and options on the right. Every action runs through the coordinator, so its alerts still show.
struct ProvidersPane: View {
    @Bindable var settings: SettingsModel
    @Bindable var state: SettingsWindowState
    let actions: any SettingsActions

    static let size = CGSize(width: 680, height: 420)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail(for: selection)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// The provider chosen last, kept while rusage runs, else the first in the menu's order.
    private var selection: UsageProvider {
        state.selectedProvider ?? settings.general.toolOrder.first ?? .claude
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { selection }, set: { state.selectedProvider = $0 })) {
                ForEach(settings.general.toolOrder, id: \.self) { provider in
                    row(provider)
                }
                .onMove { settings.general.toolOrder.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)
            Text("Drag to set the menu order. The first one shown drives the menu bar icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .frame(width: 210)
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
        guard let section = section(provider) else { return "Hidden from the menu" }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func accountRows(for section: ToolSection) -> some View {
        let provider = section.provider
        if let label = section.activeLabel {
            LabeledContent(label) {
                Text(source(of: section)).foregroundStyle(.secondary)
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

    private func source(of section: ToolSection) -> String {
        if section.ownSignIn == .signedIn { return "Signed in with rusage" }
        return section.signInSourceLabel ?? "In use"
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
        guard let index = settings.general.toolOrder.firstIndex(of: provider) else { return false }
        return settings.general.toolOrder.indices.contains(index + offset)
    }

    private func move(_ provider: UsageProvider, by offset: Int) {
        guard canMove(provider, by: offset), let index = settings.general.toolOrder.firstIndex(of: provider) else { return }
        settings.general.toolOrder.swapAt(index, index + offset)
    }
}
