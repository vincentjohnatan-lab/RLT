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
                    TextField("Nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.black)
                    
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

                    SecureField("Confirm Password", text: $confirmPassword)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    SignUpView()
        .environmentObject(SessionManager())
}
