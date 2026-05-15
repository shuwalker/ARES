import SwiftUI

/// Avatar style configurator — generalized for wide audience.
///
/// Not locked to one aesthetic. Users pick from multiple styles:
/// anime, realistic, pixel, abstract, minimalist, geometric.
/// Future: import custom Live2D/GLB models.
struct AvatarConfiguratorView: View {
    @EnvironmentObject var brain: BrainConnection
    @Binding var currentStyle: AvatarStyle
    @State private var hoveredStyle: AvatarStyle?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))
            styleGrid
            Divider().background(.white.opacity(0.08))
            customizationSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle")
            Text("Avatar")
                .font(.title3.weight(.semibold))
            Spacer()
            Text(currentStyle.displayName)
                .font(.caption.weight(.medium).lowercaseSmallCaps())
                .foregroundStyle(ARESPalette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Style Grid

    private var styleGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(AvatarStyle.allCases, id: \.self) { style in
                    styleCard(style)
                }
            }
            .padding(14)
        }
    }

    private func styleCard(_ style: AvatarStyle) -> some View {
        let isSelected = currentStyle == style
        let isHovered = hoveredStyle == style

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStyle = style
            }
        } label: {
            VStack(spacing: 8) {
                // Preview circle with style color
                Circle()
                    .fill(style.previewGradient)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: style.icon)
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isSelected ? ARESPalette.accent : (isHovered ? Color.white.opacity(0.2) : Color.clear),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    )

                Text(style.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? ARESPalette.accent : .secondary)

                Text(style.category)
                    .font(.system(size: 9, weight: .medium).lowercaseSmallCaps())
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ARESPalette.cornerM, style: .continuous)
                    .fill(isSelected ? ARESPalette.accentDim : (isHovered ? ARESPalette.surfaceHover : ARESPalette.surfaceBase))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredStyle = hovering ? style : nil
        }
    }

    // MARK: - Customization

    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Expression")
                .font(.caption.weight(.semibold).lowercaseSmallCaps())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            // Quick expression presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AvatarExpression.allCases, id: \.self) { expr in
                        ExpressionPill(expression: expr)
                    }
                }
                .padding(.horizontal, 14)
            }

            // Intensity slider
            HStack(spacing: 10) {
                Text("Intensity")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Slider(value: $brain.intensity, in: 0...1)
                    .tint(ARESPalette.accent)
                Text(String(format: "%.0f%%", brain.intensity * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Expression Pill

private struct ExpressionPill: View {
    let expression: AvatarExpression
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        Button {
            brain.setEmotion(expression.rawValue)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expression.icon)
                    .font(.system(size: 10))
                Text(expression.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(brain.avatarExpression == expression ? ARESPalette.accentDim : ARESPalette.surfaceBase)
            )
            .overlay(
                Capsule()
                    .strokeBorder(ARESPalette.surfaceBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}