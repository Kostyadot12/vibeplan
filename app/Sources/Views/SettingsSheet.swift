import SwiftUI
import SwiftData

struct SettingsSheet: View {
    @Environment(\.dismiss)        private var dismiss
    @Environment(AuthState.self)   private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(SyncEngine.self)  private var sync

    @State private var serverDraft: String = ""
    @State private var probeText: String?

    var body: some View {
        ZStack {
            // Solid soft cream — no material/blend tricks; reads identical
            // in any system appearance.
            Color(hex: 0xFAF8F4).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
                        syncSection
                        Divider()
                        logoutSection
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { serverDraft = settings.backendURL.absoluteString }
    }

    private var header: some View {
        HStack {
            Text("Настройки")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VibePlanTheme.ink900)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    // MARK: – Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Аккаунт")
            HStack(spacing: 12) {
                UserBadge(user: auth.user, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Text(auth.user?.email ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(VibePlanTheme.ink500)
                }
                Spacer()
                if auth.user?.role == "admin" {
                    Text("Admin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(VibePlanTheme.ink900, in: Capsule())
                }
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
        }
    }

    private var displayName: String {
        if let name = auth.user?.name, !name.isEmpty { return name }
        return auth.user?.email ?? "—"
    }

    // MARK: – Server

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Сервер")
            VStack(alignment: .leading, spacing: 8) {
                TextField("http://82.38.68.48:4400", text: $serverDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))

                if let probeText {
                    Text(probeText)
                        .font(.system(size: 11))
                        .foregroundStyle(probeText.hasPrefix("✓")
                                         ? Color(red: 0.20, green: 0.58, blue: 0.30)
                                         : Color(red: 0.78, green: 0.20, blue: 0.20))
                }

                HStack(spacing: 8) {
                    Button(action: { Task { await probe() } }) {
                        Text("Проверить")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VibePlanTheme.ink900)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(Color.black.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(URL(string: serverDraft) == nil)

                    Button(action: {
                        if let url = URL(string: serverDraft) { settings.backendURL = url }
                    }) {
                        Text("Сохранить")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(VibePlanTheme.ink900, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(URL(string: serverDraft) == nil
                              || URL(string: serverDraft)?.absoluteString == settings.backendURL.absoluteString)
                    Spacer()
                }
            }
        }
    }

    // MARK: – Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Синхронизация")
            HStack {
                if sync.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("Синхронизация…")
                        .foregroundStyle(VibePlanTheme.ink700)
                } else if let last = sync.lastSyncAt {
                    Text("Последняя синхронизация: \(formatted(last))")
                        .foregroundStyle(VibePlanTheme.ink500)
                } else {
                    Text("Ещё не синхронизировались в этой сессии")
                        .foregroundStyle(VibePlanTheme.ink500)
                }
                if let err = sync.lastError {
                    Text("· \(err)")
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: { Task { await sync.fullSync() } }) {
                    Label("Синк", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(VibePlanTheme.ink900)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(sync.isSyncing)
                .keyboardShortcut("r", modifiers: [.command])
            }
            .font(.system(size: 12))
        }
    }

    // MARK: – Logout

    private var logoutSection: some View {
        Button(action: { auth.logout(); dismiss() }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                Text("Выйти")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.red.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: – helpers

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(VibePlanTheme.ink500)
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func probe() async {
        guard let baseURL = URL(string: serverDraft),
              let url = URL(string: "health", relativeTo: baseURL) else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                probeText = "✓ Сервер ответил (HTTP \(http.statusCode))"
            } else {
                probeText = "✗ Сервер не вернул 2xx"
            }
        } catch {
            probeText = "✗ \(error.localizedDescription)"
        }
    }
}

/// Convenience wrapper around `AvatarBadge` taking a `UserDTO?`.
struct UserBadge: View {
    let user: UserDTO?
    let size: CGFloat

    var body: some View {
        AvatarBadge(
            name: user?.name ?? "",
            email: user?.email ?? "",
            size: size,
            avatarPath: user?.avatarUrl
        )
    }
}
