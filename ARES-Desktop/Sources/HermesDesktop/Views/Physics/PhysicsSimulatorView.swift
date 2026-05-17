import SwiftUI

struct PhysicsSimulatorView: View {
    var body: some View {
        HermesPageContainer {
            VStack(spacing: 16) {
                HermesPageHeader(title: "Physics Simulator", subtitle: "Computational physics for ARES robotics")
                Text("Coming soon — requires hardware specs from Matthew")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
