import SwiftUI

/// Mandatory update modal — cannot be dismissed. The only way out is to
/// install the update or quit the app from the menu/Cmd+Q.
struct UpdateSheet: View {
    let release: ReleaseInfo

    @Environment(Updater.self)        private var updater
    @Environment(UpdateChecker.self)  private var checker

    var body: some View {
        ZStack {
            Color(hex: 0xFAF8F4).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !release.notes.isEmpty {
                            notesBlock
                        } else {
                            Text("Без описания изменений.")
                                .font(.system(size: 12))
                                .foregroundStyle(VibePlanTheme.ink500)
                        }
                    }
                    .padding(20)
                }

                Divider().opacity(0.4)
                footer
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(true)   // нельзя закрыть свайпом / Esc
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x2D2646), Color(hex: 0x0F0F12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Доступно обновление")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(VibePlanTheme.ink500)
                HStack(spacing: 8) {
                    Text("VibePlan \(release.version)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(VibePlanTheme.ink900)
                    Text("·")
                        .foregroundStyle(VibePlanTheme.ink400)
                    Text("сейчас \(checker.current)")
                        .font(.system(size: 12))
                        .foregroundStyle(VibePlanTheme.ink500)
                        .monospacedDigit()
                }
            }
            Spacer()
            Text(sizeString)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(VibePlanTheme.ink500)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.06)))
        }
        .padding(20)
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что нового")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6).textCase(.uppercase)
                .foregroundStyle(VibePlanTheme.ink500)
            // Plain-text rendering for safety; markdown bullet lines look
            // OK as-is for now.
            Text(release.notes)
                .font(.system(size: 13))
                .foregroundStyle(VibePlanTheme.ink800)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06)))
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            switch updater.state {
            case .idle:
                installButton(label: "Скачать и установить", busy: false)
                Text("Приложение перезапустится автоматически. Логин и задачи сохранятся.")
                    .font(.system(size: 11))
                    .foregroundStyle(VibePlanTheme.ink500)
            case .downloading(let p):
                progressBar(p)
                Text("Скачиваем обновление… \(Int(p * 100))%")
                    .font(.system(size: 12))
                    .foregroundStyle(VibePlanTheme.ink500)
            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Устанавливаем и перезапускаем…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(VibePlanTheme.ink900)
                }
                .padding(.vertical, 4)
            case .failed(let msg):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(msg).font(.system(size: 12)).lineLimit(3)
                }
                .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.20))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                installButton(label: "Попробовать снова", busy: false)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func installButton(label: String, busy: Bool) -> some View {
        Button(action: { Task { await updater.install(release) } }) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small).tint(.white) }
                Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .bold))
                Text(label).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [Color(hex: 0x2D2646), Color(hex: 0x0F0F12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            )
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.06))
                RoundedRectangle(cornerRadius: 6)
                    .fill(VibePlanTheme.ink900)
                    .frame(width: max(8, geo.size.width * CGFloat(value)))
                    .animation(.linear(duration: 0.15), value: value)
            }
        }
        .frame(height: 8)
    }

    private var sizeString: String {
        let mb = Double(release.dmgSize) / 1024 / 1024
        return mb > 0 ? String(format: "%.1f МБ", mb) : "—"
    }
}

private extension VibePlanTheme {
    static var ink800: Color { ink900 }
}
