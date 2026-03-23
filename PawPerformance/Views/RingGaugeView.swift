import SwiftUI

struct RingGaugeView: View {
    let title: String
    let value: Double
    let maximum: Double

    private var normalized: Double {
        guard maximum > 0 else { return 0 }
        return min(max(value / maximum, 0), 1)
    }

    private var gaugeColor: Color {
        switch normalized {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: normalized)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: normalized)
                Text("\(Int(normalized * 100))%")
                    .font(.caption.monospacedDigit())
                    .bold()
            }
            .frame(width: 62, height: 62)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
