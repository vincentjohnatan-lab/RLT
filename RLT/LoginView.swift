// Gestion du log au début de la session

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionManager

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 18) {

                    Spacer(minLength: 0)

                    // Logo (même asset que HomeView)
                    Image("RLTLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: geo.size.width * 0.75,
                            maxHeight: geo.size.height * 0.22
                        )
                        .padding(.bottom, 8)

                    // Titre
                    Text("Connexion")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    // Champs
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.black)

                        SecureField("Mot de passe", text: $password)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: min(420, geo.size.width * 0.86))

                    // Erreur
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                    }

                    // Bouton "Se connecter" dans un rond blanc (rappel HomeView)
                    Button {
                        let ok = session.logIn(email: email, password: password)
                        if !ok {
                            errorMessage = "Identifiants invalides (mode démo)."
                        }
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 72, height: 72)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.black)
                            }

                            Text("Se connecter")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(SessionManager())
}
