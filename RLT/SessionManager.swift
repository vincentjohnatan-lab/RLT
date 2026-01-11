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

    // MARK: - Auth (persisted)
    @AppStorage("isLoggedIn") private var storedIsLoggedIn: Bool = false
    @Published var isLoggedIn: Bool = false
    @AppStorage("userNickname") private var storedUserNickname: String = ""
    @Published var userNickname: String = ""

    init() {
        self.isLoggedIn = storedIsLoggedIn
        self.userNickname = storedUserNickname

        if self.isLoggedIn {
            applyNicknameAsDriver1()
        }
    }

    // MARK: - Session state
    @Published var isSessionRunning: Bool = false
    @Published var sessionStartDate: Date?

    // MARK: - Live data
    @Published var currentLapTime: TimeInterval = 0
    @Published var lastLapTime: TimeInterval?
    @Published var bestLapTime: TimeInterval?
    @Published var deltaToBestLap: TimeInterval = 0
    private var lapTicker: AnyCancellable?

    // MARK: - Drivers
    @Published var drivers: [String] = ["Driver 1", "Driver 2"]
    @Published var selectedDriverName: String = "Driver 1"

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
        sectorCount = max(1, sectorLines.count)

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

            if let refT = refTime(atDistance: currentLapDistance) {
                let raw = t - refT

                // EMA: lissage pour stabiliser le delta (réduit le jitter GPS)
                smoothedDeltaToBest = smoothedDeltaToBest + deltaEmaAlpha * (raw - smoothedDeltaToBest)
                deltaToBestLap = smoothedDeltaToBest
            } else {
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

        if lastSectorCrossDates.count != sectorLines.count {
            lastSectorCrossDates = Array(repeating: nil, count: sectorLines.count)
        }
        if bestSectorTimes.count != sectorLines.count {
            bestSectorTimes = Array(repeating: .infinity, count: sectorLines.count)
        }

        guard currentSectorIndex < sectorLines.count else { return }
        guard let seg = trackLine(sectorLines[currentSectorIndex]) else { return }

        if let last = lastSectorCrossDates[currentSectorIndex],
           timestamp.timeIntervalSince(last) < 1.5 {
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
                lastSectorCrossDates = Array(repeating: nil, count: max(0, min(sectorCount, 6)))

                currentLapTime = 0
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
            lastSectorCrossDates = Array(repeating: nil, count: max(0, min(sectorCount, 6)))

            currentLapTime = 0
            return
        }

        completeLap(lapTime: lapTime)

        // Capture référence pilotage si nouveau best
        if let best = bestLapTime, abs(best - lapTime) < 0.0005 {
            let cleaned = currentLapSamples
                .filter { $0.s.isFinite && $0.t.isFinite && $0.s >= 0 && $0.t >= 0 }
                .sorted { $0.s < $1.s }

            if cleaned.count >= 10 {
                referenceLapSamples = cleaned
                referenceLapTotalDistance = cleaned.last?.s ?? 0
            }
        }

        smoothedDeltaToBest = 0

        // Reset pour le tour suivant (pilot delta)
        currentLapDistance = 0
        currentLapSamples = []

        // Reset secteur pour le tour suivant
        lastLapSectorTimes = currentLapSectorTimes
        currentLapSectorTimes = []
        currentSectorIndex = 0
        sectorStartDate = date
        sectorStates = Array(repeating: .neutral, count: max(1, min(sectorCount, 6)))
        lastSectorCrossDates = Array(repeating: nil, count: max(0, min(sectorCount, 6)))

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
