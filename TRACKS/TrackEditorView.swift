//
//  TrackEditorView.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 10/01/2026.
//

import SwiftUI
import MapKit
import Combine

struct TrackEditorView: View {
    @EnvironmentObject private var trackStore: TrackStore
    @Environment(\.dismiss) private var dismiss
    

    @State private var draft: TrackDefinition
    @StateObject private var completer = PlaceSearchCompleter()


    // Sélection de ce qu'on édite sur la carte
    private enum LineTarget: String, CaseIterable, Identifiable {
        case startFinish = "Start/Finish"
        case sector1 = "Sector 1"
        case sector2 = "Sector 2"
        case sector3 = "Sector 3"
        var id: String { rawValue }
    }

    private enum PointSlot: String, CaseIterable, Identifiable {
        case a = "Point A"
        case b = "Point B"
        var id: String { rawValue }
    }

    @State private var target: LineTarget = .startFinish
    @State private var slot: PointSlot = .a

    enum EditorMode {
        case create
        case edit
    }
    private let mode: EditorMode
    
    // Caméra
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), // défaut Paris
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )

    init(track: TrackDefinition, mode: EditorMode = .edit) {
        self.mode = mode
        _draft = State(initialValue: track)
    }


    var body: some View {
        Form {
            Section("Track info") {
                TextField("Track name", text: $draft.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Picker("Direction", selection: $draft.direction) {
                    ForEach(TrackDirection.allCases) { d in
                        Text(d.title).tag(d)
                    }
                }
            }
            
            Section("Search") {
                TextField("Search address or karting complex", text: $completer.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !completer.results.isEmpty {
                    ForEach(completer.results, id: \.self) { item in
                        Button {
                            Task { await selectCompletion(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            
            Section("Map placement") {
                Picker("Line", selection: $target) {
                    ForEach(LineTarget.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }

                Picker("Point", selection: $slot) {
                    ForEach(PointSlot.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                Text("Tap on the map to set \(target.rawValue) – \(slot.rawValue).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Toutes les annotations existantes
                        annotations(for: .startFinish, line: draft.startFinish)
                        annotations(for: .sector1, line: draft.sector1)
                        annotations(for: .sector2, line: draft.sector2)
                        annotations(for: .sector3, line: draft.sector3)

                        // Polylines (si A et B sont définis)
                        polyline(for: draft.startFinish)
                        polyline(for: draft.sector1)
                        polyline(for: draft.sector2)
                        polyline(for: draft.sector3)
                    }
                    .mapStyle(.imagery)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let coord = proxy.convert(value.location, from: .local) {
                                    setPoint(coord)
                                }
                            }
                    )
                }
            }
        }
        .navigationTitle("Edit track")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    draft.name = trimmed

                    switch mode {
                    case .create:
                        trackStore.addTrack(draft)
                    case .edit:
                        trackStore.updateTrack(draft)
                    }

                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            // Centrer la carte sur un point existant si dispo
            if let c = firstDefinedCoordinate(in: draft) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: c,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )
                )
            }
        }
    }

    // MARK: - Map helpers

    private func firstDefinedCoordinate(in t: TrackDefinition) -> CLLocationCoordinate2D? {
        let lines = [t.startFinish, t.sector1, t.sector2, t.sector3]
        for l in lines {
            if let a = l.aCoordinate { return a }
            if let b = l.bCoordinate { return b }
        }
        return nil
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        do {
            let response = try await completer.search(from: completion)
            guard let mapItem = response.mapItems.first else { return }

            let coord = mapItem.location.coordinate

            await MainActor.run {
                // Remplit le champ avec le choix (comme Plans)
                completer.query = completion.title
                completer.clear()

                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )
                )
            }
        } catch {
            // Optionnel : tu peux garder un message d'erreur si tu veux
        }
    }
    
    private func setPoint(_ coord: CLLocationCoordinate2D) {
        completer.clear()
        switch target {
        case .startFinish:
            setPoint(on: &draft.startFinish, coord: coord)
        case .sector1:
            setPoint(on: &draft.sector1, coord: coord)
        case .sector2:
            setPoint(on: &draft.sector2, coord: coord)
        case .sector3:
            setPoint(on: &draft.sector3, coord: coord)
        }
    }

    private func setPoint(on line: inout TrackLine, coord: CLLocationCoordinate2D) {
        switch slot {
        case .a:
            line.aLat = coord.latitude
            line.aLon = coord.longitude
        case .b:
            line.bLat = coord.latitude
            line.bLon = coord.longitude
        }
    }

    private func annotations(for target: LineTarget, line: TrackLine) -> some MapContent {
        let prefix: String = {
            switch target {
            case .startFinish: return "SF"
            case .sector1: return "S1"
            case .sector2: return "S2"
            case .sector3: return "S3"
            }
        }()

        return Group {
            if let a = line.aCoordinate {
                Annotation("\(prefix) A", coordinate: a) {
                    labelView(text: "\(prefix)A")
                }
            }
            if let b = line.bCoordinate {
                Annotation("\(prefix) B", coordinate: b) {
                    labelView(text: "\(prefix)B")
                }
            }
        }
    }

    private func polyline(for line: TrackLine) -> some MapContent {
        Group {
            if let a = line.aCoordinate, let b = line.bCoordinate {
                MapPolyline(coordinates: [a, b])
                    .stroke(.blue, lineWidth: 3)
            }
        }
    }

    private func labelView(text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - TrackLine conveniences (kept here to avoid touching your model file too much)

private extension TrackLine {
    var aCoordinate: CLLocationCoordinate2D? {
        guard let aLat, let aLon else { return nil }
        return CLLocationCoordinate2D(latitude: aLat, longitude: aLon)
    }
    var bCoordinate: CLLocationCoordinate2D? {
        guard let bLat, let bLon else { return nil }
        return CLLocationCoordinate2D(latitude: bLat, longitude: bLon)
    }
}
