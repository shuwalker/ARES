import SwiftUI
import ARESCore

// MARK: - Avatar Widget
//
// Static avatar display extracted from CompanionView.
// Placeholder for future animation states (idle, listening, thinking, speaking, sleeping).

struct AvatarWidget: View {
    @State private var currentEmotion: String = "neutral"
    let emotions = ["neutral", "happy", "curious", "thinking"]

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.3),
                                Color.blue.opacity(0.1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(height: 180)

                VStack(spacing: 20) {
                    // Eyes
                    HStack(spacing: 24) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)
                    }
                    .frame(height: 40)

                    // Mouth (emotion indicator)
                    Group {
                        if currentEmotion == "happy" {
                            Path { path in
                                path.addArc(center: CGPoint(x: 0, y: 0), radius: 20, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                            }
                            .stroke(Color.black, lineWidth: 2)
                        } else if currentEmotion == "thinking" {
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        } else {
                            // neutral / curious
                            Path { path in
                                path.move(to: CGPoint(x: -15, y: 0))
                                path.addLine(to: CGPoint(x: 15, y: 0))
                            }
                            .stroke(Color.black, lineWidth: 2)
                        }
                    }
                    .frame(height: 30)
                }
                .frame(width: 100)
            }

            // Emotion indicator
            VStack(spacing: 8) {
                Text("State").font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(emotions, id: \.self) { emotion in
                        Button {
                            withAnimation(.spring()) {
                                currentEmotion = emotion
                            }
                        } label: {
                            Circle()
                                .fill(currentEmotion == emotion ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Online").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 200)
    }
}

#Preview {
    AvatarWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}
