//
//  PurchaseManager.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 14/01/2026.
//

import Foundation
import SwiftUI
import Combine

/// Étape 1: simple "entitlement" persistée.
/// Étape 2 (plus tard): on remplacera unlock/lock par StoreKit2 (achat, restore, etc.).
final class PurchaseManager: ObservableObject {

    /// Pour un premier MVP: booléen persisté localement.
    /// On migrera vers une logique d'entitlements basée sur StoreKit / serveur si besoin.
    @AppStorage("entitlement_live_access") private var storedLiveAccess: Bool = false
    @Published private(set) var hasLiveAccess: Bool = false

    init() {
        self.hasLiveAccess = storedLiveAccess
    }

    // MARK: - MVP controls (placeholder)

    func grantLiveAccessForNow() {
        storedLiveAccess = true
        hasLiveAccess = true
    }

    func revokeLiveAccessForNow() {
        storedLiveAccess = false
        hasLiveAccess = false
    }
}

