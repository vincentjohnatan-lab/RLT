import SwiftUI
import Combine
import UIKit

enum AppearancePreference: String {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}


@main
struct RLTApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionManager()
    @AppStorage("appearance_preference") private var appearanceRawValue = AppearancePreference.system.rawValue
    @StateObject private var raceBoxGPS = RaceBoxGPSManager()
    @StateObject private var trackStore = TrackStore()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(session)
                .environmentObject(raceBoxGPS)
                .environmentObject(trackStore)
                .preferredColorScheme(
                    AppearancePreference(rawValue: appearanceRawValue)?.colorScheme
                )
        }
    }
}

// GERER LES ORIENTATIONS DE L'APP

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.current
    }
}

enum OrientationLock {
    static var current: UIInterfaceOrientationMask = .all
}


// MARK: - Routing

enum AppRoute: String, CaseIterable, Identifiable {
    case home = "Home"
    case live = "Live"
    case stats = "Stats"
    case spotter = "Spotter"
    case weather = "Weather"
    case settings = "Settings"

    var id: String { rawValue }
}

// MARK: - Root Shell (full screen + menu)

struct RootShellView: View {
    @EnvironmentObject var session: SessionManager
    @State private var route: AppRoute = .home
    @State private var isMenuPresented: Bool = false
    @State private var isHomeRaceSetupPresented: Bool = false
    
    var body: some View {
        Group {
            if session.isLoggedIn {
                Group {
                    switch route {
                    case .home:
                        HomeView(onLiveTap: {
                            // Si une course existe déjà (armée ou en cours), on reprend le Live directement
                            if session.raceConfig != nil {
                                route = .live
                            } else {
                                // Sinon, on passe par le setup (comportement actuel)
                                isHomeRaceSetupPresented = true
                            }
                        })
                    case .live:
                        LiveView(
                            onHomeTap: { route = .home },
                            onWeatherTap: { route = .weather },
                            onSettingsTap: { route = .settings }
                        )

                    case .weather:
                        WeatherView()

                    case .stats:
                        StatsView()

                    case .spotter:
                        SpotterView()

                    case .settings:
                        SettingsView(onClose: {
                            route = .live
                        })
                    }
                }
                .sheet(isPresented: $isHomeRaceSetupPresented) {
                    RaceSetupView(
                        initialMinimumPitSeconds: session.minimumPitSeconds,
                        initialDrivers: session.drivers
                    ) { config in
                        session.armRaceStart(with: config)
                        isHomeRaceSetupPresented = false
                        route = .live
                    }
                    .presentationDetents([.fraction(0.98), .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
                }
                .sheet(isPresented: $isMenuPresented) {
                    MenuSheetView(route: $route, isPresented: $isMenuPresented)
                }
            } else {
                LoginView()
            }
        }
    }
}


// MARK: - Menu Sheet

struct MenuSheetView: View {
    @Binding var route: AppRoute
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppRoute.allCases) { item in
                    Button {
                        route = item
                        isPresented = false
                    } label: {
                        HStack {
                            Text(item.rawValue)
                            Spacer()
                            if item == route {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Menu")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Driver

struct DriverPickerSheet: View {
    let drivers: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(drivers, id: \.self) { name in
                    Button {
                        onSelect(name)
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if name == selected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Driver")
        }
    }
}

// MARK: - Sectors

struct SectorIndicatorsRow: View {
    let states: [SessionManager.SectorDeltaState]

    private let spacing: CGFloat = 6
    private let height: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let n = max(states.count, 1)
            let totalSpacing = spacing * CGFloat(max(n - 1, 0))
            let rawWidth = (geo.size.width - totalSpacing) / CGFloat(n)
            let width = min(max(rawWidth, 44), 90) // garde-fou min/max

            HStack(spacing: spacing) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color(for: state))
                        .frame(width: width, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height) // hauteur fixe
    }

    private func color(for state: SessionManager.SectorDeltaState) -> Color {
        switch state {
        case .neutral: return .gray.opacity(0.45)
        case .slower:  return .yellow
        case .faster:  return .green
        case .best:    return .purple
        }
    }
}

// MARK: - Delta bar (dark track, iRacing-ish)

struct DeltaBar: View {
    /// delta > 0 : retard (vers la droite)
    /// delta < 0 : avance (vers la gauche)
    let deltaSeconds: TimeInterval

    /// Barre pleine à +/- rangeSeconds
    var rangeSeconds: TimeInterval = 2.0

    /// Plus épais
    var barHeight: CGFloat = 14

    private var trackColor: Color { Color(white: 0.18) } // gris très foncé
    private var centerMarkColor: Color { Color(white: 0.75).opacity(0.7) }

    var body: some View {
        GeometryReader { geo in
            let fullW = max(1, geo.size.width)
            let halfW = fullW / 2

            let clamped = max(-rangeSeconds, min(rangeSeconds, deltaSeconds))
            let ratio = CGFloat(abs(clamped) / max(rangeSeconds, 0.0001))
            let fillW = ratio * halfW

            ZStack {
                Capsule()
                    .fill(trackColor)

                // marqueur central
                Rectangle()
                    .fill(centerMarkColor)
                    .frame(width: 2)

                // remplissage depuis le centre
                if clamped < 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: fillW)
                        .offset(x: -(fillW / 2))
                        .clipShape(Capsule())
                } else if clamped > 0 {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: fillW)
                        .offset(x: +(fillW / 2))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: barHeight)
    }
}

struct DeltaCenterTile: View {
        let deltaSeconds: TimeInterval
        var rangeSeconds: TimeInterval = 2.0
        var currentLapSeconds: TimeInterval? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var tileBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var borderColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func formatLapTime(_ seconds: TimeInterval) -> String {
        let totalMs = max(0, Int((seconds * 1000.0).rounded()))
        let minutes = totalMs / 60000
        let remMs = totalMs % 60000
        let secs = remMs / 1000
        let ms = remMs % 1000
        return String(format: "%d:%02d.%03d", minutes, secs, ms)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Delta time")
                .font(.headline)
                .foregroundStyle(.secondary)

            // La barre EST dans la tuile grise
            DeltaBar(deltaSeconds: deltaSeconds, rangeSeconds: rangeSeconds, barHeight: 20)

            Text(String(format: "%+.3f", deltaSeconds))
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(deltaSeconds < 0 ? .green : (deltaSeconds > 0 ? .red : .primary))

            if let t = currentLapSeconds {
                Text(formatLapTime(t))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(tileBackground)
        .overlay(
            Rectangle().stroke(borderColor, lineWidth: 4)
        )
        .padding(.horizontal, 2)

   // contour noir épais, angles droits
    }
}

// MARK: - Layout telemetry

struct TelemetryTile: View {
    let title: String
    let value: String
    var valueFont: Font = .title2
    @Environment(\.colorScheme) private var colorScheme

    private var tileBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(valueFont)
                .fontDesign(.monospaced)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct CenterTile: View {
    let title: String
    let value: String
    let valueFontSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: valueFontSize, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview

#Preview(traits: .landscapeLeft) {
    RootShellView()
        .environmentObject(SessionManager())
}
