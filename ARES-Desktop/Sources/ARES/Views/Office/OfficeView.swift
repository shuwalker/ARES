import SwiftUI

struct OfficeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "building.2.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Agent Crew")
                .font(.title2)
                .fontWeight(.medium)

            Text("Office space coming in Phase 4.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
