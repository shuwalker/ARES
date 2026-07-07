import SwiftUI
import ARESCore

struct SubAgentStatusNode: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let status: String
    let color: Color
}

struct AgentStatusWidget: View {
    let agents = [
        SubAgentStatusNode(name: "ARES Core", icon: "brain", status: "Active", color: .green),
        SubAgentStatusNode(name: "Vision Node", icon: "eye", status: "Capturing", color: .blue),
        SubAgentStatusNode(name: "Coder", icon: "hammer", status: "Idle", color: .gray),
        SubAgentStatusNode(name: "Researcher", icon: "magnifyingglass", status: "Searching", color: .orange)
    ]

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.purple)
                Text("Sub-Agents")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(agents) { agent in
                    HStack(spacing: 8) {
                        Image(systemName: agent.icon)
                            .foregroundColor(agent.color)
                            .frame(width: 24, height: 24)
                            .background(agent.color.opacity(0.1))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(agent.status)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
    }
}
