import SwiftUI

struct MainWindowView: View {
    var body: some View {
        ZStack {
            VibePlanTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(VibePlanTheme.ink700)

                Text("VibePlan")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(VibePlanTheme.ink900)

                Text("Phase 0 · skeleton build")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .textCase(.uppercase)
                    .tracking(0.8)

                Text("Если ты это видишь — сборка работает.\nДальше — экран логина, месяц-сетка, синк через бэк.")
                    .font(.system(size: 13))
                    .foregroundStyle(VibePlanTheme.ink500)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .frame(maxWidth: 420)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x3C3258, alpha: 0.18), radius: 24, x: 0, y: 10)
        }
    }
}
