import SwiftUI

/// Professional Hermes-inspired sidebar for Manual mode.
///
/// Design:
///   - 220px width, collapsible to 60px icon-only
///   - Grouped navigation: Conversation, Tools, System
///   - ARES branding at top with flame icon
///   - Selected state: cyan/violet accent, subtle background
///   - Hover state: subtle white background
///   - Bottom: connection status dot, voice toggle, version
struct SidebarView: View {
    @Binding var selectedPage: DashboardPage
    @Binding var isCollapsed: Bool
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager

    @State private var collapsedGroups: Set<SidebarGroup> = []
    @State private var hoveredPage: DashboardPage?

    private let sidebarWidth: CGFloat = 220
    private let collapsedWidth: CGFloat = 60

    var body: some View {
        ZStack {
            sidebarBackground

            VStack(spacing: 0) {
                // ── ARES Branding ──
                brandHeader
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                brandDivider

                // ── Navigation Groups ──
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(SidebarGroup.allCases, id: \.self) { group in
                            NavGroupSection(
                                group: group,
                                selectedPage: $selectedPage,
                                isCollapsed: $isCollapsed,
                                collapsedGroups: $collapsedGroups,
                                hoveredPage: $hoveredPage
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, isCollapsed ? 6 : 10)
                }

                Spacer()

                // ── Bottom Section ──
                bottomDivider

                VStack(spacing: 8) {
                    if !isCollapsed {
                        voiceToggle
                        connectionStatus
                        versionLabel
                    } else {
                        compactVoiceToggle
                        compactConnectionDot
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, isCollapsed ? 0 : 12)

                // ── Collapse Toggle ──
                collapseButton
                    .padding(.bottom, 8)
            }
        }
        .frame(width: isCollapsed ? collapsedWidth : sidebarWidth)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    // MARK: - Background

    private var sidebarBackground: some View {
        ZStack {
            Color.black.opacity(0.35)
            VisualEffect(material: .sidebar, blendingMode: .withinWindow)
        }
        .ignoresSafeArea()
    }

    // MARK: - Brand Header

    @ViewBuilder
    private var brandHeader: some View {
        HStack(spacing: isCollapsed ? 0 : 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: isCollapsed ? 18 : 22, weight: .semibold))
                .foregroundStyle(ARESPalette.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ARESPalette.accent.opacity(0.12))
                )

            if !isCollapsed {
                Text("ARES")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
        }
        .padding(.horizontal, isCollapsed ? 0 : 14)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var brandDivider: some View {
        Divider()
            .background(ARESPalette.surfaceBorder)
            .padding(.horizontal, isCollapsed ? 10 : 14)
    }

    private var bottomDivider: some View {
        Divider()
            .background(ARESPalette.surfaceBorder)
            .padding(.horizontal, isCollapsed ? 10 : 14)
    }

    // MARK: - Collapse Button

    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }

    // MARK: - Voice Toggle (Expanded)

    private var voiceToggle: some View {
        Button {
            voice.toggleListening()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                    .font(.system(size: 12, weight: voice.isListening ? .semibold : .regular))
                    .frame(width: 16)
                    .foregroundStyle(voice.isListening ? .green : .secondary)

                Text(voice.isListening ? "Listening" : "Voice Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(voice.isListening ? .green : .secondary)

                Spacer()

                Circle()
                    .fill(voice.isListening ? Color.green : Color.clear)
                    .frame(width: 6, height: 6)
                    .shadow(color: voice.isListening ? Color.green.opacity(0.5) : .clear, radius: 3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(voice.isListening ? Color.green.opacity(0.08) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private var compactVoiceToggle: some View {
        Button {
            voice.toggleListening()
        } label: {
            Image(systemName: voice.isListening ? "mic.fill" : "mic.slash")
                .font(.system(size: 12))
                .foregroundStyle(voice.isListening ? .green : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(voice.isListening ? Color.green.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(voice.isListening ? "Stop listening" : "Start listening")
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        HStack(spacing: 6) {
            connectionDot
            Text(brain.backendConnected ? "Connected" : "Offline")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(brain.backendConnected ? Color.green.opacity(0.8) : .secondary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var compactConnectionDot: some View {
        connectionDot
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var connectionDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(brain.backendConnected ? Color.green : Color.red.opacity(0.7))
                .frame(width: 6, height: 6)
                .shadow(
                    color: brain.backendConnected ? Color.green.opacity(0.4) : Color.red.opacity(0.2),
                    radius: 3
                )
        }
    }

    // MARK: - Version

    private var versionLabel: some View {
        Text("ARES v1.0")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

// MARK: - Nav Group Section

struct NavGroupSection: View {
    let group: SidebarGroup
    @Binding var selectedPage: DashboardPage
    @Binding var isCollapsed: Bool
    @Binding var collapsedGroups: Set<SidebarGroup>
    @Binding var hoveredPage: DashboardPage?

    var isGroupCollapsed: Bool {
        collapsedGroups.contains(group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !isCollapsed {
                // Group header
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isGroupCollapsed {
                            collapsedGroups.remove(group)
                        } else {
                            collapsedGroups.insert(group)
                        }
                    }
                } label: {
                    HStack {
                        Text(group.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.25))
                            .rotationEffect(.degrees(isGroupCollapsed ? -90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isGroupCollapsed)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } else if !isGroupCollapsed {
                // In collapsed mode, show a subtle separator between groups
                Divider()
                    .background(Color.white.opacity(0.04))
                    .padding(.vertical, 4)
            }

            if !isGroupCollapsed {
                ForEach(group.pages, id: \.self) { page in
                    NavItem(
                        page: page,
                        isSelected: selectedPage == page,
                        isCollapsed: isCollapsed,
                        isHovered: hoveredPage == page
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPage = page
                        }
                    }
                    .onHover { hovering in
                        hoveredPage = hovering ? page : nil
                    }
                }
            }
        }
    }
}

// MARK: - Nav Item

struct NavItem: View {
    let page: DashboardPage
    let isSelected: Bool
    let isCollapsed: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: isCollapsed ? 0 : 10) {
            Image(systemName: page.icon)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? ARESPalette.accent : Color.primary.opacity(0.6))
                .frame(width: isCollapsed ? 32 : 20, height: isCollapsed ? 32 : 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                              ? ARESPalette.accent.opacity(0.12)
                              : (isHovered ? Color.white.opacity(0.06) : Color.clear))
                )

            if !isCollapsed {
                Text(page.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? ARESPalette.accent : Color.primary.opacity(0.7))
                Spacer()
            }
        }
        .padding(.horizontal, isCollapsed ? 0 : 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? ARESPalette.accent.opacity(0.06)
                      : (isHovered ? Color.white.opacity(0.03) : Color.clear))
        )
        .contentShape(Rectangle())
        .help(page.label)
    }
}
