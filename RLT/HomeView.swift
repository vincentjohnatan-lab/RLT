
import SwiftUI

struct HomeView: View {
    let onLiveTap: () -> Void
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                        Color.black.ignoresSafeArea()
                VStack(spacing: 24) {

                    // Logo – premier tiers de l’écran
                    Spacer(minLength: 0)

                    Image("RLTLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: geo.size.width * 1,
                            maxHeight: geo.size.height * 1
                        )

                    Spacer(minLength: 0)

                    // Boutons – ligne 1 (3)
                    HStack(spacing: 16) {
                        homeButton(title: "Live", systemImage: "bolt.fill", action: onLiveTap)
                        homeButton(title: "Track", systemImage: "map.fill")
                        homeButton(title: "GPS", systemImage: "location.fill")
                    }

                    // Boutons – ligne 2 (2)
                    HStack(spacing: 16) {
                        homeButton(title: "Settings", systemImage: "gearshape.fill")
                        homeButton(title: "Account", systemImage: "person.crop.circle")
                    }

                    Spacer(minLength: 20)
                }
                .padding(24)
            }
            .navigationBarHidden(true)
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
}

#Preview(traits: .portrait) {
    HomeView(onLiveTap: {})
}

