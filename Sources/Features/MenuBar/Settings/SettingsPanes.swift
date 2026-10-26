import SwiftUI

/// One toolbar pane of the Settings window.
struct SettingsPane {
    let title: String
    let symbol: String
    let view: AnyView

    static let width: CGFloat = 480
    /// A pane taller than this scrolls, so the window fits a small display.
    static let maxHeight: CGFloat = 600

    @MainActor
    static func all(settings: SettingsModel, state: SettingsWindowState, actions: any SettingsActions) -> [SettingsPane] {
        [
            SettingsPane(title: "General", symbol: "gearshape", view: AnyView(GeneralPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Accounts", symbol: "person.crop.circle", view: AnyView(AccountsPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Menu Bar", symbol: "menubar.rectangle", view: AnyView(MenuBarPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Usage Bars", symbol: "chart.bar.fill", view: AnyView(UsageBarsPane(settings: settings))),
            SettingsPane(title: "Tools", symbol: "square.stack", view: AnyView(ToolsPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Token Usage", symbol: "chart.xyaxis.line", view: AnyView(TokenUsagePane(settings: settings, actions: actions))),
        ]
    }
}

struct GeneralPane: View {
    @Bindable var settings: SettingsModel
    let state: SettingsWindowState
    let actions: any SettingsActions

    var body: some View {
        Form {
            Section {
                Picker("Refresh Every", selection: $settings.general.refreshIntervalMinutes) {
                    ForEach(GeneralSettings.refreshIntervalOptions, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                Toggle("Hide Emails", isOn: $settings.general.masksEmails)
            }
            Section {
                Picker("Theme", selection: $settings.general.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
            } footer: {
                Text("Sets the icon, usage bar and Token Usage colors.")
            }
            Section {
                Toggle("Launch at Login", isOn: launchAtLogin)
                    .disabled(state.isBusy || state.loginItemState == .unavailable)
                if state.loginItemState == .requiresApproval || state.loginItemState == .unavailable {
                    LabeledContent(state.loginItemState == .requiresApproval ? "Needs approval in System Settings" : "Unavailable for this copy of rusage") {
                        Button("Open Login Items…") { actions.openLoginItemsSettings() }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .settingsPane()
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { state.loginItemState == .enabled || state.loginItemState == .requiresApproval },
            set: { actions.setLaunchAtLogin($0) }
        )
    }
}

/// Each tool's account in the menu's order: the one it is signed in to, its sign-in and the actions the menu used to
/// offer. Every action runs through the coordinator, so its alerts still show.
struct AccountsPane: View {
    let settings: SettingsModel
    let state: SettingsWindowState
    let actions: any SettingsActions

    var body: some View {
        Form {
            ForEach(settings.general.toolOrder, id: \.self) { provider in
                Section(provider.copy.sectionTitle) {
                    if let section = state.toolSections.first(where: { $0.provider == provider }) {
                        rows(for: section)
                    } else {
                        LabeledContent(notShownLabel(provider)) {
                            Button(connectTitle(provider)) { actions.setTool(provider, shown: true) }
                                .disabled(provider == .codex && state.isBusy)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .settingsPane()
    }

    @ViewBuilder
    private func rows(for section: ToolSection) -> some View {
        let provider = section.provider
        if let label = section.activeLabel {
            LabeledContent(label) {
                Text(section.signInSourceLabel ?? "In use").foregroundStyle(.secondary)
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
                Button("Sign Out of Codex…") { actions.perform(.signOut, on: provider) }
                    .help("Signs the Codex app and CLI out on this Mac.")
            }
            .disabled(state.isBusy)
        } else if section.ownSignIn != .unsupported {
            ownSignInRow(for: section)
        }
    }

    /// rusage's own sign-in reads another account without touching the tool's own. Signing out of it goes back to the
    /// tool's sign-in; while that one is in use, the tool can only be disconnected.
    private func ownSignInRow(for section: ToolSection) -> some View {
        let provider = section.provider
        let name = provider.copy.sectionTitle
        return HStack {
            Button("Use Another Account…") { actions.perform(.signIn, on: provider) }
                .help("Signs in with rusage's own \(name) sign-in. \(provider.copy.name) keeps its own.")
            if section.ownSignIn == .signedIn {
                Button("Sign Out of \(name)") { actions.perform(.signOut, on: provider) }
            } else {
                Button("Disconnect") { actions.setTool(provider, shown: false) }
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
}

struct MenuBarPane: View {
    @Bindable var settings: SettingsModel
    let state: SettingsWindowState
    let actions: any SettingsActions

    var body: some View {
        Form {
            Section {
                Picker("Menu Bar Label", selection: displayMode) {
                    ForEach(StatusBarDisplayMode.allCases) { Text($0.menuTitle).tag($0) }
                }
                .disabled(!state.canShowMenuBarText)
                Picker("Icon Style", selection: $settings.menuBar.statusBarIndicatorStyle) {
                    ForEach(StatusBarIndicatorStyle.allCases) { Text($0.menuTitle).tag($0) }
                }
            } footer: {
                if !state.canShowMenuBarText {
                    Text("Text shows once the first tool has a reading.")
                }
            }
            Section {
                LabeledContent("Reveal Shortcut") {
                    HStack {
                        Text(settings.menuBar.revealStatusItemTitleShortcut.map { KeyboardShortcutPresentation(shortcut: $0).displayTitle } ?? "Off")
                            .foregroundStyle(.secondary)
                        Button("Change…") { actions.recordRevealShortcut() }
                            .disabled(state.isBusy)
                    }
                }
            } footer: {
                Text("Shows the menu bar text for a few seconds.")
            }
        }
        .settingsPane()
    }

    /// The label the menu bar shows now: icon only until the first tool has a reading.
    private var displayMode: Binding<StatusBarDisplayMode> {
        Binding(
            get: { state.canShowMenuBarText ? settings.menuBar.statusBarDisplayMode : .iconOnly },
            set: { settings.menuBar.statusBarDisplayMode = $0 }
        )
    }
}

struct UsageBarsPane: View {
    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Show", selection: $settings.menuBar.usagePercentMode) {
                    Text("% Used").tag(UsagePercentMode.used)
                    Text("% Left").tag(UsagePercentMode.left)
                }
                .pickerStyle(.segmented)
                Picker("Layout", selection: $settings.menuBar.usageMeterLayout) {
                    Text("Classic").tag(UsageMeterLayout.classic)
                    Text("Compact").tag(UsageMeterLayout.compact)
                }
                .pickerStyle(.segmented)
                Toggle("Pace Markers", isOn: $settings.menuBar.pacingMarkersEnabled)
            }
            Section {
                ColorPicker("Session Color", selection: sessionColor, supportsOpacity: false)
                ColorPicker("Weekly Color", selection: weeklyColor, supportsOpacity: false)
                    .disabled(settings.menuBar.usesOneUsageColor)
                Toggle("Same Color for Both", isOn: $settings.menuBar.usesOneUsageColor)
                Button("Use Theme Colors") { settings.menuBar.resetUsageColors() }
                    .disabled(!settings.menuBar.hasCustomUsageColors)
            } footer: {
                Text("Custom colors replace the theme's on every tool card.")
            }
        }
        .settingsPane()
    }

    private var palette: ThemePalette { ThemePalette(theme: settings.general.theme) }

    /// A color equal to the theme's is stored as no custom color, so the bar keeps following the theme.
    private var sessionColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.menuBar.sessionAccentColor?.nsColor ?? palette.sessionColor(for: .codex)) },
            set: { color in
                let nsColor = NSColor(color).withAlphaComponent(1)
                settings.menuBar.sessionAccentColor = nsColor.isEqualToStatusItemAccentColor(palette.sessionColor(for: .codex))
                    ? nil
                    : StatusItemAccentColor(nsColor: nsColor)
            }
        )
    }

    private var weeklyColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.menuBar.effectiveWeeklyAccentColor?.nsColor ?? palette.weeklyColor(for: .codex)) },
            set: { color in
                settings.menuBar.weeklyAccentColor = StatusItemAccentColor(nsColor: NSColor(color).withAlphaComponent(1))
            }
        )
    }
}

/// Every tool in the menu's order, which drag or Move Up and Move Down change, each with a switch that connects or
/// disconnects it.
struct ToolsPane: View {
    @Bindable var settings: SettingsModel
    let state: SettingsWindowState
    let actions: any SettingsActions
    @State private var selection: UsageProvider?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(settings.general.toolOrder, id: \.self) { provider in
                        row(provider)
                    }
                    .onMove { settings.general.toolOrder.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Drag to reorder. The first tool shown drives the menu bar icon.")
                }
                if state.shownTools.contains(.claude) {
                    Section {
                        HStack {
                            Text("Claude Model Limits")
                            Spacer()
                            Toggle("Claude Model Limits", isOn: showsModelLimits)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .help("Weekly limits per model, such as Fable.")
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button("Move Up", systemImage: "chevron.up") { move(by: -1) }
                    .disabled(!canMove(by: -1))
                Button("Move Down", systemImage: "chevron.down") { move(by: 1) }
                    .disabled(!canMove(by: 1))
                Spacer()
            }
            .labelStyle(.titleAndIcon)
            .padding(8)
        }
        .frame(width: SettingsPane.width, height: 300)
    }

    private func row(_ provider: UsageProvider) -> some View {
        let name = provider.copy.sectionTitle
        let isShown = state.shownTools.contains(provider)
        return HStack {
            Text(name)
            Spacer()
            Toggle(name, isOn: Binding(get: { isShown }, set: { actions.setTool(provider, shown: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(provider == .codex && !isShown && state.isBusy)
        }
        .tag(provider)
        .accessibilityElement(children: .contain)
    }

    private var showsModelLimits: Binding<Bool> {
        Binding(get: { state.showsModelLimits }, set: { actions.setShowsModelLimits($0) })
    }

    private func canMove(by offset: Int) -> Bool {
        guard let selection, let index = settings.general.toolOrder.firstIndex(of: selection) else { return false }
        return settings.general.toolOrder.indices.contains(index + offset)
    }

    private func move(by offset: Int) {
        guard let selection, let index = settings.general.toolOrder.firstIndex(of: selection),
              settings.general.toolOrder.indices.contains(index + offset) else { return }
        settings.general.toolOrder.swapAt(index, index + offset)
    }
}

struct TokenUsagePane: View {
    @Bindable var settings: SettingsModel
    let actions: any SettingsActions

    var body: some View {
        Form {
            Section {
                Picker("Show", selection: Binding(get: { settings.tokenUsage.display }, set: { actions.setTokenUsageDisplay($0) })) {
                    Text("Graph, breakdown on hover").tag(TokenUsageDisplay.graphWithBreakdownOnHover)
                    Text("Graph and breakdown").tag(TokenUsageDisplay.graphAndBreakdown)
                    Text("Hidden").tag(TokenUsageDisplay.hidden)
                }
            } footer: {
                Text("Tokens your tools used over the last 30 days.")
            }
            Section {
                Picker("Chart", selection: $settings.tokenUsage.chartStyle) {
                    ForEach(TokenUsageChartStyle.allCases, id: \.self) { Text($0.accessibilityName).tag($0) }
                }
                Picker("Breakdown", selection: $settings.tokenUsage.breakdown) {
                    ForEach(TokenUsageBreakdown.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .disabled(!settings.tokenUsage.isEnabled)
        }
        .settingsPane()
    }
}

extension View {
    /// A grouped form as tall as its rows up to `SettingsPane.maxHeight`, so the window takes each pane's size.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: SettingsPane.width)
            .frame(maxHeight: SettingsPane.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}
