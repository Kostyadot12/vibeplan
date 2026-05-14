import SwiftUI

enum SpaceSheetMode: Hashable {
    case create
    case manage(spaceId: String)
}

/// Sheet for creating a new space OR managing an existing one
/// (rename, recolor, invite/remove members, leave/delete).
struct SpaceSheet: View {
    let mode: SpaceSheetMode

    @Environment(\.dismiss)         private var dismiss
    @Environment(AuthState.self)    private var auth
    @Environment(AppSettings.self)  private var settings
    @Environment(SpacesRoster.self) private var roster

    @State private var name: String = ""
    @State private var color: PlanCategory = .work
    @State private var inviteEmail: String = ""
    @State private var saving: Bool = false
    @State private var inviting: Bool = false
    @State private var error: String?
    @State private var inviteHint: String?

    private var current: SpaceDTO? {
        if case .manage(let id) = mode { return roster.space(byId: id) }
        return nil
    }

    private var isOwner: Bool {
        guard let s = current, let me = auth.user?.id else { return false }
        return s.ownerId == me
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F4).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        nameSection
                        colorSection
                        if !isCreate {
                            membersSection
                            inviteSection
                            Divider().padding(.vertical, 4)
                            destructiveSection
                        }
                        if let error {
                            errorBanner(error)
                        }
                    }
                    .padding(20)
                }
                Divider().opacity(0.4)
                footer
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.tintBackground).frame(width: 32, height: 32)
                Image(systemName: isCreate ? "plus" : "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color.color)
            }
            Text(isCreate ? "Новое пространство" : "Пространство")
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

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Название")
            TextField("", text: $name,
                      prompt: Text("Например: Команда продукта").foregroundStyle(VibePlanTheme.ink400))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VibePlanTheme.ink900)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.black.opacity(0.08)))
                .disabled(!isCreate && !isOwner)
                .opacity(!isCreate && !isOwner ? 0.7 : 1)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Цвет")
            HStack(spacing: 8) {
                ForEach(PlanCategory.allCases) { c in
                    Button(action: { color = c }) {
                        Circle()
                            .fill(c.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(color == c ? VibePlanTheme.ink900 : Color.black.opacity(0.06),
                                                lineWidth: color == c ? 2 : 1)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(color == c ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isCreate && !isOwner)
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Участники")
                Spacer()
                if let s = current {
                    Text("\(s.members.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink400)
                }
            }
            VStack(spacing: 6) {
                ForEach(current?.members ?? []) { m in
                    HStack(spacing: 10) {
                        AvatarBadge(name: m.name, email: m.email, size: 28, avatarPath: m.avatarUrl)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name.isEmpty ? m.email : m.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(VibePlanTheme.ink900)
                            if !m.name.isEmpty {
                                Text(m.email)
                                    .font(.system(size: 11))
                                    .foregroundStyle(VibePlanTheme.ink500)
                            }
                        }
                        Spacer()
                        if m.role == "owner" {
                            Text("Владелец")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(VibePlanTheme.ink900, in: Capsule())
                        } else if isOwner {
                            Button(action: { Task { await removeMember(m.userId) } }) {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(VibePlanTheme.ink400)
                            }
                            .buttonStyle(.plain)
                            .help("Убрать из пространства")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06)))
                }
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Пригласить по email")
            HStack(spacing: 8) {
                TextField("", text: $inviteEmail,
                          prompt: Text("друг@team.io").foregroundStyle(VibePlanTheme.ink400))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink900)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
                    .disabled(!isOwner)

                Button(action: { Task { await invite() } }) {
                    HStack(spacing: 6) {
                        if inviting { ProgressView().controlSize(.small).tint(.white) }
                        Text("Пригласить")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(VibePlanTheme.ink900, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isOwner || !isValidEmail(inviteEmail) || inviting)
                .opacity(isOwner && isValidEmail(inviteEmail) && !inviting ? 1 : 0.5)
            }
            if let inviteHint {
                Text(inviteHint)
                    .font(.system(size: 12))
                    .foregroundStyle(inviteHint.hasPrefix("✓")
                                     ? Color(red: 0.20, green: 0.58, blue: 0.30)
                                     : VibePlanTheme.ink500)
            }
            if !isOwner {
                Text("Только владелец пространства может приглашать.")
                    .font(.system(size: 11))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
        }
    }

    private var destructiveSection: some View {
        HStack {
            if isOwner {
                Button(action: { Task { await deleteSpace() } }) {
                    Label("Удалить пространство", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.red.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if let me = auth.user?.id, current?.members.contains(where: { $0.userId == me }) == true {
                Button(action: { Task { await leaveSpace() } }) {
                    Label("Покинуть", systemImage: "arrow.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.red.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
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
                    Text(isCreate ? "Создать" : "Сохранить")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(VibePlanTheme.ink900, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving
                      || (!isCreate && !isOwner))
            .opacity((name.trimmingCharacters(in: .whitespaces).isEmpty || (!isCreate && !isOwner)) ? 0.5 : 1)
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
        if let s = current {
            name = s.name
            color = PlanCategory(rawValue: s.color) ?? .work
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        saving = true; error = nil; defer { saving = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            switch mode {
            case .create:
                let s = try await client.createSpace(name: trimmed, color: color.rawValue)
                roster.upsert(s)
                roster.scope = .space(s.id)
            case .manage(let id):
                let s = try await client.updateSpace(
                    id: id,
                    patch: SpacePatchPayload(name: trimmed, color: color.rawValue)
                )
                roster.upsert(s)
            }
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func invite() async {
        guard case .manage(let id) = mode else { return }
        let email = inviteEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard isValidEmail(email) else { return }
        inviting = true; inviteHint = nil; error = nil; defer { inviting = false }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            let result = try await client.inviteToSpace(spaceId: id, email: email)
            if let s = result {
                roster.upsert(s)
                inviteHint = "✓ \(email) добавлен в пространство"
            } else {
                inviteHint = "✓ \(email) приглашён — попадёт в команду при первом логине"
            }
            inviteEmail = ""
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func removeMember(_ userId: String) async {
        guard case .manage(let id) = mode else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            try await client.removeMember(spaceId: id, userId: userId)
            // Refresh from server to reflect new member list
            await roster.refresh()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func leaveSpace() async {
        guard case .manage(let id) = mode, let me = auth.user?.id else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            try await client.removeMember(spaceId: id, userId: me)
            roster.remove(spaceId: id)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func deleteSpace() async {
        guard case .manage(let id) = mode else { return }
        do {
            let client = APIClient(baseURL: settings.backendURL, token: auth.token)
            try await client.deleteSpace(id: id)
            roster.remove(spaceId: id)
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.contains("@") && t.contains(".") && t.count >= 5
    }
}
