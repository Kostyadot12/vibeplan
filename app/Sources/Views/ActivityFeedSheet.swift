import SwiftUI

struct ActivityFeedSheet: View {
    @Environment(\.dismiss)         private var dismiss
    @Environment(ActivityFeed.self) private var feed
    @Environment(SpacesRoster.self) private var spacesRoster
    @Environment(TeamRoster.self)   private var roster

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F4).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                if feed.events.isEmpty && !feed.loading {
                    emptyState
                } else {
                    list
                }
            }
        }
        .preferredColorScheme(.light)
        .task { await feed.refresh(scope: spacesRoster.scope) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Активность")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink900)
                Text(scopeName)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(VibePlanTheme.ink500)
            }
            Spacer()
            Button(action: { Task { await feed.refresh(scope: spacesRoster.scope) } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .frame(width: 28, height: 28)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Color.black.opacity(0.06)))
            }
            .buttonStyle(.plain)
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

    private var scopeName: String {
        switch spacesRoster.scope {
        case .personal: return "Личные"
        case .space(let id):
            return spacesRoster.space(byId: id)?.name ?? "Пространство"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 24, weight: .light))
                .foregroundStyle(VibePlanTheme.ink400)
            Text("Пока пусто")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VibePlanTheme.ink700)
            Text("Когда команда создаёт задачи и пишет комментарии — появится тут.")
                .font(.system(size: 12))
                .foregroundStyle(VibePlanTheme.ink500)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(feed.events) { e in
                    eventRow(e)
                }
            }
            .padding(20)
        }
    }

    private func eventRow(_ e: ActivityEventDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            actorBadge(for: e)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(actorName(e.actorId))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Text(e.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(VibePlanTheme.ink700)
                }
                Text(timeString(e.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(VibePlanTheme.ink400)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.05)))
    }

    private func actorBadge(for e: ActivityEventDTO) -> some View {
        let info = actorInfo(e.actorId)
        return AvatarBadge(name: info.name, email: info.email, size: 24, avatarPath: info.avatarPath)
    }

    private func actorInfo(_ id: String?) -> (name: String, email: String, avatarPath: String?) {
        guard let id else { return ("?", "", nil) }
        if let m = roster.member(byId: id) { return (m.name, m.email, m.avatarUrl) }
        for s in spacesRoster.spaces {
            if let m = s.members.first(where: { $0.userId == id }) {
                return (m.name, m.email, m.avatarUrl)
            }
        }
        return ("?", "", nil)
    }

    private func actorName(_ id: String?) -> String {
        let info = actorInfo(id)
        return info.name.isEmpty ? (info.email.isEmpty ? "Кто-то" : info.email) : info.name
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
}
