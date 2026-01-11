//
//  PlaceSearchCompleter.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 10/01/2026.
//

import SwiftUI
import MapKit
import Combine

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.address, .pointOfInterest]
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    func clear() {
        results = []
    }

    func search(from completion: MKLocalSearchCompletion) async throws -> MKLocalSearch.Response {
        let request = MKLocalSearch.Request(completion: completion)
        return try await MKLocalSearch(request: request).start()
    }
}
