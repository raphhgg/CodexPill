import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $settings.refreshIntervalMinutes) {
                ForEach(settings.refreshIntervalOptions, id: \.self) { minutes in
                    Text("\(minutes) minutes").tag(minutes)
                }
            }

            Text("The app refreshes the active account on this schedule. Saved inactive accounts are refreshed when they become active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}
