import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Profile view. If `userId == auth.user?.id` → editable (rename + avatar
/// upload). Otherwise read-only — used when you click on someone else's
/// avatar in a card to see who created/owns the task.
struct ProfileSheet: View {
    let userId: String

    @Environment(\.dismiss)         private var dismiss
    @Environment(AuthState.self)    private var auth
    @Environment(AppSettings.self)  private var settings
    @Environment(TeamRoster.self)   private var roster
    @Environment(SpacesRoster.self) private var spacesRoster

    @State private var name: String = ""
    @State private var avatarUrl: String? = nil
    @State private var saving: Bool = false
    @State private var uploading: Bool = false
    @State private var error: String?
    @State private var loaded: Bool = false

    private var isSelf: Bool { userId == auth.user?.id }

    private var displayMember: (email: String, name: String, role: String?, avatarUrl: String?)? {
        // Try TeamRoster, then SpacesRoster members, then auth.user.
        if let m = roster.member(byId: userId) {
            return (m.email, m.name, m.role, m.avatarUrl)
        }
        for s in spacesRoster.spaces {
            if let m = s.members.first(where: { $0.userId == userId }) {
                return (m.email, m.name, m.role, m.avatarUrl)
            }
        }
        if let u = auth.user, u.id == userId {
            return (u.email, u.name, u.role, u.avatarUrl)
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F4).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        avatarSection
                        nameSection
                        emailSection
                        if let role = displayMember?.role {
                            badgeSection(role: role)
                        }
                        if let error {
                            errorBanner(error)
                        }
                    }
                    .padding(20)
                }
                if isSelf {
                    Divider().opacity(0.4)
                    footer
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack {
            Text(isSelf ? "Мой профиль" : "Профиль")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VibePlanTheme.ink900)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 28, height: 28)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var avatarSection: some View {
        HStack {
            Spacer()
            VStack(spacing: 14) {
                AvatarBadge(
                    name: displayMember?.name ?? "",
                    email: displayMember?.email ?? "",
                    size: 96,
                    avatarPath: avatarUrl
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelf {
                        Button(action: pickAndUpload) {
                            ZStack {
                                Circle().fill(VibePlanTheme.ink900).frame(width: 30, height: 30)
                                if uploading {
                                    ProgressView().controlSize(.small).tint(.white)
                                } else {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)
                    }
                }
                if isSelf && avatarUrl != nil {
                    Button(action: { Task { await clearAvatar() } }) {
                        Text("Убрать фото")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(VibePlanTheme.ink500)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Имя")
            if isSelf {
                TextField("", text: $name,
                          prompt: Text("Как тебя зовут?").foregroundStyle(VibePlanTheme.ink400))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.08)))
            } else {
                Text(displayMember?.name.isEmpty == false ? displayMember!.name : "—")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.06)))
            }
        }
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Email")
            Text(displayMember?.email ?? "—")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(VibePlanTheme.ink700)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xF1EEEA), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private func badgeSection(role: String) -> some View {
        HStack(spacing: 8) {
            if role == "admin" || role == "owner" {
                Text(role == "admin" ? "Администратор" : "Владелец пространства")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(VibePlanTheme.ink900, in: Capsule())
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: { dismiss() }) {
                Text("Отмена")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Button(action: { Task { await save() } }) {
                HStack(spacing: 6) {
                    if saving { ProgressView().controlSize(.small).tint(.white) }
                    Text("Сохранить")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(VibePlanTheme.ink900, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(VibePlanTheme.ink500)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(msg).lineLimit(3)
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: – Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if isSelf, let u = auth.user {
            name = u.name
            avatarUrl = u.avatarUrl
        } else if let m = displayMember {
            name = m.name
            avatarUrl = m.avatarUrl
        }
    }

    private func save() async {
        guard isSelf else { return }
        saving = true; error = nil; defer { saving = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let updated = try await client.updateMe(
                name: name.trimmingCharacters(in: .whitespaces),
                avatarUrl: nil   // not patched here — use upload/clear actions
            )
            auth.setLoggedIn(token: auth.token!, user: updated)
            await roster.refresh()
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func pickAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            uploading = true; error = nil; defer { uploading = false }
            do {
                let data = try Data(contentsOf: url)
                let mime = url.pathExtension.lowercased() == "png"  ? "image/png"
                         : url.pathExtension.lowercased() == "gif"  ? "image/gif"
                         : url.pathExtension.lowercased() == "webp" ? "image/webp"
                         : "image/jpeg"
                let client = APIClient(baseURL: settings.backendURL, token: auth.token)
                let updated = try await client.uploadAvatar(imageData: data, mimeType: mime)
                avatarUrl = updated.avatarUrl
                auth.setLoggedIn(token: auth.token!, user: updated)
                await roster.refresh()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
        }
    }

    private func clearAvatar() async {
        guard isSelf else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let updated = try await client.updateMe(name: nil, avatarUrl: .some(nil))
            avatarUrl = nil
            auth.setLoggedIn(token: auth.token!, user: updated)
            await roster.refresh()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
