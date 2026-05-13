import SwiftUI

struct FaceRenderer: View {
    let state: FaceState
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.016)) { context in
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let time = context.date.timeIntervalSinceReferenceDate
                drawFace(in: ctx, center: center, size: size, time: time)
            }
        }
    }
    
    func drawFace(in ctx: GraphicsContext, center: CGPoint, size: CGSize, time: TimeInterval) {
        let pulse = sin(time * state.pulseSpeed) * state.pulseAmount
        let radius = min(size.width, size.height) / 2 - 10 + pulse
        
        // Background circle
        let bgRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        
        // Outer glow
        ctx.fill(
            Path(ellipseIn: bgRect.insetBy(dx: -4, dy: -4)),
            with: .color(state.color.opacity(0.1))
        )
        
        // Main face circle
        ctx.fill(
            Path(ellipseIn: bgRect),
            with: .color(state.color.opacity(state.opacity))
        )
        
        // Eyes
        let eyeOffsetX = radius * 0.3
        let eyeY = center.y - radius * 0.1
        let eyeRadius = radius * 0.12
        
        let leftEye = CGRect(
            x: center.x - eyeOffsetX - eyeRadius,
            y: eyeY - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        )
        let rightEye = CGRect(
            x: center.x + eyeOffsetX - eyeRadius,
            y: eyeY - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        )
        
        ctx.fill(Path(ellipseIn: leftEye), with: .color(.white))
        ctx.fill(Path(ellipseIn: rightEye), with: .color(.white))
        
        // Pupils (follow state)
        let pupilOffset = state.pupilOffset * radius
        let pupilRadius = eyeRadius * 0.5
        let leftPupil = CGRect(
            x: center.x - eyeOffsetX + pupilOffset - pupilRadius,
            y: eyeY - pupilRadius,
            width: pupilRadius * 2,
            height: pupilRadius * 2
        )
        let rightPupil = CGRect(
            x: center.x + eyeOffsetX + pupilOffset - pupilRadius,
            y: eyeY - pupilRadius,
            width: pupilRadius * 2,
            height: pupilRadius * 2
        )
        ctx.fill(Path(ellipseIn: leftPupil), with: .color(.black))
        ctx.fill(Path(ellipseIn: rightPupil), with: .color(.black))
        
        // Mouth
        if state != .thinking {
            let mouthY = center.y + radius * 0.3
            let mouthWidth = radius * 0.4
            let mouthHeight: CGFloat
            
            switch state {
            case .speaking:
                mouthHeight = radius * 0.15 + sin(time * 12) * radius * 0.05
            case .listening:
                mouthHeight = radius * 0.02
            default:
                mouthHeight = radius * 0.02
            }
            
            let mouthRect = CGRect(
                x: center.x - mouthWidth / 2,
                y: mouthY - mouthHeight / 2,
                width: mouthWidth,
                height: mouthHeight
            )
            ctx.fill(Path(ellipseIn: mouthRect), with: .color(.white))
        } else {
            // Thinking: three dots
            for i in 0..<3 {
                let dotSize: CGFloat = 6
                let dotX = center.x + CGFloat(i - 1) * 14
                let dotY = center.y + radius * 0.3 + sin(time * 3 + Double(i)) * 4
                ctx.fill(
                    Path(ellipseIn: CGRect(x: dotX - dotSize/2, y: dotY - dotSize/2, width: dotSize, height: dotSize)),
                    with: .color(.white.opacity(0.8))
                )
            }
        }
    }
}
