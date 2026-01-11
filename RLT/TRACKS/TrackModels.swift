//
//  TrackModels.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 10/01/2026.
//

import Foundation

enum TrackDirection: String, Codable, CaseIterable, Identifiable {
    case clockwise
    case counterClockwise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clockwise: return "Clockwise"
        case .counterClockwise: return "Counter-clockwise"
        }
    }
}

/// Ligne définie par 2 points A/B.
/// Pour l’instant optionnels : on les remplira avec la carte plus tard.
struct TrackLine: Codable, Equatable {
    var aLat: Double?
    var aLon: Double?
    var bLat: Double?
    var bLon: Double?
}

struct TrackDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var direction: TrackDirection

    // Lignes A/B (à remplir via la carte plus tard)
    var startFinish: TrackLine = TrackLine()
    var sector1: TrackLine = TrackLine()
    var sector2: TrackLine = TrackLine()
    var sector3: TrackLine = TrackLine()

    var createdAt: Date = Date()
}
