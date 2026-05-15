import SwiftUI

/// Water ripple animation shown on first launch (BootGate).
struct ARESLaunchRipple: View {
    @State private var startTime: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince1970
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height)

                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.black.opacity(0.85)))

                for i in 0..<6 {
                    let delay = Double(i) * 0.25
                    let p = ((t - delay) / 2.0).truncatingRemainder(dividingBy: 1.0)
                    let r = p * maxR
                    let alpha = (1 - p) * (0.5 - Double(i) * 0.06)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                width: r * 2, height: r * 2)),
                        with: .color(.cyan.opacity(max(0, alpha))),
                        lineWidth: 1.5
                    )
                }

                let dropletAlpha = max(0, 1 - t / 1.5)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
                    with: .color(.white.opacity(dropletAlpha))
                )
            }
        }
    }
}