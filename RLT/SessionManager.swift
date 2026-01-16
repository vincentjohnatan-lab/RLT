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

    private let minLapDurationSeconds: TimeInterval = 20
    
    // MARK: - Auth Errors
    enum AuthError: LocalizedError {
        case emptyEmail
        case invalidEmail
        case emptyPassword
        case passwordTooShort(min: Int)
        case passwordMismatch
        case demoFailure

        var errorDescription: String? {
            switch self {
            case .emptyEmail:
                return "Veuillez saisir un email."
            case .invalidEmail:
                return "Veuillez saisir un email valide."
            case .emptyPassword:
                return "Veuillez saisir un mot de passe."
            case .passwordTooShort(let min):
                return "Le mot de passe doit contenir au moins \(min) caractères."
            case .passwordMismatch:
                return "Les mots de passe ne correspondent pas."
            case .demoFailure:
                return "Opération impossible (mode démo)."
            }
        }
    }

    // MARK: - LiveView right-middle tile mode
    enum RightMiddleTileMode: String, CaseIterable, Identifiable {
        case liveTiming
        case sectorTimes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveTiming:  return "Live Timing"
            case .sectorTimes: return "Sector Times"
            }
        }
    }

    // MARK: - Auth (persisted)
    @AppStorage("isLoggedIn") private var storedIsLoggedIn: Bool = false
    @Published var isLoggedIn: Bool = false
    @AppStorage("userNickname") private var storedUserNickname: String = ""
    @Published var userNickname: String = ""

    init() {
        self.isLoggedIn = storedIsLoggedIn
        self.rightMiddleTileMode = RightMiddleTileMode(rawValue: storedRightMiddleTileMode) ?? .sectorTimes
        self.userNickname = storedUserNickname

        if self.isLoggedIn {
            applyNicknameAsDriver1()
        }
    }

    // MARK: - Session state
    @Published var isSessionRunning: Bool = false
    @Published var sessionStartDate: Date?
    
    // MARK: - Demo mode
    @Published var isDemoMode: Bool = false
    @Published var demoSpeedKmh: Double = 0
    private var demoTicker: AnyCancellable?
    private var demoTargetLap: TimeInterval = 45.0
    private var demoStartTime: Date?

    // MARK: - Live data
    @Published var currentLapTime: TimeInterval = 0
    @Published var lastLapTime: TimeInterval?
    @Published var bestLapTime: TimeInterval?
    @Published var deltaToBestLap: TimeInterval = 0
    @Published var isDeltaReady: Bool = false
    private var lapTicker: AnyCancellable?
    
    // MARK: - Sector live timing (UI)
    @Published var liveSectorIndex: Int = 0                 // 0=S1, 1=S2, 2=S3...
    @Published var liveSectorElapsed: TimeInterval = 0      // chrono du secteur en cours
    @Published var currentLapSectorTimesUI: [TimeInterval] = [] // temps validés sur le tour en cours

    // MARK: - Drivers
    @Published var drivers: [String] = ["Driver 1", "Driver 2"]
    @Published var selectedDriverName: String = "Driver 1"
    
    //MARK:Sectors in layout
    @AppStorage("right_middle_tile_mode")
    private var storedRightMiddleTileMode: String = RightMiddleTileMode.sectorTimes.rawValue

    @Published var rightMiddleTileMode: RightMiddleTileMode = .sectorTimes {
        didSet { storedRightMiddleTileMode = rightMiddleTileMode.rawValue }
    }

    func selectDriver(_ name: String) {
        guard name != selectedDriverName else { return }

        if isSessionRunning {
            endCurrentStint()
            selectedDriverName = name
            beginStint(for: name)
        } else {
            selectedDriverName = name
        }
    }

    func addDriver(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        drivers.append(trimmed)
        if drivers.count == 1 { selectedDriverName = trimmed }
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

    private func applyNicknameAsDriver1() {
        let nick = userNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nick.isEmpty else { return }

        if drivers.isEmpty {
            drivers = [nick]
            selectedDriverName = nick
            return
        }

        drivers[0] = nick
        if selectedDriverName == "Driver 1" || selectedDriverName.isEmpty {
            selectedDriverName = nick
        }
    }

    // MARK: - Race Config / Start Gate
    struct RaceConfig: Equatable {
        var track: TrackDefinition
        var minimumPitSeconds: TimeInterval
        // NEW: garde-fou anti-lap trop court (glitch SF / démarrage / GPS)
        var driverNames: [String]
        var createdAt: Date = Date()
        var trackName: String { track.name }
    }

    @Published var raceConfig: RaceConfig?
    @Published var isRaceStartArmed: Bool = false
    @Published var lapCount: Int = 0
    @Published var driverStints: [String: Int] = [:]

    // MARK: - GPS ingestion
    private var lastGPSLat: Double? = nil
    private var lastGPSLon: Double? = nil
    private var lastStartFinishCrossDate: Date? = nil
    // le 1er passage SF après START sert à initialiser le chrono, pas à compter un tour
    private var awaitingFirstStartFinishCross: Bool = true
    
    // MARK: - Sectors (MVP)
    private var currentSectorIndex: Int = 0
    private var sectorStartDate: Date? = nil
    private var currentLapSectorTimes: [TimeInterval] = []
    private var lastLapSectorTimes: [TimeInterval] = []
    private var bestSectorTimes: [TimeInterval] = []
    private var lastSectorCrossDates: [Date?] = []

    // MARK: - Pilot delta (MVP)
    private struct LapSample {
        let s: Double
        let t: TimeInterval
    }

    private var lastGPSTimestamp: Date? = nil
    private var currentLapDistance: Double = 0.0
    private var currentLapSamples: [LapSample] = []
    private var referenceLapSamples: [LapSample] = []
    private var referenceLapTotalDistance: Double = 0.0
    
    // MARK: - Delta smoothing (EMA)
    private var smoothedDeltaToBest: TimeInterval = 0
    private let deltaEmaAlpha: Double = 0.18  // 0.12 = très lisse, 0.25 = plus réactif


    // MARK: - Stints (stats)
    struct StintRecord: Identifiable {
        let id = UUID()
        let driverName: String
        let stintNumber: Int
        let startedAt: Date
        let endedAt: Date
        var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    }

    @Published private(set) var completedStints: [StintRecord] = []
    @Published private(set) var currentStintDriverName: String?
    @Published private(set) var currentStintNumber: Int = 0
    @Published private(set) var currentStintStartDate: Date?

    var currentStintElapsed: TimeInterval {
        guard isSessionRunning, let start = currentStintStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }
   
    /// Temps total équipe = somme des stints terminés + stint en cours (si session active)
    var teamTotalStintTime: TimeInterval {
        let done = completedStints.reduce(0) { $0 + $1.duration }
        let current = (isSessionRunning ? currentStintElapsed : 0)
        return done + current
    }

    /// Optimal lap = somme des meilleurs secteurs (pilote)
    var optimalLapTime: TimeInterval? {
        guard !bestSectorTimes.isEmpty else { return nil }

        let valid = bestSectorTimes.filter { $0.isFinite && $0 > 0 }
        guard valid.count == bestSectorTimes.count else { return nil }

        return valid.reduce(0, +)
    }

    private func beginStint(for driver: String, at date: Date = Date()) {
        currentStintDriverName = driver
        currentStintStartDate = date

        let nextNumber = (driverStints[driver] ?? 0) + 1
        driverStints[driver] = nextNumber
        currentStintNumber = nextNumber
    }

    private func endCurrentStint(at date: Date = Date()) {
        guard let driver = currentStintDriverName,
              let start = currentStintStartDate,
              currentStintNumber > 0 else { return }

        completedStints.append(
            StintRecord(
                driverName: driver,
                stintNumber: currentStintNumber,
                startedAt: start,
                endedAt: date
            )
        )

        currentStintDriverName = nil
        currentStintStartDate = nil
        currentStintNumber = 0
    }

    // MARK: - Race lifecycle
    func armRaceStart(with config: RaceConfig) {
        raceConfig = config

        // Configure sectorCount from track
        let sectorLines = availableSectorLines(from: config.track)
        // secteurs = (nb de lignes secteurs) + 1 (le dernier secteur jusqu’à SF)
        sectorCount = max(1, sectorLines.count + 1)
        
        // Apply config
        minimumPitSeconds = config.minimumPitSeconds
        drivers = config.driverNames.isEmpty ? ["Driver 1"] : config.driverNames
        selectedDriverName = drivers.first ?? "Driver 1"
        applyNicknameAsDriver1()
        driverStints = Dictionary(uniqueKeysWithValues: drivers.map { ($0, 0) })

        resetRaceData()

        isRaceStartArmed = true
        stopSession()
    }

    func startArmedRace() {
        guard isRaceStartArmed else { return }
        isRaceStartArmed = false
        startSession()
    }

    // MARK: - GPS ingest
    
    func ingestGPS(lat: Double, lon: Double, speedKmh: Double?, timestamp: Date) {
        defer {
            lastGPSLat = lat
            lastGPSLon = lon
            lastGPSTimestamp = timestamp
        }

        guard isSessionRunning else { return }
        guard let prevLat = lastGPSLat, let prevLon = lastGPSLon else { return }
        if let s = speedKmh, s < 3 { return }

        // --- Pilot delta: distance cumulée + samples ---
        let d = haversineMeters(lat1: prevLat, lon1: prevLon, lat2: lat, lon2: lon)
        if d < 50 {
            currentLapDistance += d
        }

        if let start = sessionStartDate {
            let t = max(0, timestamp.timeIntervalSince(start))
            currentLapSamples.append(LapSample(s: currentLapDistance, t: t))

            // Delta : seulement quand une lap de référence existe vraiment
            if isDeltaReady, let refT = refTime(atDistance: currentLapDistance) {
                let raw = t - refT
                smoothedDeltaToBest = smoothedDeltaToBest + deltaEmaAlpha * (raw - smoothedDeltaToBest)
                deltaToBestLap = smoothedDeltaToBest
            } else {
                // Tant qu'on n'est pas "ready", on force un delta neutre (affichage stable)
                smoothedDeltaToBest = 0
                deltaToBestLap = 0
            }
        }

        guard let track = raceConfig?.track else { return }

        // --- Start/Finish ---
        if let sf = trackLine(track.startFinish) {
            if let last = lastStartFinishCrossDate, timestamp.timeIntervalSince(last) < 2.0 {
                // do nothing
            } else if segmentsIntersect(
                a1: (prevLat, prevLon),
                a2: (lat, lon),
                b1: sf.a,
                b2: sf.b
            ) {
                lastStartFinishCrossDate = timestamp
                registerLapCrossing(at: timestamp)
            }
        }

        // --- Sectors (ordre imposé) ---
        let sectorLines = availableSectorLines(from: track)
        guard !sectorLines.isEmpty else { return }

        if sectorStartDate == nil {
            sectorStartDate = timestamp
        }
        
        // UI: chrono du secteur en cours + secteurs déjà validés
        liveSectorIndex = currentSectorIndex
        if let start = sectorStartDate {
            liveSectorElapsed = max(0, timestamp.timeIntervalSince(start))
        } else {
            liveSectorElapsed = 0
        }
        currentLapSectorTimesUI = currentLapSectorTimes

        let sectorsCount = max(1, sectorLines.count + 1)

        // Debounce uniquement sur les lignes secteurs (sans SF)
        if lastSectorCrossDates.count != sectorLines.count {
            lastSectorCrossDates = Array(repeating: nil, count: sectorLines.count)
        }

        // Best/States sur le nombre de secteurs (incluant le dernier jusqu’à SF)
        if bestSectorTimes.count != sectorsCount {
            bestSectorTimes = Array(repeating: .infinity, count: sectorsCount)
        }
        if sectorStates.count != max(1, min(sectorsCount, 6)) {
            sectorStates = Array(repeating: .neutral, count: max(1, min(sectorsCount, 6)))
        }

        // Si on est déjà dans le dernier secteur (après la dernière ligne), il n’y a plus de ligne à croiser.
        // Le dernier secteur sera validé au passage SF (registerLapCrossing).
        guard currentSectorIndex < sectorLines.count else { return }

        guard let seg = trackLine(sectorLines[currentSectorIndex]) else { return }

        // Debounce dynamique (anti double-cross) basé sur la vitesse
        let v = max(0, speedKmh ?? 0) // km/h (peut être nil)
        let debounceSeconds: TimeInterval
        if v < 20 {
            debounceSeconds = 2.2
        } else if v < 50 {
            debounceSeconds = 1.6
        } else if v < 90 {
            debounceSeconds = 1.1
        } else {
            debounceSeconds = 0.8
        }

        if let last = lastSectorCrossDates[currentSectorIndex],
           timestamp.timeIntervalSince(last) < debounceSeconds {
            return
        }

        if segmentsIntersect(
            a1: (prevLat, prevLon),
            a2: (lat, lon),
            b1: seg.a,
            b2: seg.b
        ) {
            lastSectorCrossDates[currentSectorIndex] = timestamp

            let start = sectorStartDate ?? timestamp
            let sectorTime = max(0, timestamp.timeIntervalSince(start))

            if currentLapSectorTimes.count == currentSectorIndex {
                currentLapSectorTimes.append(sectorTime)
            } else if currentLapSectorTimes.count > currentSectorIndex {
                currentLapSectorTimes[currentSectorIndex] = sectorTime
            } else {
                while currentLapSectorTimes.count < currentSectorIndex { currentLapSectorTimes.append(0) }
                currentLapSectorTimes.append(sectorTime)
            }

            let prevTime: TimeInterval? = (lastLapSectorTimes.count > currentSectorIndex) ? lastLapSectorTimes[currentSectorIndex] : nil
            let bestTime: TimeInterval = bestSectorTimes[currentSectorIndex]

            let state: SectorDeltaState
            if sectorTime < bestTime {
                state = .best
                bestSectorTimes[currentSectorIndex] = sectorTime
            } else if let prev = prevTime, sectorTime < prev {
                state = .faster
            } else {
                state = .slower
            }

            if sectorStates.indices.contains(currentSectorIndex) {
                sectorStates[currentSectorIndex] = state
            }

            currentSectorIndex += 1
            sectorStartDate = timestamp
            // UI: on vient de valider un secteur, le prochain démarre maintenant
            currentLapSectorTimesUI = currentLapSectorTimes
            liveSectorIndex = currentSectorIndex
            liveSectorElapsed = 0
        }
    }

    private func registerLapCrossing(at date: Date) {
        // 1er passage SF après START: on initialise le début du tour, mais on ne valide pas un lap.
            if awaitingFirstStartFinishCross {
                awaitingFirstStartFinishCross = false
                sessionStartDate = date

                // (optionnel mais cohérent) initialiser le début des secteurs
                sectorStartDate = date
                currentSectorIndex = 0
                currentLapSectorTimes = []
                lastLapSectorTimes = []
                sectorStates = Array(repeating: .neutral, count: max(1, min(sectorCount, 6)))
                let lineCount = sectorLineCount(for: raceConfig?.track)
                lastSectorCrossDates = Array(repeating: nil, count: lineCount)

                currentLapTime = 0
                currentLapSectorTimesUI = []
                liveSectorIndex = 0
                liveSectorElapsed = 0

                return
            }
        guard let start = sessionStartDate else {
            sessionStartDate = date
            return
        }

        let lapTime = date.timeIntervalSince(start)

        // NEW: ignore les tours anormalement courts
        if lapTime < minLapDurationSeconds {
            // On considère que ce passage SF est un faux positif.
            // On "repart" depuis maintenant pour éviter d'accumuler du temps.
            sessionStartDate = date

            // Optionnel mais recommandé: réaligner les secteurs sur ce nouveau "départ de tour"
            sectorStartDate = date
            currentSectorIndex = 0
            currentLapSectorTimes = []
            let lineCount = sectorLineCount(for: raceConfig?.track)
            lastSectorCrossDates = Array(repeating: nil, count: lineCount)
            currentLapSectorTimesUI = []
            liveSectorIndex = 0
            liveSectorElapsed = 0
            currentLapTime = 0
            return
        }

        // Valider le dernier secteur (dernier split -> SF) au passage SF
        if let track = raceConfig?.track {
            let sectorLines = availableSectorLines(from: track)
            let sectorsCount = max(1, sectorLines.count + 1)

            // S'assure que bestSectorTimes est prêt
            if bestSectorTimes.count != sectorsCount {
                bestSectorTimes = Array(repeating: .infinity, count: sectorsCount)
            }
            if sectorStates.count != max(1, min(sectorsCount, 6)) {
                sectorStates = Array(repeating: .neutral, count: max(1, min(sectorsCount, 6)))
            }

            // Si on n’a pas encore validé ce dernier secteur dans ce tour
            if currentSectorIndex == sectorsCount - 1, let start = sectorStartDate {
                let sectorTime = max(0, date.timeIntervalSince(start))

                if currentLapSectorTimes.count == currentSectorIndex {
                    currentLapSectorTimes.append(sectorTime)
                } else if currentLapSectorTimes.count > currentSectorIndex {
                    currentLapSectorTimes[currentSectorIndex] = sectorTime
                } else {
                    while currentLapSectorTimes.count < currentSectorIndex { currentLapSectorTimes.append(0) }
                    currentLapSectorTimes.append(sectorTime)
                }

                let prevTime: TimeInterval? = (lastLapSectorTimes.count > currentSectorIndex) ? lastLapSectorTimes[currentSectorIndex] : nil
                let bestTime: TimeInterval = bestSectorTimes[currentSectorIndex]

                let state: SectorDeltaState
                if sectorTime < bestTime {
                    state = .best
                    bestSectorTimes[currentSectorIndex] = sectorTime
                } else if let prev = prevTime, sectorTime < prev {
                    state = .faster
                } else {
                    state = .slower
                }

                if sectorStates.indices.contains(currentSectorIndex) {
                    sectorStates[currentSectorIndex] = state
                }

                // UI sync (optionnel mais cohérent)
                currentLapSectorTimesUI = currentLapSectorTimes
            }
        }
        
        completeLap(lapTime: lapTime)

        // Capture référence pilotage si nouveau best
        if let best = bestLapTime, abs(best - lapTime) < 0.0005 {
            let cleaned = currentLapSamples
                .filter { $0.s.isFinite && $0.t.isFinite && $0.s >= 0 && $0.t >= 0 }
                .sorted { $0.s < $1.s }

            // On accepte une référence dès qu'on a assez d'échantillons et une distance minimale
            if cleaned.count >= 5, (cleaned.last?.s ?? 0) > 50 {
                referenceLapSamples = cleaned
                referenceLapTotalDistance = cleaned.last?.s ?? 0
                isDeltaReady = referenceLapSamples.count >= 2
            }
        }

        smoothedDeltaToBest = 0

        // Reset pour le tour suivant (pilot delta)
        currentLapDistance = 0
        currentLapSamples = []

        // Reset secteur différé (laisser voir les rectangles ~3s)
        lastLapSectorTimes = currentLapSectorTimes
        currentLapSectorTimes = []

        pendingSectorResetWorkItem?.cancel()

        let resetWork = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.currentSectorIndex = 0
            self.sectorStartDate = date
            self.sectorStates = Array(
                repeating: .neutral,
                count: max(1, min(self.sectorCount, 6))
            )
            let lineCount = sectorLineCount(for: raceConfig?.track)
            self.lastSectorCrossDates = Array(repeating: nil, count: lineCount)

            self.currentLapSectorTimesUI = []
            self.liveSectorIndex = 0
            self.liveSectorElapsed = 0
        }

        pendingSectorResetWorkItem = resetWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: resetWork)


        // Nouveau tour
        sessionStartDate = date
        currentLapTime = 0
    }

    // MARK: - Track helpers
    private func trackLine(_ line: TrackLine) -> (a: (Double, Double), b: (Double, Double))? {
        guard let aLat = line.aLat, let aLon = line.aLon,
              let bLat = line.bLat, let bLon = line.bLon else {
            return nil
        }
        return (a: (aLat, aLon), b: (bLat, bLon))
    }

    private func availableSectorLines(from track: TrackDefinition) -> [TrackLine] {
        var lines: [TrackLine] = []
        let candidates: [TrackLine] = [track.sector1, track.sector2, track.sector3]
        for l in candidates {
            if trackLine(l) != nil { lines.append(l) }
        }
        return lines
    }
    
    private func sectorLineCount(for track: TrackDefinition?) -> Int {
        guard let track else { return 0 }
        return availableSectorLines(from: track).count
    }

    // MARK: - Geometry
    private func segmentsIntersect(
        a1: (Double, Double),
        a2: (Double, Double),
        b1: (Double, Double),
        b2: (Double, Double)
    ) -> Bool {
        let lat0 = (a1.0 + a2.0) * 0.5 * .pi / 180.0
        let lon0 = (a1.1 + a2.1) * 0.5
        let R = 6_371_000.0

        func proj(_ p: (Double, Double)) -> (x: Double, y: Double) {
            let lon = p.1
            let x = (lon - lon0) * .pi / 180.0 * cos(lat0) * R
            let y = (p.0 - (lat0 * 180.0 / .pi)) * .pi / 180.0 * R
            return (x, y)
        }

        let p1 = proj(a1)
        let p2 = proj(a2)
        let q1 = proj(b1)
        let q2 = proj(b2)

        func orient(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Double {
            (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
        }
        func onSeg(_ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double)) -> Bool {
            min(a.0, b.0) - 1e-9 <= c.0 && c.0 <= max(a.0, b.0) + 1e-9 &&
            min(a.1, b.1) - 1e-9 <= c.1 && c.1 <= max(a.1, b.1) + 1e-9
        }

        let o1 = orient(p1, p2, q1)
        let o2 = orient(p1, p2, q2)
        let o3 = orient(q1, q2, p1)
        let o4 = orient(q1, q2, p2)

        if (o1 > 0 && o2 < 0 || o1 < 0 && o2 > 0) &&
           (o3 > 0 && o4 < 0 || o3 < 0 && o4 > 0) {
            return true
        }

        if abs(o1) < 1e-9 && onSeg(p1, p2, q1) { return true }
        if abs(o2) < 1e-9 && onSeg(p1, p2, q2) { return true }
        if abs(o3) < 1e-9 && onSeg(q1, q2, p1) { return true }
        if abs(o4) < 1e-9 && onSeg(q1, q2, p2) { return true }

        return false
    }

    // MARK: - Pilot delta helpers
    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0

        let a =
            sin(dLat/2) * sin(dLat/2) +
            cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
            sin(dLon/2) * sin(dLon/2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    private func refTime(atDistance s: Double) -> TimeInterval? {
        guard referenceLapSamples.count >= 2 else { return nil }

        let sClamped = max(0, min(s, referenceLapSamples.last!.s))

        var lo = 0
        var hi = referenceLapSamples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if referenceLapSamples[mid].s < sClamped {
                lo = mid
            } else {
                hi = mid
            }
        }

        let a = referenceLapSamples[lo]
        let b = referenceLapSamples[hi]
        let ds = max(b.s - a.s, 1e-6)
        let alpha = (sClamped - a.s) / ds
        return a.t + (b.t - a.t) * alpha
    }

    // MARK: - Race reset
    func resetRaceData() {
        currentLapTime = 0
        lastLapTime = nil
        bestLapTime = nil
        deltaToBestLap = 0
        isDeltaReady = false
        lapCount = 0

        lapFlash = nil

        sectorStates = Array(repeating: .neutral, count: max(1, min(sectorCount, 6)))

        endPit(resetElapsed: true)

        sessionStartDate = nil
        isSessionRunning = false

        completedStints.removeAll()
        currentStintDriverName = nil
        currentStintNumber = 0
        currentStintStartDate = nil

        // Sectors internal
        currentSectorIndex = 0
        sectorStartDate = nil
        currentLapSectorTimes = []
        lastLapSectorTimes = []
        bestSectorTimes = []
        lastSectorCrossDates = []
        currentLapSectorTimesUI = []
        liveSectorIndex = 0
        liveSectorElapsed = 0

        // GPS
        lastGPSLat = nil
        lastGPSLon = nil
        lastStartFinishCrossDate = nil
        lastGPSTimestamp = nil
        awaitingFirstStartFinishCross = true

        // Pilot delta
        currentLapDistance = 0
        currentLapSamples = []
        referenceLapSamples = []
        referenceLapTotalDistance = 0
        
        smoothedDeltaToBest = 0

        lapTicker?.cancel()
        lapTicker = nil
    }

    // MARK: - Pit
    @Published var isInPit: Bool = false
    @Published var pitStartDate: Date?
    @Published var pitElapsedSeconds: TimeInterval = 0
    private var pitTicker: AnyCancellable?

    @Published var minimumPitSeconds: TimeInterval = 10

    func togglePit() {
        if isInPit {
            endPit(resetElapsed: true)
        } else {
            beginPit()
        }
    }

    private func beginPit() {
        isInPit = true
        pitStartDate = Date()
        pitElapsedSeconds = 0

        pitTicker?.cancel()
        pitTicker = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isInPit, let start = self.pitStartDate else { return }

                let elapsed = Date().timeIntervalSince(start)
                self.pitElapsedSeconds = elapsed

                if elapsed >= self.minimumPitSeconds {
                    self.endPit(resetElapsed: true)
                }
            }
    }

    private func endPit(resetElapsed: Bool) {
        isInPit = false
        pitStartDate = nil
        if resetElapsed { pitElapsedSeconds = 0 }

        pitTicker?.cancel()
        pitTicker = nil
    }

    // MARK: - ApexTiming (placeholder)
    @Published var racePosition: Int?
    @Published var remainingRaceTime: TimeInterval?

    // MARK: - Control
    func startSession() {
        // On démarre la session, mais le chrono du tour démarre au 1er passage Start/Finish
        sessionStartDate = nil
        isSessionRunning = true
        awaitingFirstStartFinishCross = true

        // Reset lap state
        currentLapDistance = 0
        currentLapSamples = []
        lastGPSTimestamp = nil

        smoothedDeltaToBest = 0
        isDeltaReady = false

        beginStint(for: selectedDriverName)

        lapTicker?.cancel()
        lapTicker = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isSessionRunning else { return }
                // Si le tour n'a pas encore été initialisé par SF, on affiche 0
                guard let start = self.sessionStartDate else {
                    self.currentLapTime = 0
                    return
                }
                self.currentLapTime = max(0, Date().timeIntervalSince(start))
            }
    }


    func stopSession() {
        if isSessionRunning {
            endCurrentStint()
        }
        isSessionRunning = false

        lapTicker?.cancel()
        lapTicker = nil
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
        lapCount += 1

        lapFlash = LapFlash(lapTime: lapTime, state: state)
    }

    // MARK: - Demo Mode Control
    func startDemoMode() {
        // Evite de relancer si déjà actif
        if isDemoMode { return }

        isDemoMode = true

        // Remise à zéro propre (sans toucher au layout)
        resetRaceData()
        isRaceStartArmed = false
        raceConfig = nil

        // Démarre une session "comme si" le Start/Finish avait déjà été passé
        startSession()
        awaitingFirstStartFinishCross = false
        sessionStartDate = Date()
        demoStartTime = Date()

        // Initialisation UI
        sectorCount = 3
        sectorStates = [.neutral, .neutral, .neutral]
        isDeltaReady = true
        deltaToBestLap = 0

        // Lap cible (tu peux ajuster)
        demoTargetLap = 5.0
        demoSpeedKmh = 72      // valeur de départ lisible

        // Timer qui simule delta + secteurs + laps
        demoTicker?.cancel()
        demoTicker = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isDemoMode, self.isSessionRunning else { return }
                
                // 0) Delta (oscillation réaliste)
                let t = Date().timeIntervalSince(self.demoStartTime ?? Date())
                self.deltaToBestLap = 1.8 * sin(t / 2.0)   // +/- ~1.8s
                
                // 1) Vitesse (simulation réaliste + stable)
                let base = 78.0 + 18.0 * sin(t / 1.7)          // oscillation
                let noise = Double.random(in: -2.0...2.0)      // petites variations
                self.demoSpeedKmh = max(0, base + noise)

                // 2) Secteurs (cycle: faster / slower / best)
                let phase = Int(t) % 6
                switch phase {
                case 0: self.sectorStates = [.faster, .neutral, .neutral]
                case 1: self.sectorStates = [.best, .neutral, .neutral]
                case 2: self.sectorStates = [.best, .faster, .neutral]
                case 3: self.sectorStates = [.best, .best, .neutral]
                case 4: self.sectorStates = [.best, .best, .faster]
                default: self.sectorStates = [.best, .best, .best]
                }

                // 3) Fin de tour simulée
                if let lapStart = self.sessionStartDate {
                    let lapElapsed = Date().timeIntervalSince(lapStart)
                    if lapElapsed >= self.demoTargetLap {
                        // Lap time simulé autour de demoTargetLap
                        let lapTime = self.demoTargetLap + Double.random(in: -0.6...0.8)
                        self.completeLap(lapTime: max(20, lapTime))

                        // Nouveau tour
                        self.sessionStartDate = Date()

                        // On varie légèrement la cible
                        self.demoTargetLap = max(30, self.demoTargetLap + Double.random(in: -0.7...0.7))

                        // Reset secteurs pour le nouveau tour
                        self.sectorStates = [.neutral, .neutral, .neutral]
                    }
                }
            }
    }

    func stopDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false

        demoTicker?.cancel()
        demoTicker = nil
        demoStartTime = nil

        // Stop session et reset minimal (tu peux choisir de conserver des stats si tu veux)
        stopSession()
        resetRaceData()
        isRaceStartArmed = false
        raceConfig = nil
        demoSpeedKmh = 0
    }
    
    // MARK: - Sectors UI (layout)
    enum SectorDeltaState: String, CaseIterable {
        case neutral
        case slower
        case faster
        case best
    }

    @Published var sectorCount: Int = 3 {
        didSet { normalizeSectorStates() }
    }

    @Published var sectorStates: [SectorDeltaState] = Array(repeating: .neutral, count: 3)
    
    private var pendingSectorResetWorkItem: DispatchWorkItem?

    private func normalizeSectorStates() {
        let clamped = max(1, min(sectorCount, 6))
        if sectorStates.count == clamped { return }
        if sectorStates.count < clamped {
            sectorStates.append(contentsOf: Array(repeating: .neutral, count: clamped - sectorStates.count))
        } else {
            sectorStates = Array(sectorStates.prefix(clamped))
        }
    }

    func setAllSectors(_ state: SectorDeltaState) {
        sectorStates = Array(repeating: state, count: max(1, min(sectorCount, 6)))
    }

    // MARK: - Login (mode démo)
    func logIn(email: String, password: String) -> Result<Void, AuthError> {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else { return .failure(.emptyEmail) }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else { return .failure(.invalidEmail) }
        guard !trimmedPassword.isEmpty else { return .failure(.emptyPassword) }

        storedIsLoggedIn = true
        isLoggedIn = true
        userNickname = storedUserNickname
        applyNicknameAsDriver1()
        return .success(())
    }

    func signUp(email: String, password: String, confirmPassword: String, nickname: String) -> Result<Void, AuthError> {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else { return .failure(.emptyEmail) }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else { return .failure(.invalidEmail) }
        guard !trimmedPassword.isEmpty else { return .failure(.emptyPassword) }

        let minLen = 8
        guard trimmedPassword.count >= minLen else { return .failure(.passwordTooShort(min: minLen)) }
        guard password == confirmPassword else { return .failure(.passwordMismatch) }

        let trimmedNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNick.isEmpty {
            storedUserNickname = trimmedNick
            userNickname = trimmedNick
        }

        storedIsLoggedIn = true
        isLoggedIn = true
        applyNicknameAsDriver1()
        return .success(())
    }

    func logOut() {
        storedIsLoggedIn = false
        isLoggedIn = false
    }
}

// MARK: - App Lifecycle
func handleScenePhaseChange(_ phase: ScenePhase) {
    switch phase {
    case .active:
        break
    case .inactive:
        break
    case .background:
        break
    @unknown default:
        break
    }
}
