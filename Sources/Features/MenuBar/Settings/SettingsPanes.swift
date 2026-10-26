import SwiftUI

/// One toolbar pane of the Settings window.
struct SettingsPane {
    let title: String
    let symbol: String
    let view: AnyView

    /// The narrowest a form pane gets. Every pane fills the window, which takes the largest pane's size.
    static let width: CGFloat = 480
    /// A pane taller than this scrolls, so the window fits a small display.
    static let maxHeight: CGFloat = 600

    @MainActor
    static func all(settings: SettingsModel, state: SettingsWindowState, actions: any SettingsActions) -> [SettingsPane] {
        [
            SettingsPane(title: "General", symbol: "gearshape", view: AnyView(GeneralPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Providers", symbol: "square.stack", view: AnyView(ProvidersPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Menu Bar", symbol: "menubar.rectangle", view: AnyView(MenuBarPane(settings: settings, state: state, actions: actions))),
            SettingsPane(title: "Usage Bars", symbol: "chart.bar.fill", view: AnyView(UsageBarsPane(settings: settings))),
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
            .frame(minWidth: SettingsPane.width, maxWidth: .infinity)
            .frame(maxHeight: SettingsPane.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}
