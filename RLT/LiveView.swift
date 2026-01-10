
import SwiftUI
import Combine

struct LiveView: View {
    let onHomeTap: () -> Void
    let onWeatherTap: () -> Void
    let onSettingsTap: () -> Void

    @EnvironmentObject var sessionManager: SessionManager
    @State private var isDriverSheetPresented: Bool = false
    @State private var isRaceSetupPresented: Bool = false
    @State private var controlsBarHeight: CGFloat = 0

#if DEBUG
    @State private var simTick: Int = 0
    @State private var simTimer: Timer?
#endif

    @State private var activeLapFlash: SessionManager.LapFlash? = nil
    
    @Environment(\.colorScheme) private var colorScheme

    private var tileBackground: Color {
        colorScheme == .dark ? .black : .white
    }

        private func formatLapTime(_ seconds: TimeInterval) -> String {
            let totalMs = max(0, Int((seconds * 1000.0).rounded()))
            let minutes = totalMs / 60000
            let remMs = totalMs % 60000
            let secs = remMs / 1000
            let ms = remMs % 1000
            return String(format: "%d:%02d.%03d", minutes, secs, ms)
        }

        private func lapFlashColor(for state: SessionManager.LapFlashState) -> Color {
            switch state {
            case .bestEver: return .purple
            case .improvedPrevious: return .green
            case .normal: return .yellow
            }
        }

        private enum WeatherState {
            case sunny, cloudy, rainy
        }

        private enum GPSQuality {
            case none, weak, good
        }

        @State private var weatherState: WeatherState = .sunny
        @State private var gpsQuality: GPSQuality = .good

        private var weatherSymbolName: String {
            switch weatherState {
            case .sunny:  return "sun.max.fill"
            case .cloudy: return "cloud.fill"
            case .rainy:  return "cloud.rain.fill"
            }
        }

        private var gpsFilledBars: Int {
            switch gpsQuality {
            case .none: return 0
            case .weak: return 1
            case .good: return 3
            }
        }

        
        // Timer léger (4 fois par seconde) pour un affichage fluide
        private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
        private let sectorRectWidth: CGFloat = 70
        private let sectorSpacing: CGFloat = 6
        private let rowSpacing: CGFloat = 10
        private let smallRowHeight: CGFloat = 60

        private func middleColumnWidth(for sectorCount: Int) -> CGFloat {
            let n = max(sectorCount, 1)
            return CGFloat(n) * sectorRectWidth + CGFloat(max(n - 1, 0)) * sectorSpacing
        }

