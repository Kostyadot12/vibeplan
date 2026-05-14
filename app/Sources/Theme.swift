import SwiftUI

enum VibePlanTheme {
    static let ink900 = Color(hex: 0x1F1F1F)
    static let ink700 = Color(hex: 0x3A3A3A)
    static let ink500 = Color(hex: 0x777777)
    static let ink400 = Color(hex: 0xA0A0A0)
    static let ink300 = Color(hex: 0xC4C4C4)
    static let ink100 = Color(hex: 0xECECEC)

    static let catPersonal = Color(hex: 0xB794F4)
    static let catWork     = Color(hex: 0x6AAEF7)
    static let catUrgent   = Color(hex: 0xF17A7A)
    static let catIdeas    = Color(hex: 0xF0C674)
    static let catLearning = Color(hex: 0x8ED4A8)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(hex: 0xF6F4F1),
            Color(hex: 0xEFEAF3),
            Color(hex: 0xEBF2F7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
