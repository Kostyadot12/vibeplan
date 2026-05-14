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
            backgroundCanvas
            content
        }
        .sheet(isPresented: $settingsOpen) {
            ServerSheet().frame(minWidth: 380, minHeight: 240)
        }
        .onAppear { focus = .email }
    }

    // MARK: – Background

    private var backgroundCanvas: some View {
        ZStack {
            // Warm cream-to-lavender base
            LinearGradient(
                colors: [
                    Color(hex: 0xF7F2EB),
                    Color(hex: 0xF0E8F3),
                    Color(hex: 0xE7EFF7)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Two soft color blobs for depth
            RadialGradient(
                colors: [VibePlanTheme.catPersonal.opacity(0.32), .clear],
                center: .topLeading, startRadius: 30, endRadius: 460
            )
            RadialGradient(
                colors: [VibePlanTheme.catWork.opacity(0.28), .clear],
                center: .bottomTrailing, startRadius: 60, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    // MARK: – Content

    private var content: some View {
        VStack(spacing: 32) {
            brandMark
            formCard
                .frame(maxWidth: 380)
            serverChip
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 50)
    }

    private var brandMark: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x2D2646), Color(hex: 0x0F0F12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 76, height: 76)
                    .shadow(color: Color(hex: 0x3C3258, alpha: 0.32), radius: 18, x: 0, y: 10)

                // Mini calendar-grid glyph (mirrors AppIcon-Source)
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        glyphCell(filled: false)
                        glyphCell(filled: false)
                        glyphCell(filled: false)
                    }
                    HStack(spacing: 5) {
                        glyphCell(filled: false)
                        glyphCell(filled: true)
                        glyphCell(filled: false)
                    }
                    HStack(spacing: 5) {
                        glyphCell(filled: false)
                        glyphCell(filled: false)
                        glyphCell(filled: false)
                    }
                }
            }

            VStack(spacing: 4) {
                Text("VibePlan")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink900)
                Text("планируйте вместе")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(VibePlanTheme.ink500)
            }
        }
    }

    private func glyphCell(filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(filled ? Color.white : Color.white.opacity(0.0))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(filled ? 0 : 0.85), lineWidth: 1.4)
            )
            .frame(width: 11, height: 11)
    }

    // MARK: – Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            emailField

            if step == .code {
                codeField
            }

            if let error {
                errorBanner(error)
            }

            actionButton

            if step == .code {
                Button("← назад к email") {
                    step = .email
                    code = ""
                    error = nil
                    focus = .email
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VibePlanTheme.ink500)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05))
        )
        .shadow(color: Color(hex: 0x3C3258, alpha: 0.18), radius: 30, x: 0, y: 14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 7) {
            label("Email")
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink400)
                TextField("you@team.io", text: $email)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($focus, equals: .email)
                    .disabled(step == .code)
                    .submitLabel(.next)
                    .onSubmit { if step == .email { Task { await requestCode() } } }
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(step == .code ? Color(hex: 0xF5F4F8) : Color(hex: 0xFAFAFB))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(focus == .email ? VibePlanTheme.ink900 : Color.black.opacity(0.08),
                            lineWidth: focus == .email ? 1.5 : 1)
            )
        }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                label("Код из письма")
                Spacer()
                Text("\(code.count)/6")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(VibePlanTheme.ink400)
            }
            TextField("· · · · · ·", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .tracking(10)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .code)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(hex: 0xFAFAFB))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(focus == .code ? VibePlanTheme.ink900 : Color.black.opacity(0.08),
                                lineWidth: focus == .code ? 1.5 : 1)
                )
                .submitLabel(.go)
                .onSubmit { Task { await verify() } }
                .onChange(of: code) { _, new in
                    let cleaned = String(new.filter(\.isNumber).prefix(6))
                    if cleaned != new { code = cleaned }
                    if cleaned.count == 6 { Task { await verify() } }   // auto-submit
                }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .opacity
        ))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(msg)
                .font(.system(size: 12))
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.78, green: 0.20, blue: 0.20).opacity(0.08))
        )
    }

    private var actionButton: some View {
        Button(action: { Task { step == .email ? await requestCode() : await verify() } }) {
            HStack(spacing: 8) {
                if sending {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: step == .email ? "arrow.right" : "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(step == .email ? "Получить код" : "Войти")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x2D2646), Color(hex: 0x0F0F12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(disableAction)
        .opacity(disableAction ? 0.45 : 1)
    }

    private var serverChip: some View {
        Button(action: { settingsOpen = true }) {
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("Сервер:")
                    .foregroundStyle(VibePlanTheme.ink500)
                Text(settings.backendURL.host ?? settings.backendURL.absoluteString)
                    .foregroundStyle(VibePlanTheme.ink900)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.85))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.06))
            )
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
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
            withAnimation(.easeOut(duration: 0.18)) { step = .code }
            try? await Task.sleep(nanoseconds: 200_000_000)
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
            self.error = body.contains("истёк") ? "Срок действия кода истёк. Запросите новый."
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
            .tracking(0.7)
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
                probeResult = "✗ Сервер не вернул 2xx"
            }
        } catch {
            probeResult = "✗ \(error.localizedDescription)"
        }
    }
}
