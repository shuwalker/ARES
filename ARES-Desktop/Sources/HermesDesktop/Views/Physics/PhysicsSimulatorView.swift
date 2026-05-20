import SwiftUI

struct PhysicsSimulatorView: View {
    var body: some View {
        HermesPageContainer {
            VStack(spacing: 16) {
                HermesPageHeader(
                    title: L10n.string("Physics Simulator"),
                    subtitle: L10n.string("Computational physics for ARES robotics")
                )
                Image(systemName: "atom")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(L10n.string("Not yet available. This panel will host the physics simulation workspace once the robotics hardware integration ships."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }
}
