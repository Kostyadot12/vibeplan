import SwiftUI

struct LoginView: View {
    @Environment(AuthState.self)   private var auth
    @Environment(AppSettings.self) private var settings

    @State private var step: Step = .email
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var sending: Bool = false
    @State private var error: String?
    @State private var settingsOpen: Bool = false

    @FocusState private var focus: Field?

    enum Step { case email, code }
    enum Field: Hashable { case email, code }

    var body: some View {
        ZStack {
            VibePlanTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                wordmark

                card
                    .frame(width: 380)

                serverChip
            }
            .padding(40)
        }
        .sheet(isPresented: $settingsOpen) {
            ServerSheet().frame(minWidth: 380, minHeight: 220)
        }
        .onAppear { focus = .email }
    }

    private var wordmark: some View {
        VStack(spacing: 8) {
            Text("VibePlan")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(VibePlanTheme.ink900)
            Text("Планируйте вместе")
                .font(.system(size: 13, weight: .medium))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(VibePlanTheme.ink500)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                label("Email")
                TextField("you@team.io", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .focused($focus, equals: .email)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focus == .email ? VibePlanTheme.ink900.opacity(0.4) : Color.black.opacity(0.06)))
                    .disabled(step == .code)
                    .opacity(step == .code ? 0.7 : 1)
                    .submitLabel(.next)
                    .onSubmit { if step == .email { Task { await requestCode() } } }
            }

            if step == .code {
                VStack(alignment: .leading, spacing: 8) {
                    label("Код из письма")
                    TextField("6 цифр", text: $code)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .tracking(8)
                        .multilineTextAlignment(.center)
                        .focused($focus, equals: .code)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focus == .code ? VibePlanTheme.ink900.opacity(0.4) : Color.black.opacity(0.06)))
                        .submitLabel(.go)
                        .onSubmit { Task { await verify() } }
                        .onChange(of: code) { _, new in
                            // strip non-digits, cap at 6
                            let cleaned = String(new.filter(\.isNumber).prefix(6))
                            if cleaned != new { code = cleaned }
                        }
                }
            }

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).lineLimit(3)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            actionButton

            if step == .code {
                Button("Назад к email") {
                    step = .email
                    code = ""
                    error = nil
                    focus = .email
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VibePlanTheme.ink500)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.7)))
        .shadow(color: Color(hex: 0x3C3258, alpha: 0.18), radius: 24, x: 0, y: 10)
    }

    private var actionButton: some View {
        Button(action: { Task { step == .email ? await requestCode() : await verify() } }) {
            HStack(spacing: 8) {
                if sending {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: step == .email ? "envelope.fill" : "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(step == .email ? "Получить код" : "Войти")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(VibePlanTheme.ink900, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(disableAction)
        .opacity(disableAction ? 0.5 : 1)
    }

    private var serverChip: some View {
        Button(action: { settingsOpen = true }) {
            HStack(spacing: 6) {
                Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                Text("Сервер: ")
                    .foregroundStyle(VibePlanTheme.ink500)
                Text(settings.backendURL.host ?? settings.backendURL.absoluteString)
                    .foregroundStyle(VibePlanTheme.ink700)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(VibePlanTheme.ink500)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.white.opacity(0.55), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var disableAction: Bool {
        if sending { return true }
        if step == .email { return !isValidEmail(email) }
        return code.count != 6
    }

    // MARK: – Actions

    private func requestCode() async {
        guard isValidEmail(email) else { return }
        sending = true; error = nil; defer { sending = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: nil)
            try await client.requestCode(email: email.trimmingCharacters(in: .whitespaces).lowercased())
            step = .code
            focus = .code
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func verify() async {
        guard code.count == 6 else { return }
        sending = true; error = nil; defer { sending = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: nil)
            let result = try await client.verify(
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                code:  code
            )
            auth.setLoggedIn(token: result.token, user: result.user)
        } catch APIError.http(401, let body) {
            self.error = body.contains("истёк") ? "Срок действия кода истёк. Получите новый."
                       : body.contains("Неверный")  ? "Неверный код"
                       : "Не получилось войти. Запросите новый код."
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(VibePlanTheme.ink500)
    }
}

// MARK: – Server (URL) sheet — used both from login and from main settings

struct ServerSheet: View {
    @Environment(\.dismiss)        private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var raw: String = ""
    @State private var probing: Bool = false
    @State private var probeResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Адрес сервера")
                .font(.system(size: 16, weight: .semibold))

            TextField("http://82.38.68.48:4400", text: $raw)
                .textFieldStyle(.plain)
                .font(.system(size: 14).monospacedDigit())
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))

            if let probeResult {
                Text(probeResult)
                    .font(.system(size: 12))
                    .foregroundStyle(probeResult.hasPrefix("✓") ? .green : .red)
            }

            HStack {
                Button("Проверить") { Task { await probe() } }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                    .disabled(probing || URL(string: raw) == nil)

                Spacer()

                Button("Отмена") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.1)))

                Button("Сохранить") {
                    if let url = URL(string: raw) { settings.backendURL = url }
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(VibePlanTheme.ink900, in: Capsule())
                .disabled(URL(string: raw) == nil)
            }
        }
        .padding(20)
        .onAppear { raw = settings.backendURL.absoluteString }
    }

    private func probe() async {
        guard let baseURL = URL(string: raw),
              let url = URL(string: "health", relativeTo: baseURL) else { return }
        probing = true; defer { probing = false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                probeResult = "✓ Сервер ответил (HTTP \(http.statusCode))"
            } else {
                probeResult = "✗ Сервер ответил, но не 2xx"
            }
        } catch {
            probeResult = "✗ \(error.localizedDescription)"
        }
    }
}
