import SwiftUI

/// Small generic avatar — initials on a stable gradient computed from the name.
/// Reuse from anywhere we need to show a person.
struct AvatarBadge: View {
    let name: String
    let email: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: gradient(for: seed),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(1, size / 14)))
    }

    private var seed: String { email.isEmpty ? name : email }

    private var initials: String {
        let display = name.isEmpty ? email : name
        if display.contains(" ") {
            let parts = display.split(separator: " ")
            return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        if display.contains("@") {
            // First two letters of local-part of email.
            let local = display.split(separator: "@").first.map(String.init) ?? display
            return String(local.prefix(2)).uppercased()
        }
        return String(display.prefix(2)).uppercased()
    }

    /// Stable hash → palette index so the same email always gets the same colors.
    private func gradient(for s: String) -> [Color] {
        let palettes: [[Color]] = [
            [VibePlanTheme.catWork, VibePlanTheme.catPersonal],
            [VibePlanTheme.catUrgent, VibePlanTheme.catIdeas],
            [VibePlanTheme.catLearning, VibePlanTheme.catWork],
            [VibePlanTheme.catPersonal, VibePlanTheme.catIdeas],
            [VibePlanTheme.catWork, VibePlanTheme.catLearning],
            [VibePlanTheme.catUrgent, VibePlanTheme.catPersonal]
        ]
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palettes[Int(hash % UInt64(palettes.count))]
    }
}

/// Wrap-friendly horizontal layout — chips flow onto multiple lines as needed.
/// Rolled by hand because SwiftUI ships no built-in flow layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Stack of overlapping avatars (`+N` chip if more than `maxVisible`).
struct AvatarStack: View {
    let people: [(name: String, email: String)]
    var maxVisible: Int = 3
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -size * 0.28) {
            ForEach(Array(people.prefix(maxVisible).enumerated()), id: \.offset) { _, p in
                AvatarBadge(name: p.name, email: p.email, size: size)
            }
            if people.count > maxVisible {
                ZStack {
                    Circle().fill(VibePlanTheme.ink900)
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(1, size / 14)))
                    Text("+\(people.count - maxVisible)")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
