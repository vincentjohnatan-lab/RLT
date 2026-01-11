//
//  TrackStore.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 10/01/2026.
//

import SwiftUI
import Combine

@MainActor
final class TrackStore: ObservableObject {
    @Published private(set) var tracks: [TrackDefinition] = []

    private let fileName = "tracks.json"

    init() {
        load()
        if tracks.isEmpty {
            // Valeur par défaut (évite une app vide au 1er lancement)
            tracks = [
                TrackDefinition(name: "Unknown Track", direction: .clockwise)
            ]
            save()
        }
    }
    
    func addTrack(_ track: TrackDefinition) {
        let trimmed = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tracks.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        var t = track
        t.name = trimmed
        tracks.append(t)
        tracks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }


    func delete(at offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        save()
    }

    func track(named name: String) -> TrackDefinition? {
        tracks.first(where: { $0.name == name })
    }
    
    func updateTrack(_ track: TrackDefinition) {
        guard let idx = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[idx] = track
        tracks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    // MARK: - Persistence

    private func fileURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }

    private func load() {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return }
        guard let decoded = try? JSONDecoder().decode([TrackDefinition].self, from: data) else { return }
        self.tracks = decoded
    }

    private func save() {
        let url = fileURL()
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
