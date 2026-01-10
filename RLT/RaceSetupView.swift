//
//  RaceSetupView.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 02/01/2026.
//

import SwiftUI

struct RaceSetupView: View {
    let initialMinimumPitSeconds: TimeInterval
    let initialDrivers: [String]
    let onValidate: (SessionManager.RaceConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var trackName: String = "Unknown Track"
    @State private var minimumPitSeconds: Double = 10

    @State private var driverCount: Int = 2
    @State private var driverNames: [String] = ["Driver 1", "Driver 2"]

    // Liste simple (placeholder). On la branchera plus tard sur une vraie liste Track.
    private let tracks: [String] = [
        "Unknown Track",
        "Le Mans",
        "Karting (Generic)",
        "Circuit 1",
        "Circuit 2"
    ]

    init(
        initialMinimumPitSeconds: TimeInterval,
        initialDrivers: [String],
        onValidate: @escaping (SessionManager.RaceConfig) -> Void
    ) {
        self.initialMinimumPitSeconds = initialMinimumPitSeconds
        self.initialDrivers = initialDrivers
        self.onValidate = onValidate

        _minimumPitSeconds = State(initialValue: Double(initialMinimumPitSeconds))

        let safeDrivers = initialDrivers.isEmpty ? ["Driver 1", "Driver 2"] : initialDrivers
        let initialCount = max(1, min(6, safeDrivers.count))
        _driverCount = State(initialValue: initialCount)

        var names = Array(safeDrivers.prefix(6))
        if names.count < 2 { names.append("Driver 2") }
        names = Array(names.prefix(6))

        _driverNames = State(initialValue: names)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Race") {
                    Picker("Track", selection: $trackName) {
                        ForEach(tracks, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }

                    Stepper(value: $minimumPitSeconds, in: 0...600, step: 10) {
                        HStack {
                            Text("Minimum pit (sec)")
                            Spacer()
                            Text("\(Int(minimumPitSeconds))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Drivers") {
                    Stepper(value: $driverCount, in: 1...6, step: 1) {
                        HStack {
                            Text("Number of drivers")
                            Spacer()
                            Text("\(driverCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: driverCount) { _, newValue in
                        normalizeDriverNames(count: newValue)
                    }

                    ForEach(0..<driverCount, id: \.self) { idx in
                        TextField("Driver \(idx + 1) name", text: Binding(
                            get: { driverNames[safeIndex: idx] ?? "" },
                            set: { newValue in
                                if idx < driverNames.count { driverNames[idx] = newValue }
                            }
                        ))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle("Start Race")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Launch") {
                        let cleaned = driverNames
                            .prefix(driverCount)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .enumerated()
                            .map { (i, name) in name.isEmpty ? "Driver \(i + 1)" : name }

                        let config = SessionManager.RaceConfig(
                            trackName: trackName,
                            minimumPitSeconds: minimumPitSeconds,
                            driverNames: cleaned
                        )
                        onValidate(config)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func normalizeDriverNames(count: Int) {
        let clamped = max(1, min(6, count))
        if driverNames.count < clamped {
            for i in driverNames.count..<clamped {
                driverNames.append("Driver \(i + 1)")
            }
        } else if driverNames.count > clamped {
            driverNames = Array(driverNames.prefix(clamped))
        }
    }
}

// Petit helper safeIndex (local, pas de dépendances)
private extension Array {
    subscript(safeIndex index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

#Preview {
    RaceSetupView(initialMinimumPitSeconds: 10, initialDrivers: ["Driver 1", "Driver 2"]) { _ in }
        .environmentObject(SessionManager())
}
