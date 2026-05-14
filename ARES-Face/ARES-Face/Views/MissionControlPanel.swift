import SwiftUI

// Mission Control — renders the current cycle's reasoning DAG as a
// force-directed graph using a Verlet integrator on each TimelineView
// tick. No third-party dependencies.

struct MissionControlPanel: View {
    @EnvironmentObject var brain: BrainConnection

    @State private var sim = GraphSimulation()
    @State private var selectedId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))
            graph
            if let id = selectedId,
               let node = brain.cognitive.thought?.branches.first(where: { $0.id == id }) {
                Divider().background(.white.opacity(0.08))
                detailFooter(node: node)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onChange(of: brain.cognitive.thought?.branches ?? []) { _, nodes in
            sim.sync(with: nodes)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            Text("Mission Control")
                .font(.title3.weight(.semibold))
            Spacer()
            if let depth = brain.cognitive.thought?.depth, depth > 0 {
                Text("depth \(depth)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("cycle \(brain.cognitive.loop.cycle)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var graph: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                Canvas { ctx, size in
                    sim.step(in: size)

                    // Edges first so nodes overlay them.
                    for edge in sim.edges {
                        guard let a = sim.position(of: edge.from),
                              let b = sim.position(of: edge.to) else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        ctx.stroke(path, with: .color(.cyan.opacity(0.25)), lineWidth: 1)
                    }

                    for body in sim.bodies {
                        let highlighted = body.id == selectedId
                        let color = nodeColor(for: body.label, highlighted: highlighted)
                        let radius: CGFloat = highlighted ? 12 : 8
                        let rect = CGRect(
                            x: body.position.x - radius,
                            y: body.position.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        ctx.fill(Path(ellipseIn: rect), with: .color(color))
                        ctx.stroke(Path(ellipseIn: rect),
                                   with: .color(.white.opacity(highlighted ? 0.7 : 0.25)),
                                   lineWidth: 1)

                        // Label
                        let text = Text(body.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        ctx.draw(text,
                                 at: CGPoint(x: body.position.x, y: body.position.y + radius + 9),
                                 anchor: .center)
                    }
                }
                .background(Color.black.opacity(0.25))
                .gesture(tapGesture(in: geo.size))
            }
        }
    }

    @ViewBuilder
    private func detailFooter(node: ThoughtNode) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.label.uppercased())
                    .font(.caption.weight(.semibold))
                Text("id \(node.id) · parents \(node.parentIds.count) · \(node.durationMs)ms")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                selectedId = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func tapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { event in
                let pt = event.location
                let hit = sim.bodies.min { lhs, rhs in
                    hypot(lhs.position.x - pt.x, lhs.position.y - pt.y) <
                    hypot(rhs.position.x - pt.x, rhs.position.y - pt.y)
                }
                if let hit, hypot(hit.position.x - pt.x, hit.position.y - pt.y) < 24 {
                    selectedId = hit.id
                } else {
                    selectedId = nil
                }
            }
    }

    private func nodeColor(for label: String, highlighted: Bool) -> Color {
        let base: Color
        switch label.lowercased() {
        case "perceive": base = .cyan
        case "think":    base = .orange
        case "act":      base = .purple
        case "reflect":  base = .green
        default:         base = .blue
        }
        return highlighted ? base : base.opacity(0.7)
    }
}

// MARK: - Verlet force-directed simulation

private struct GraphBody: Identifiable {
    let id: String
    let label: String
    var position: CGPoint
    var previous: CGPoint
}

private struct GraphEdge {
    let from: String
    let to: String
}

@Observable
final class GraphSimulation {
    var bodies: [GraphBody] = []
    var edges: [GraphEdge] = []

    // Parameters tuned for ~10 nodes in a panel-sized canvas.
    private let repulsion: CGFloat = 1400
    private let springLength: CGFloat = 70
    private let springStiffness: CGFloat = 0.08
    private let centerPull: CGFloat = 0.012
    private let damping: CGFloat = 0.86

    func sync(with nodes: [ThoughtNode]) {
        // Keep existing positions for unchanged nodes; introduce new ones
        // at the center with a small jitter so they fly out naturally.
        let existing = Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0) })
        var rebuilt: [GraphBody] = []
        for node in nodes {
            if let prior = existing[node.id] {
                rebuilt.append(prior)
            } else {
                let jitter = CGPoint(x: CGFloat.random(in: -8...8),
                                     y: CGFloat.random(in: -8...8))
                rebuilt.append(GraphBody(
                    id: node.id,
                    label: node.label,
                    position: jitter,
                    previous: jitter
                ))
            }
        }
        bodies = rebuilt
        edges = nodes.flatMap { node in
            node.parentIds.map { GraphEdge(from: $0, to: node.id) }
        }
    }

    func position(of id: String) -> CGPoint? {
        bodies.first(where: { $0.id == id })?.position
    }

    func step(in size: CGSize) {
        guard !bodies.isEmpty, size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var forces: [String: CGPoint] = [:]
        for body in bodies { forces[body.id] = .zero }

        // Pairwise repulsion
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                let a = bodies[i], b = bodies[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = sqrt(distSq)
                let fx = repulsion * dx / (distSq * dist)
                let fy = repulsion * dy / (distSq * dist)
                forces[a.id]?.x += fx
                forces[a.id]?.y += fy
                forces[b.id]?.x -= fx
                forces[b.id]?.y -= fy
            }
        }

        // Spring forces along edges
        for edge in edges {
            guard let fromIdx = bodies.firstIndex(where: { $0.id == edge.from }),
                  let toIdx = bodies.firstIndex(where: { $0.id == edge.to }) else { continue }
            let from = bodies[fromIdx]
            let to = bodies[toIdx]
            let dx = to.position.x - from.position.x
            let dy = to.position.y - from.position.y
            let dist = max(sqrt(dx * dx + dy * dy), 0.001)
            let delta = dist - springLength
            let fx = springStiffness * delta * dx / dist
            let fy = springStiffness * delta * dy / dist
            forces[from.id]?.x += fx
            forces[from.id]?.y += fy
            forces[to.id]?.x -= fx
            forces[to.id]?.y -= fy
        }

        // Center pull keeps the graph inside the canvas.
        for body in bodies {
            forces[body.id]?.x += (center.x - body.position.x) * centerPull
            forces[body.id]?.y += (center.y - body.position.y) * centerPull
        }

        // Verlet integration step
        let margin: CGFloat = 16
        for i in 0..<bodies.count {
            let id = bodies[i].id
            let force = forces[id] ?? .zero
            let pos = bodies[i].position
            let prev = bodies[i].previous
            let vx = (pos.x - prev.x) * damping + force.x
            let vy = (pos.y - prev.y) * damping + force.y
            var next = CGPoint(x: pos.x + vx, y: pos.y + vy)
            // Clamp inside the canvas with soft margins.
            next.x = min(max(next.x, margin), size.width - margin)
            next.y = min(max(next.y, margin), size.height - margin)
            bodies[i].previous = pos
            bodies[i].position = next
        }
    }
}
