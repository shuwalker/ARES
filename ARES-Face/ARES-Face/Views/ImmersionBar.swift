import SwiftUI

struct ImmersionBar: View {
    @EnvironmentObject var brain: BrainConnection
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(ImmersionLevel.allCases, id: \.self) { level in
                Button {
                    withAnimation(.spring(response: 0.5)) { brain.immersionLevel = level }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: level.icon)
                        Text(level.label)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(brain.immersionLevel == level ? .white.opacity(0.15) : .clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Text(brain.agentState.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.trailing, 4)
            
            Text(brain.avatarExpression.rawValue.capitalized)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.trailing, 4)
            
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }
    
    var stateColor: Color {
        switch brain.agentState {
        case .idle:      return .blue
        case .awakened:  return .cyan
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .purple
        case .sleeping:  return .gray
        }
    }
}