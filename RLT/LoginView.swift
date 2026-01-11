// Gestion du log au début de la session

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionManager

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSignUpPresented = false

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
                            maxWidth: geo.size.width * 1,
                            maxHeight: geo.size.height * 1
                        )
                        .padding(.bottom, 8)

                    // Titre
                    Text("LogIn")
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

                        SecureField("Password", text: $password)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .sheet(isPresented: $isSignUpPresented) {
                        SignUpView()
                            .environmentObject(session)
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
                            errorMessage = nil
                            switch session.logIn(email: email, password: password) {
                            case .success:
                                break
                            case .failure(let err):
                                errorMessage = err.localizedDescription
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

                            Text("get connected")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    
                    Button {
                        isSignUpPresented = true
                    } label: {
                        Text("Create an account")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.9))
                            .underline()
                            .padding(.top, 10)
                    }
                    .buttonStyle(.plain)

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
