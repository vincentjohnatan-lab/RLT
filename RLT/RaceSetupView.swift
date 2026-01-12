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
    @EnvironmentObject private var trackStore: TrackStore


    @State private var selectedTrackID: UUID? = nil
    @State private var minimumPitSeconds: Double = 10

    @State private var driverCount: Int = 2
    @State private var driverNames: [String] = ["Driver 1", "Driver 2"]

    // Liste simple (placeholder). On la branchera plus tard sur une vraie liste Track.
    private var availableTrackNames: [String] {
        let names = trackStore.tracks.map { $0.name }
        return names.isEmpty ? ["Unknown Track"] : names
    }

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

    private var availableTracks: [TrackDefinition] {
        trackStore.tracks.sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Race") {
                    Picker("Track", selection: $selectedTrackID) {

                        // ✅ Tag explicite pour la valeur nil (supprime le warning)
                        Text("Select a track").tag(UUID?.none)

                        ForEach(availableTracks) { track in
                            Text(track.name).tag(Optional(track.id))
                        }
                    }
                    .onAppear {
                        // Init une fois pour éviter un Picker sans sélection
                        if selectedTrackID == nil {
                            selectedTrackID = availableTracks.first?.id
                        }
                    }
                    .onChange(of: availableTracks.count) { _, _ in
                        if selectedTrackID == nil {
                            selectedTrackID = availableTracks.first?.id
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
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }

                        // 1) Récupère le TrackDefinition choisi
                        guard
                            let id = selectedTrackID,
                            let track = availableTracks.first(where: { $0.id == id })
                        else {
                            return
                        }

                        // 2) Construit la config robuste (avec snapshot du track)
                        let config = SessionManager.RaceConfig(
                            track: track,
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
        .environmentObject(TrackStore())
}
