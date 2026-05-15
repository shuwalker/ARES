import SwiftUI

/// Wraps content behind a launch animation gate. Content is mounted immediately
/// so its data loads while the animation plays. The overlay dismisses when
/// the animation finishes or the user taps to skip.
///
/// Ported from OS1's BootGate pattern (nickvasilescu/hermes-desktop-os1).
/// Views that should not run until the intro has finished can read
/// `@Environment(\.aresBootFinished)` to defer heavy init.
struct BootGate<Content: View>: View {
    @AppStorage("ares.skipBootAnimation") private var skipBootAnimation: Bool = false
    @State private var bootFinished: Bool

    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        // Dev escape hatch: ARES_SKIP_BOOT=1 skips animation for fast dev cycles
        let envSkip = ProcessInfo.processInfo.environment["ARES_SKIP_BOOT"] == "1"
        _bootFinished = State(initialValue: envSkip)
    }

    var body: some View {
        let isBootComplete = bootFinished || skipBootAnimation

        ZStack {
            content()
                .environment(\.aresBootFinished, isBootComplete)

            if !isBootComplete {
                ARESLaunchRipple()
                    .transition(.opacity)
                    .zIndex(1)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.3)) {
                            bootFinished = true
                        }
                    }
            }
        }
    }
}

// MARK: - Environment Key

private struct ARESBootFinishedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var aresBootFinished: Bool {
        get { self[ARESBootFinishedKey.self] }
        set { self[ARESBootFinishedKey.self] = newValue }
    }
}