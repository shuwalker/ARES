import SwiftUI

struct SwiftTermTerminalView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let appearance: TerminalThemeAppearance
    let isActive: Bool

    func makeNSView(context _: Context) -> TerminalMountContainerView {
        let container = TerminalMountContainerView()
        session.mount(in: container, appearance: appearance, isActive: isActive)
        return container
    }

    func updateNSView(_ nsView: TerminalMountContainerView, context _: Context) {
        session.mount(in: nsView, appearance: appearance, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: TerminalMountContainerView, coordinator _: Void) {
        nsView.unmountHostedView()
    }
}
