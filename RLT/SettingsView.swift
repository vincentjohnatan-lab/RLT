// Setting view

import SwiftUI

struct SettingsView: View {
    let onClose: () -> Void
    @EnvironmentObject var sessionManager: SessionManager

    @State private var minimumPitText: String = ""
    @State private var newDriverName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    HStack {
                        Text("Minimum Pit time (s)")
                        Spacer()
                        TextField("10", text: $minimumPitText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
                Section("Drivers (session)") {
                    ForEach(sessionManager.drivers.indices, id: \.self) { index in
                        TextField("Driver's name", text: Binding(
                            get: { sessionManager.drivers[index] },
                            set: { sessionManager.drivers[index] = $0 }
                        ))
                    }
                    .onDelete(perform: sessionManager.removeDrivers)

                    HStack {
                        TextField("Add a driver", text: $newDriverName)
                        Button("Add") {
                            sessionManager.addDriver(newDriverName)
                            newDriverName = ""
                        }
                        .disabled(newDriverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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
            .onAppear {
                minimumPitText = String(Int(sessionManager.minimumPitSeconds))
            }
            .onChange(of: minimumPitText) {
                let filtered = minimumPitText.filter { $0.isNumber }
                if filtered != minimumPitText {
                    minimumPitText = filtered
                }
                sessionManager.minimumPitSeconds = TimeInterval(Int(filtered) ?? 0)
            }
        }
    }
}
