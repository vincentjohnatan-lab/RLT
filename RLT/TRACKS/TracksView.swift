//
//  TracksView.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 10/01/2026.
//

import SwiftUI

struct TracksView: View {
    let onClose: () -> Void

    @EnvironmentObject var trackStore: TrackStore
    @State private var isAddPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Tracks") {
                    ForEach(trackStore.tracks) { t in
                        NavigationLink {
                            TrackEditorView(track: t)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.name)
                                    .font(.headline)
                                Text(t.direction.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: trackStore.delete)
                }

                Section {
                    Button {
                        isAddPresented = true
                    } label: {
                        Label("Add track", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Track")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Label("Retour", systemImage: "chevron.left")
                    }
                }
            }
            .sheet(isPresented: $isAddPresented) {
                NavigationStack {
                    TrackEditorView(
                        track: TrackDefinition(name: "", direction: .clockwise),
                        mode: .create
                    )
                }
                .environmentObject(trackStore)
            }
        }
    }
}
