import SwiftUI

struct StatusCardView: View {
    @ObservedObject var monitor: SystemMonitor
    let runnerName: String

    private var tier: SpeedTier.Tier {
        SpeedTier.tier(forCPU: monitor.cpuUsage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 24, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(runnerName) is \(tier.state.rawValue)")
                        .font(.headline)
                    Text(tier.moodLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                RingGaugeView(title: "CPU", value: monitor.cpuUsage, maximum: 100)
                RingGaugeView(title: "Memory", value: monitor.memoryUsedGB, maximum: max(monitor.memoryTotalGB, 1))
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
