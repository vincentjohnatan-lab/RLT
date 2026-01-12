//
//  SignUpView.swift
//  RaceLiveTelemetry
//
//  Created by Johnatan Vincent on 02/01/2026.
//

import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var session: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var nickname = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    TextField("", text: $nickname, prompt: Text("Nickname").foregroundStyle(.black.opacity(0.45)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)
                    
                    TextField("", text: $email, prompt: Text("Email").foregroundStyle(.black.opacity(0.45)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)

                    SecureField("", text: $password, prompt: Text("Password").foregroundStyle(.black.opacity(0.45)))
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)

                    SecureField("", text: $confirmPassword, prompt: Text("Confirm Password").foregroundStyle(.black.opacity(0.45)))
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }

                    Button {
                        errorMessage = nil
                        switch session.signUp(email: email, password: password, confirmPassword: confirmPassword, nickname: nickname) {
                        case .success:
                            dismiss()
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    } label: {
                        Text("Create the account")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Spacer(minLength: 0)
                }
                .padding(24)
            }
            .navigationTitle("Create an account")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Create an account")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(SessionManager())
}
