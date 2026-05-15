import SwiftUI

// MARK: - ARES Palette
//
// Centralized design tokens from OS1 analysis + ARES brand.
// Every color, spacing, and corner radius in one place.
// Views reference these instead of magic numbers.

enum ARESPalette {
    // ── Brand ──
    static let accent = Color.cyan
    static let accentDim = Color.cyan.opacity(0.12)
    static let accentGlow = Color.cyan.opacity(0.5)

    // ── Surfaces ──
    static let surfaceBase = Color.white.opacity(0.04)
    static let surfaceHover = Color.white.opacity(0.06)
    static let surfaceActive = Color.white.opacity(0.08)
    static let surfaceBorder = Color.white.opacity(0.08)

    // ── Text ──
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.white.opacity(0.35)
    static let textQuaternary = Color.white.opacity(0.15)

    // ── Status ──
    static let success = Color.green
    static let warning = Color.yellow
    static let failure = Color.red
    static let info = Color.cyan

    // ── Spacing ──
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // ── Corners ──
    static let cornerS: CGFloat = 6
    static let cornerM: CGFloat = 10
    static let cornerL: CGFloat = 14

    // ── Icon sizes ──
    static let iconS: CGFloat = 11
    static let iconM: CGFloat = 14
    static let iconL: CGFloat = 20

    // ── Font sizes ──
    static let fontCaption: CGFloat = 10
    static let fontBody: CGFloat = 12
    static let fontSubheadline: CGFloat = 13
    static let fontHeadline: CGFloat = 15
}

// MARK: - Glass Modifier
//
// OS1-inspired frosted glass surface for dashboard panels.
// Usage: .glass() on any View.

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat = ARESPalette.cornerM
    var opacity: Double = 0.9

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ARESPalette.surfaceBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Apply frosted glass surface effect to the view.
    /// - Parameters:
    ///   - cornerRadius: Override corner radius (default: ARESPalette.cornerM = 10)
    ///   - opacity: Override material opacity (default: 0.9)
    func glass(cornerRadius: CGFloat = ARESPalette.cornerM, opacity: Double = 0.9) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}