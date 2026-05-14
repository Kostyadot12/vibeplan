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
            VibePlanTheme.backgroundGradient.ignoresSafeArea()
            Color.white.opacity(0.4).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
                        serverSection
                        syncSection
                        Divider()
                        logoutSection
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { serverDraft = settings.backendURL.absoluteString }
    }

    private var header: some View {
        HStack {
            Text("Настройки")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.7), in: Circle())
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
                    Text(auth.user?.name.isEmpty == false ? auth.user!.name : (auth.user?.email ?? "—"))
                        .font(.system(size: 14, weight: .semibold))
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
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
        }
    }

    // MARK: – Server

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Сервер")
            VStack(alignment: .leading, spacing: 8) {
                TextField("http://82.38.68.48:4400", text: $serverDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13).monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))

                if let probeText {
                    Text(probeText)
                        .font(.system(size: 11))
                        .foregroundStyle(probeText.hasPrefix("✓") ? .green : .red)
                }

                HStack {
                    Button("Проверить") { Task { await probe() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                        .disabled(URL(string: serverDraft) == nil)
                    Button("Сохранить") {
                        if let url = URL(string: serverDraft) { settings.backendURL = url }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(VibePlanTheme.ink900, in: Capsule())
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
                } else if let last = sync.lastSyncAt {
                    Text("Последняя синхронизация: \(formatted(last))")
                        .foregroundStyle(VibePlanTheme.ink500)
                } else {
                    Text("Ещё не синхронизировались в этой сессии")
                        .foregroundStyle(VibePlanTheme.ink500)
                }
                if let err = sync.lastError {
                    Text("· \(err)")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: { Task { await sync.fullSync() } }) {
                    Label("Синк", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                .disabled(sync.isSyncing)
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

struct UserBadge: View {
    let user: UserDTO?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [VibePlanTheme.catWork, VibePlanTheme.catPersonal],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
    }

    private var initials: String {
        let name = (user?.name.isEmpty == false ? user!.name : user?.email) ?? "?"
        let parts = name.split(separator: name.contains(" ") ? " " : "@")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.map(String.init).joined().uppercased()
    }
}
