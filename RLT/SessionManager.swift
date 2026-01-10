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

        // Si l'utilisateur est déjà loggé et a un nickname, on force Driver 1
        if self.isLoggedIn {
            applyNicknameAsDriver1()
        }
    }


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
        guard name != selectedDriverName else { return }

        // Si la course tourne, on clôture le stint en cours et on redémarre un nouveau stint à 0
        if isSessionRunning {
            endCurrentStint()
            selectedDriverName = name
            beginStint(for: name)
        } else {
            // Hors course : simple sélection
            selectedDriverName = name
        }
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

        // Reset uniquement du stint courant
        currentStintDriverName = nil
        currentStintStartDate = nil
        currentStintNumber = 0
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
        var trackName: String
        var minimumPitSeconds: TimeInterval
        var driverNames: [String]
        var createdAt: Date = Date()
    }

    /// Config courante (utile pour afficher des infos plus tard)
    @Published var raceConfig: RaceConfig?

    /// Vrai tant que la course est "armée" mais pas encore démarrée (overlay START affiché)
    @Published var isRaceStartArmed: Bool = false

    /// Compteurs simples (placeholders évolutifs)
    @Published var lapCount: Int = 0

    /// Stint par pilote (0 au lancement)
    @Published var driverStints: [String: Int] = [:]
    // MARK: - Stints (stats)

    // Un stint terminé (pour stats / historique)
    struct StintRecord: Identifiable {
        let id = UUID()
        let driverName: String
        let stintNumber: Int
        let startedAt: Date
        let endedAt: Date

        var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    }

    // Historique des stints terminés (à exploiter plus tard dans un écran Stats)
    @Published private(set) var completedStints: [StintRecord] = []

    // Stint en cours
    @Published private(set) var currentStintDriverName: String?
    @Published private(set) var currentStintNumber: Int = 0
    @Published private(set) var currentStintStartDate: Date?

    // Temps écoulé du stint courant (0 si pas de stint actif)
    var currentStintElapsed: TimeInterval {
        guard isSessionRunning, let start = currentStintStartDate else { return 0 }
        return Date().timeIntervalSince(start)
    }


    /// Prépare une nouvelle course : reset + arme l'overlay START.
    func armRaceStart(with config: RaceConfig) {
        raceConfig = config

        // Applique la config
        minimumPitSeconds = config.minimumPitSeconds

        // Drivers
        drivers = config.driverNames.isEmpty ? ["Driver 1"] : config.driverNames
        selectedDriverName = drivers.first ?? "Driver 1"
        applyNicknameAsDriver1()
        driverStints = Dictionary(uniqueKeysWithValues: drivers.map { ($0, 0) })

        // Reset course data
        resetRaceData()
        
        // La course ne démarre pas tant que l'utilisateur n'a pas tap "START"
        isRaceStartArmed = true
        stopSession()
    }

    /// Démarre réellement la course (appelé au tap sur l'overlay START)
    func startArmedRace() {
        guard isRaceStartArmed else { return }
        isRaceStartArmed = false
        startSession()
    }

    /// Remise à zéro des données live (secteurs, best, laps, pits, delta, etc.)
    func resetRaceData() {
        // Laps / best
        currentLapTime = 0
        lastLapTime = nil
        bestLapTime = nil
        deltaToBestLap = 0
        lapCount = 0
        
        // Lap flash
        lapFlash = nil
        
        // Sectors -> neutre
        sectorStates = Array(repeating: .neutral, count: max(1, min(sectorCount, 6)))
        
        // Pit reset
        endPit(resetElapsed: true)
        
        // Session timer
        sessionStartDate = nil
        isSessionRunning = false
        
        // Stints reset (nouvelle course)
        completedStints.removeAll()
        currentStintDriverName = nil
        currentStintNumber = 0
        currentStintStartDate = nil
    }

    // MARK: - Pit
    @Published var isInPit: Bool = false
    @Published var pitStartDate: Date?
    @Published var pitElapsedSeconds: TimeInterval = 0
    private var pitTicker: AnyCancellable?


    // Minimum pit time for the session (Settings)
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

        // Lance/relance le ticker (évite les doublons)
        pitTicker?.cancel()
        pitTicker = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isInPit, let start = self.pitStartDate else { return }

                let elapsed = Date().timeIntervalSince(start)
                self.pitElapsedSeconds = elapsed

                // Auto-close PIT quand le minimum est atteint
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
        sessionStartDate = Date()
        isSessionRunning = true

        // Démarre le stint du pilote sélectionné au start
        beginStint(for: selectedDriverName)
    }


    func stopSession() {
        if isSessionRunning {
            endCurrentStint()
        }
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
        lapCount += 1

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
    
    // MARK: - Login (mode démo)
    func logIn(email: String, password: String) -> Result<Void, AuthError> {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else { return .failure(.emptyEmail) }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else { return .failure(.invalidEmail) }
        guard !trimmedPassword.isEmpty else { return .failure(.emptyPassword) }

        // Mode démo : on accepte si non vide + email "semble" valide
        storedIsLoggedIn = true
        isLoggedIn = true
        userNickname = storedUserNickname
              applyNicknameAsDriver1()
        return .success(())
    }

    // MARK: - Sign Up (mode démo)
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

        // Mode démo : on "crée" et connecte
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
        // App revient au premier plan
        // Rien à recalculer : les timers basés sur Date restent justes
        break

    case .inactive:
        // Transition (appel, verrouillage écran, etc.)
        break

    case .background:
        // App en arrière-plan
        // On ne stoppe PAS la session volontairement
        break

    @unknown default:
        break
    }
}

