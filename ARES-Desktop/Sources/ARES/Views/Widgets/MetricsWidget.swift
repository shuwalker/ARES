import SwiftUI
import Charts
import ARESCore

struct TokenDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

struct MetricsWidget: View {
    @State private var dataPoints: [TokenDataPoint] = []
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                Text("System Metrics")
                    .font(.headline)
                Spacer()
                Text("Tokens/sec")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart(dataPoints) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Tokens", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.blue.gradient)

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Tokens", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
        .padding()
        .onReceive(timer) { time in
            // Simulated live token speed (in a real app, bind to ARESAppState.metrics)
            let speed = Double.random(in: 10...45)
            dataPoints.append(TokenDataPoint(time: time, value: speed))
            if dataPoints.count > 30 {
                dataPoints.removeFirst()
            }
        }
    }
}