        var body: some View {
            NavigationStack {
                ZStack(alignment: .bottom) {

                    GeometryReader { geo in
                        let midW = middleColumnWidth(for: sessionManager.sectorStates.count)
                        let sideW = max(0, (geo.size.width - midW) / 2)
                        let contentHeight = max(0, geo.size.height - controlsBarHeight)

                        // 3 lignes : petite / grande / petite
                        let totalSmallRowsHeight = smallRowHeight * 2
                        let availableH = max(0, contentHeight - totalSmallRowsHeight - (rowSpacing * 2))
                        let bigRowHeight = availableH


                        HStack(spacing: 0) {

                            // MARK: - Colonne gauche (3 lignes)
                            VStack(spacing: rowSpacing) {
                                // Row 1 (petite) - stint & lap
                                VStack(alignment: .leading, spacing: 2) {

                                    HStack(spacing: 4) {
                                        Text("STINT")
                                            .frame(width: 44, alignment: .leading)

                                        Text("#\(max(1, sessionManager.currentStintNumber))")
                                            .frame(width: 28, alignment: .leading)
                                        
                                        Text(":")
                                            .frame(width: 6)

                                        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                            Text(formatStintTime(sessionManager.currentStintElapsed))
                                                .padding(.leading, 5)
                                        }
                                    }
                                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                    HStack(spacing: 4) {
                                        Text("LAP")
                                            .frame(width: 44, alignment: .leading)

                                        Text(":")
                                            .frame(width: 6)

                                        Text("\(sessionManager.lapCount)")
                                            .padding(.leading, 5)
                                            .frame(width: 44, alignment: .leading)

                                        
                                    }
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: smallRowHeight)
                                .padding(.horizontal, 12)

                                // Row 2 - vitesse km/h
                                VStack {
                                    Text("Speed (km/h)")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 0)

                                    Text("78")
                                        .font(.system(size: 80, weight: .light, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)

                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(tileBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .frame(height: bigRowHeight)

                                
                                // Row 3 - PIT / OUT
                                Button {
                                    sessionManager.togglePit()
                                } label: {
                                    Text(sessionManager.isInPit ? "OUT" : "PIT")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(sessionManager.isInPit ? .red : Color(red: 0.0, green: 0.48, blue: 1.0))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    sessionManager.isInPit ? .red : Color(red: 0.0, green: 0.48, blue: 1.0),
                                                    lineWidth: 3
                                                )
                                        )
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .frame(height: smallRowHeight)
                            }
                            .padding(.vertical, 10)
                            .frame(width: sideW, height: contentHeight)

                            // MARK: - Colonne centre (3 lignes) avec secteurs en row 1
                            
                            VStack(spacing: rowSpacing) {
                                // Row 1 (petite) - secteurs + last lap en dessous
                                VStack(spacing: 10) {
                                    SectorIndicatorsRow(states: sessionManager.sectorStates)

                                    Text("LAST  1.31.878")
                                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: smallRowHeight)

                                // Row 2 (Delta + overlay PIT si besoin)
                                ZStack {
                                    DeltaCenterTile(deltaSeconds: sessionManager.deltaToBestLap, rangeSeconds: 2.0)

                                    if sessionManager.isInPit {
                                        VStack(spacing: 12) {
                                            Text("PIT")
                                                .font(.system(size: 44, weight: .heavy))
                                                .foregroundStyle(.white)

                                            Text(formatPitTime(seconds: currentPitSeconds))
                                                .font(.system(size: 88, weight: .bold, design: .monospaced))
                                                .minimumScaleFactor(0.5)
                                                .lineLimit(1)
                                                .foregroundStyle(.white)

                                        }
                                        .padding(24)
                                        .background(Color(red: 0.0, green: 0.48, blue: 1.0))
                                        .clipShape(RoundedRectangle(cornerRadius: 0))
                                    }
                                }
                                .frame(height: bigRowHeight)

                                // Row 3 - Best Lap
                                VStack(spacing: 4) {

                                    HStack(spacing: 8) {
                                        Image(systemName: "trophy.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))

                                        Text("1.30.345")
                                            .font(.system(size: 40, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 0.13))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background(Color(tileBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .frame(height: smallRowHeight)

                            }
                            .padding(.vertical, 10)
                            .frame(width: midW, height: contentHeight)

                            // MARK: - Colonne droite (3 lignes)
                            VStack(spacing: rowSpacing) {
                                // Row 1 (petite)
                                VStack(alignment: .trailing, spacing: 2) {

                                    HStack(spacing: 0) {
                                        Text("REM. TIME")
                                            .frame(width: 82, alignment: .leading)

                                        Text(":")
                                            .frame(width: 14, alignment: .center)

                                        Text("1:58")
                                            .frame(width: 50, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                    HStack(spacing: 0) {
                                        Text("TOT LAP")
                                            .frame(width: 82, alignment: .leading)

                                        Text(":")
                                            .frame(width: 14, alignment: .center)

                                        Text("88")
                                            .frame(width: 50, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .frame(height: smallRowHeight)
                                .padding(.horizontal, 12)

                                // Row 2 - position
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Position")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    // Devant
                                    HStack(spacing: 10) {
                                        Text("↑")
                                            .font(.system(size: 18, weight: .bold))

                                        Text("#12")
                                            .font(.system(size: 20, weight: .bold, design: .monospaced))

                                        Spacer(minLength: 0)

                                        Text("+0.842")
                                            .font(.system(size: 25, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    // Notre position (au milieu)
                                    Text("6/43")
                                        .font(.system(size: 64, weight: .semibold, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)

                                    Spacer(minLength: 0)

                                    // Derrière
                                    HStack(spacing: 10) {
                                        Text("↓")
                                            .font(.system(size: 18, weight: .bold))

                                        Text("#7")
                                            .font(.system(size: 20, weight: .bold, design: .monospaced))

                                        Spacer(minLength: 0)

                                        Text("-0.315")
                                            .font(.system(size: 25, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color(tileBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .frame(height: bigRowHeight)


                                // Row 3
                                Button {
                                    isDriverSheetPresented = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "steeringwheel")
                                            .font(.system(size: 20, weight: .bold))

                                        Text(sessionManager.selectedDriverName)
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.red, lineWidth: 3)
                                    )
                                    .padding(6)
                                }
                                .buttonStyle(.plain)
                                .frame(height: smallRowHeight)
                            }
                            .padding(.vertical, 10)
                            .frame(width: sideW, height: contentHeight)
                        }
                    }
                    
                    // Full-screen Lap Flash (2s)
                    if let flash = activeLapFlash {
                        ZStack {
                            // Optionnel: léger voile pour la lisibilité
                            Color(.systemBackground).ignoresSafeArea()

                            Text(formatLapTime(flash.lapTime))
                                .font(.system(size: 120, weight: .heavy, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.2)
                                .foregroundStyle(lapFlashColor(for: flash.state))
                                .padding(24)
                        }
                        .transition(.opacity)
                        .zIndex(10)
                    }
                    
                    // Full-screen START gate (tap to start)
                    if sessionManager.isRaceStartArmed {
                        ZStack {
                            Color.white.ignoresSafeArea()

                            VStack(spacing: 16) {
                                Text("START")
                                    .font(.system(size: 120, weight: .heavy, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.2)
                                    .foregroundStyle(.black)

                                Text("Tap anywhere to start")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(24)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            sessionManager.startArmedRace()
                        }
                        .zIndex(20)
                    }

                    // Controls bar (4 buttons - evenly distributed)
                    HStack(spacing: 0) {

                        Button {
                            onHomeTap()
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Home")

                        Button {
                            isRaceSetupPresented = true
                        } label: {
                            Image(systemName: "flag.checkered")
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Race")

                        Button {
                            onWeatherTap()
                        } label: {
                            Image(systemName: weatherSymbolName)
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Weather")

                        Button {
                            onSettingsTap()
                        } label: {
                            SignalBarsIcon(filledBars: gpsFilledBars)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .font(.title3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityLabel("Settings")
                    }

                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                    .foregroundStyle(.secondary)
                    .background(.ultraThinMaterial)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { controlsBarHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, newValue in
                                    controlsBarHeight = newValue
                                }
                        }
                    )

                }
            }
    #if DEBUG
    .onAppear {
        // Évite de recréer un timer si la vue réapparaît
        if simTimer != nil { return }

        simTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            simTick += 1

            // 1) Delta sinusoïdal (entre -1.5 et +1.5)
            let t = Double(simTick) * 0.25
            sessionManager.deltaToBestLap = 1.5 * sin(t)

            // 2) Secteurs fixes : jaune / vert / violet
            sessionManager.sectorStates = [.slower, .faster, .best]
        }
    }
    .onDisappear {
        simTimer?.invalidate()
        simTimer = nil
    }
    #endif
            .sheet(isPresented: $isRaceSetupPresented) {
                RaceSetupView(
                    initialMinimumPitSeconds: sessionManager.minimumPitSeconds,
                    initialDrivers: sessionManager.drivers
                ) { config in
                    sessionManager.armRaceStart(with: config)
                    isRaceSetupPresented = false
                }
                // Plein écran (ou quasi) -> le Form peut scroller même en paysage
                .presentationDetents([.fraction(0.98), .large])
                .presentationDragIndicator(.visible)

                // Important : évite que le drag de la sheet “vole” le geste de scroll
                .presentationContentInteraction(.scrolls)
            }
            .sheet(isPresented: $isDriverSheetPresented) {
                DriverPickerSheet(
                    drivers: sessionManager.drivers,
                    selected: sessionManager.selectedDriverName,
                    onSelect: { name in
                        sessionManager.selectDriver(name)
                        isDriverSheetPresented = false
                    }
                )
            }
            .onAppear {
                OrientationLock.current = .landscape
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onChange(of: sessionManager.lapFlash?.id) { _, _ in
                guard let flash = sessionManager.lapFlash else { return }
                activeLapFlash = flash

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // On évite d'effacer si un nouveau flash est arrivé entre-temps
                    if activeLapFlash?.id == flash.id {
                        activeLapFlash = nil
                    }
                }
            }
        }

        private var currentPitSeconds: TimeInterval {
            sessionManager.pitElapsedSeconds
        }

        private func formatPitTime(seconds: TimeInterval) -> String {
            let totalSeconds = max(0, Int(seconds.rounded(.down)))
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

        func formatStintTime(_ seconds: TimeInterval) -> String {
            let totalMinutes = max(0, Int(seconds) / 60)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60

            return String(format: "%d:%02d", hours, minutes)
        }

    private struct SignalBarsIcon: View {
        let filledBars: Int   // 0...3

        var body: some View {
            HStack(alignment: .bottom, spacing: 3) {
                bar(height: 10, filled: filledBars >= 1)
                bar(height: 14, filled: filledBars >= 2)
                bar(height: 18, filled: filledBars >= 3)
            }
            .frame(height: 20) // garde une hauteur stable
        }

        private func bar(height: CGFloat, filled: Bool) -> some View {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .frame(width: 5, height: height)
                .opacity(filled ? 1.0 : 0.25)
        }
    }

