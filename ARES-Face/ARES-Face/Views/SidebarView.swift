import SwiftUI

struct SidebarView: View {
    @Binding var selectedPage: DashboardPage
    @EnvironmentObject var brain: BrainConnection

    var body: some View {
        ZStack {
            VisualEffect(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()

            VStack(spacing: 4) {
                // Top padding to align with window chrome
                Spacer().frame(height: 12)

                ForEach(DashboardPage.allCases, id: \.self) { page in
                    SidebarIconButton(
                        page: page,
                        isSelected: selectedPage == page
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPage = page
                        }
                    }
                    .help(page.label)
                }

                Spacer()

                // Connection status indicator
                Circle()
                    .fill(brain.backendConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: brain.backendConnected ? Color.green.opacity(0.6) : Color.red.opacity(0.6), radius: 3, x: 0, y: 0)
                    .padding(.bottom, 16)
                    .help(brain.backendConnected ? "Connected" : "Disconnected")
            }
        }
        .frame(width: 56)
    }
}

// MARK: - Sidebar Icon Button

struct SidebarIconButton: View {
    let page: DashboardPage
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: page.icon)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(page.label)
    }
}
