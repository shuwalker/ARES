import SwiftUI

/// OS1/AIRI-style sidebar — icon rail with labels, connection dot, voice section.
///
/// In Manual mode this sits on the left. In Avatar Twin mode it's hidden entirely,
/// replaced by the floating ControlsIsland.
struct SidebarView: View {
    @Binding var selectedPage: DashboardPage
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @State private var hoveredPage: DashboardPage?

    var body: some View {
        ZStack {
            // Glass backdrop
            VisualEffect(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(spacing: 2) {
                // ── ARES icon at top ──
                aresIcon
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                Divider()
                    .background(.white.opacity(0.06))
                    .padding(.horizontal, 10)

                // ── Page icons ──
                ForEach(DashboardPage.allCases, id: \.self) { page in
                    pageButton(page)
                }

                Spacer()

                // ── Voice section at bottom (OS1 pattern) ──
                voiceRow

                // ── Connection dot ──
                connectionDot
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 56)
    }

    // MARK: - ARES Icon

    private var aresIcon: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.cyan)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.cyan.opacity(0.12))
            )
    }

    // MARK: - Page Button

    private func pageButton(_ page: DashboardPage) -> some View {
        let isSelected = selectedPage == page
        let isHovered = hoveredPage == page

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPage = page
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: page.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.6))

                // Tiny label underneath
                Text(page.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.4))
                    .lineLimit(1)
            }
            .frame(width: 44, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) :
                          (isHovered ? Color.white.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPage = hovering ? page : nil
        }
        .help(page.label)
    }

    // MARK: - Voice Row

    private var voiceRow: some View {
        Button {
            voice.toggleListening()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                    .font(.system(size: 11, weight: voice.isListening ? .semibold : .regular))
                    .frame(width: 14)
                Text(voice.isListening ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .semibold).lowercaseSmallCaps())
            }
            .foregroundStyle(voice.isListening ? .green : .secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(voice.isListening ? Color.green.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Connection Dot

    private var connectionDot: some View {
        Circle()
            .fill(brain.backendConnected ? Color.green : Color.red.opacity(0.7))
            .frame(width: 6, height: 6)
            .shadow(color: brain.backendConnected ? Color.green.opacity(0.5) : Color.red.opacity(0.3), radius: 3)
    }
}