import SwiftUI

/// Horizontal progress bar for the tool call Gantt timeline.
/// Extracted from OrchestrationView to avoid Swift type-checker timeout
/// with complex nested views inside GeometryReader.
struct ToolTimelineBar: View {
    let durationMs: Int
    let maxDuration: Int
    let status: String

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(
                CGFloat(durationMs) / CGFloat(maxDuration) * geo.size.width,
                status == "running" ? 20.0 : 4.0
            )

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 14)

                // Foreground bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: 14)

                // Pulse overlay for running tasks
                if status == "running" {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(pulse ? 0.15 : 0.03))
                        .frame(width: barWidth, height: 14)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                        .onAppear { pulse = true }
                }
            }
        }
    }

    private var barColor: Color {
        switch status {
        case "running":  return .orange.opacity(0.7)
        case "success":  return .green.opacity(0.6)
        case "failed":   return .red.opacity(0.6)
        default:         return .secondary.opacity(0.4)
        }
    }
}