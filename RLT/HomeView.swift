import SwiftUI

struct HomeView: View {
    let onLiveTap: () -> Void
    let onDemoTap: () -> Void
    @EnvironmentObject var session: SessionManager
    @State private var isAccountSheetPresented = false
    @State private var isSettingsSheetPresented = false
    @State private var isGPSSheetPresented = false
    @State private var isTracksSheetPresented = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack {
                        HStack {
                            Spacer()

                            Button(action: onDemoTap) {
                                Text("DEMO")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 14)
                            .padding(.trailing, 14)
                        }

                        Spacer()
                    }

                    VStack(spacing: 24) {

                        Spacer(minLength: 0)

                        Image("RLTLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: geo.size.width * 1,
                                maxHeight: geo.size.height * 1
                            )

                        Spacer(minLength: 0)

                        HStack(spacing: 16) {
                            homeButton(title: "Race", systemImage: "flag.checkered", action: onLiveTap)
                            homeButton(title: "Track", systemImage: "map.fill") {
                                isTracksSheetPresented = true
                            }
                            homeButton(title: "GPS", systemImage: "location.fill") {
                                isGPSSheetPresented = true
                            }
                        }

                        HStack(spacing: 16) {
                            homeButton(title: "Settings", systemImage: "gearshape.fill") {
                                isSettingsSheetPresented = true
                            }
                            homeButton(title: "Account", systemImage: "person.crop.circle") {
                                isAccountSheetPresented = true
                            }
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(24)
                }
                .navigationBarHidden(true)
            }
            .sheet(isPresented: $isAccountSheetPresented) {
                AccountView()
                    .environmentObject(session)
            }
            .sheet(isPresented: $isSettingsSheetPresented) {
                SettingsView(onClose: { isSettingsSheetPresented = false })
                    .environmentObject(session)
            }
            .sheet(isPresented: $isGPSSheetPresented) {
                GPSView(onClose: { isGPSSheetPresented = false })
            }
            .sheet(isPresented: $isTracksSheetPresented) {
                TracksView(onClose: { isTracksSheetPresented = false })
            }
            .onAppear {
                OrientationLock.current = .portrait
            }
        }
    }

    private func homeButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)

                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.black)
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private struct AccountView: View {
        @EnvironmentObject var session: SessionManager
        @Environment(\.dismiss) private var dismiss
        @State private var isLogoutAlertPresented = false

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        Button(role: .destructive) {
                            isLogoutAlertPresented = true
                        } label: {
                            Text("Logout")
                        }
                    }
                }
                .navigationTitle("Account")
            }
            .alert("Get deconnected ?", isPresented: $isLogoutAlertPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    session.logOut()
                    dismiss()
                }
            } message: {
                Text("You will be redirected to the authentification page.")
            }
        }
    }
}

struct GPSView: View {
    let onClose: () -> Void

    @EnvironmentObject var raceBoxGPS: RaceBoxGPSManager

    var body: some View {
        NavigationStack {
            List {
                Section("RaceBox Mini") {
                    Button("Scan Launch") {
                        raceBoxGPS.start()
                    }

                    Button("Stop") {
                        raceBoxGPS.stop()
                    }
                    .foregroundStyle(.red)
                }

                Section("Status") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                    if let b = raceBoxGPS.batteryPercent {
                        if raceBoxGPS.isCharging == true {
                            Text("Battery: \(b)% (charging)")
                        } else {
                            Text("Battery: \(b)%")
                        }
                    } else {
                        Text("Battery: --")
                    }

                    if let v = raceBoxGPS.speedKmh {
                        Text(String(format: "Speed: %.1f km/h", v))
                    }
                    if let s = raceBoxGPS.satellites {
                        Text("Satellites: \(s)")
                    }
                    if let h = raceBoxGPS.hdop {
                        Text(String(format: "HDOP: %.1f", h))
                    }
                    if let lat = raceBoxGPS.latitude, let lon = raceBoxGPS.longitude {
                        Text(String(format: "Lat/Lon: %.6f, %.6f", lat, lon))
                    }
                    if let h = raceBoxGPS.headingDeg {
                        Text(String(format: "Heading: %.1f°", h))
                    }
                    if let a = raceBoxGPS.altitudeM {
                        Text(String(format: "Alt: %.1f m", a))
                    }
                }
            }
            .navigationTitle("GPS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Label("Retour", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private var statusText: String {
        switch raceBoxGPS.state {
        case .idle: return "Idle"
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .connected(let name): return "Connected: \(name)"
        case .failed(let msg): return "Error: \(msg)"
        case .bluetoothOff: return "Bluetooth OFF"
        }
    }
}
