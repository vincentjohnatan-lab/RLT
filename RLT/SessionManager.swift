//
//  SessionManager.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 29/12/2025.
//

import Foundation
import Combine
import SwiftUI

final class SessionManager: ObservableObject {

    // MARK: - Session state
    @Published var isSessionRunning: Bool = false
    @Published var sessionStartDate: Date?

    // MARK: - Live data (placeholders)
    @Published var currentLapTime: TimeInterval = 0
    @Published var lastLapTime: TimeInterval?
    @Published var bestLapTime: TimeInterval?
    @Published var deltaToBestLap: TimeInterval = 0


    // MARK: - Drivers (simple for now)
    @Published var drivers: [String] = ["Driver 1", "Driver 2"]
    @Published var selectedDriverName: String = "Driver 1"

    func selectDriver(_ name: String) {
        selectedDriverName = name
    }

    func addDriver(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        drivers.append(trimmed)
        if drivers.count == 1 {
            selectedDriverName = trimmed
        }
    }

    func removeDrivers(at offsets: IndexSet) {
        let removingSelected = offsets.contains(where: { drivers.indices.contains($0) && drivers[$0] == selectedDriverName })
        drivers.remove(atOffsets: offsets)

        if drivers.isEmpty {
            drivers = ["Driver 1"]
            selectedDriverName = drivers[0]
            return
        }

        if removingSelected {
            selectedDriverName = drivers[0]
        }
    }

    
    // MARK: - Pit
    @Published var isInPit: Bool = false
    @Published var pitStartDate: Date?
    @Published var pitElapsedSeconds: TimeInterval = 0

    // Minimum pit time for the session (Settings)
    @Published var minimumPitSeconds: TimeInterval = 10

    func togglePit() {
        if isInPit {
            // Stop pit -> reset to 0
            isInPit = false
            pitStartDate = nil
            pitElapsedSeconds = 0
        } else {
            // Start pit from 0
            isInPit = true
            pitStartDate = Date()
            pitElapsedSeconds = 0
        }
    }

    // MARK: - ApexTiming (placeholder)
    @Published var racePosition: Int?
    @Published var remainingRaceTime: TimeInterval?

    // MARK: - Control
    func startSession() {
        sessionStartDate = Date()
        isSessionRunning = true
    }

    func stopSession() {
        isSessionRunning = false
    }
    
    // MARK: - Lap flash (full-screen for 2s)
   
    enum LapFlashState {
        case normal
        case improvedPrevious
        case bestEver
    }

    struct LapFlash: Identifiable {
        let id = UUID()
        let lapTime: TimeInterval
        let state: LapFlashState
    }

    @Published var lapFlash: LapFlash?

    func completeLap(lapTime: TimeInterval) {
        let previousLast = lastLapTime
        let previousBest = bestLapTime

        // Détermine l'état (priorité: bestEver > improvedPrevious > normal)
        let isBestEver: Bool = (previousBest == nil) || (lapTime < (previousBest ?? .infinity))
        let isImprovedPrevious: Bool = (previousLast != nil) && (lapTime < (previousLast ?? .infinity))

        let state: LapFlashState
        if isBestEver {
            state = .bestEver
            bestLapTime = lapTime
        } else if isImprovedPrevious {
            state = .improvedPrevious
        } else {
            state = .normal
        }

        lastLapTime = lapTime

        // Déclenche l'overlay côté UI
        lapFlash = LapFlash(lapTime: lapTime, state: state)
    }

    // MARK: - Sectors UI (placeholder for layout)

    enum SectorDeltaState: String, CaseIterable {
        case neutral   // gris
        case slower    // jaune
        case faster    // vert
        case best      // violet
    }

    @Published var sectorCount: Int = 3 {
        didSet { normalizeSectorStates() }
    }

    @Published var sectorStates: [SectorDeltaState] = Array(repeating: .neutral, count: 3)

    private func normalizeSectorStates() {
        let clamped = max(1, min(sectorCount, 6)) // garde-fou simple
        if sectorStates.count == clamped { return }
        if sectorStates.count < clamped {
            sectorStates.append(contentsOf: Array(repeating: .neutral, count: clamped - sectorStates.count))
        } else {
            sectorStates = Array(sectorStates.prefix(clamped))
        }
    }

    // Optionnel: helper de test (à supprimer plus tard si tu veux)
    func setAllSectors(_ state: SectorDeltaState) {
        sectorStates = Array(repeating: state, count: max(1, min(sectorCount, 6)))
    }
}
