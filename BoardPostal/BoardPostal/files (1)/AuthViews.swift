import SwiftUI

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
    @Binding var showRegister: Bool

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero header
                heroHeader

                // Form
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        BPTextField(
                            label: "Email",
                            placeholder: "you@example.com",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )
                        BPTextField(
                            label: "Password",
                            placeholder: "Your password",
                            text: $password,
                            isSecure: true
                        )
                    }

                    if let error = authStore.errorMessage {
                        errorBanner(error)
                    }

                    BPButton(
                        "Sign in",
                        style: .primary,
                        isLoading: authStore.isLoading
                    ) {
                        Task { await authStore.login(email: email, password: password) }
                    }

                    BPDivider()

                    // Switch to register
                    HStack(spacing: 4) {
                        Text("New to board\\_postal?")
                            .font(.bpCallout)
                            .foregroundColor(.bpTextSecondary)

                        Button("Create account") {
                            showRegister = true
                        }
                        .font(.bpCallout)
                        .foregroundColor(.bpCobalt)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
        }
        .background(Color.bpBackground)
        .navigationBarHidden(true)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero header
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.bpPrimaryDeep)
                .frame(height: 240)

            VStack(alignment: .leading, spacing: 8) {
                ItalicLastWord(
                    text: "board_postal",
                    font: .bpDisplay,
                    baseColor: .white
                )

                ItalicLastWord(
                    text: "The travel magazine you make yourself.",
                    font: .bpCallout,
                    baseColor: .bpAzure
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Error banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.bpError)
                .font(.system(size: 16))

            Text(message)
                .font(.bpCallout)
                .foregroundColor(.bpError)

            Spacer()
        }
        .padding(14)
        .background(Color.bpError.opacity(0.08))
        .overlay(
            Rectangle()
                .stroke(Color.bpError.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - RegisterView

struct RegisterView: View {
    @EnvironmentObject var authStore: AuthStore
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Compact header
                compactHeader

                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        BPTextField(
                            label: "Full name",
                            placeholder: "Your name",
                            text: $fullName
                        )
                        BPTextField(
                            label: "Email",
                            placeholder: "you@example.com",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )
                        BPTextField(
                            label: "Password",
                            placeholder: "Choose a password",
                            text: $password,
                            isSecure: true
                        )
                    }

                    if let error = authStore.errorMessage {
                        errorBanner(error)
                    }

                    BPButton(
                        "Create account",
                        style: .primary,
                        isLoading: authStore.isLoading
                    ) {
                        Task {
                            await authStore.register(
                                email: email,
                                password: password,
                                fullName: fullName
                            )
                        }
                    }

                    // Terms note
                    Text("By creating an account you agree to board\\_postal's terms and privacy policy.")
                        .font(.bpCaption)
                        .foregroundColor(.bpTextMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
        }
        .background(Color.bpBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.bpInk)
                }
            }
        }
    }

    private var compactHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.bpPrimaryDeep)
                .frame(height: 140)

            VStack(alignment: .leading, spacing: 4) {
                Text("Start your journey.")
                    .font(.bpTitle)
                    .foregroundColor(.white)

                Text("Plan it. Live it. Remember it forever.")
                    .font(.bpCallout)
                    .foregroundColor(.bpAzure)
                    .italic()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.bpError)
                .font(.system(size: 16))

            Text(message)
                .font(.bpCallout)
                .foregroundColor(.bpError)

            Spacer()
        }
        .padding(14)
        .background(Color.bpError.opacity(0.08))
        .overlay(
            Rectangle()
                .stroke(Color.bpError.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview("Login") {
    AuthFlowView()
        .environmentObject(AuthStore())
}
