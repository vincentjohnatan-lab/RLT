// Setting view

import SwiftUI

struct SettingsView: View {
    let onClose: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("appearance_preference") private var appearanceRawValue = AppearancePreference.system.rawValue
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRawValue) {
                        ForEach([AppearancePreference.system, .light, .dark], id: \.rawValue) { pref in
                            Text(pref.title).tag(pref.rawValue)
                        }
                    }
                }

                Section("Settings (Home)") {
                    Text("Cette page sera utilisée plus tard pour les réglages généraux (Home).")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Label("Retour", systemImage: "chevron.left")
                    }
                }
            }
        }
    }
}
