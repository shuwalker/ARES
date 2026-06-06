import ARESCore
import SwiftUI

/// ARES design system colors — dark cinematic Spartan theme.
enum ARESColors {
    // Core palette
    static let gold = Color(red: 0.85, green: 0.70, blue: 0.35)
    static let accent = Color(red: 0.55, green: 0.35, blue: 0.20)
    static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.18)
    static let divider = Color.white.opacity(0.06)
    static let green = Color(red: 0.20, green: 0.80, blue: 0.40)
    static let red = Color(red: 0.90, green: 0.25, blue: 0.25)
    static let purple = Color(red: 0.60, green: 0.30, blue: 0.80)

    // Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.30)

    // Gradient
    static let gradient = LinearGradient(
        colors: [
            Color(red: 0.15, green: 0.12, blue: 0.18),
            Color(red: 0.08, green: 0.06, blue: 0.12)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
