import SwiftUI

struct MetricsPanelView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.subheadline)
                .bold()

            metricRow("CPU", "\(format(monitor.cpuUsage, "%.1f"))%")
            metricRow("Memory", "\(format(monitor.memoryUsedGB, "%.1f")) / \(format(monitor.memoryTotalGB, "%.1f")) GB (\(monitor.memoryPressure))")
            metricRow("Battery", batteryText)
            metricRow("Disk", "\(format(monitor.diskUsedGB, "%.0f")) used / \(format(monitor.diskFreeGB, "%.0f")) free GB")
            metricRow("Network", "Down \(format(monitor.networkDownloadKBps, "%.0f")) KB/s • Up \(format(monitor.networkUploadKBps, "%.0f")) KB/s")

            if !monitor.topProcesses.isEmpty {
                Divider().padding(.vertical, 2)
                Text("Top CPU Processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(monitor.topProcesses) { process in
                    HStack {
                        Text("\(process.rank + 1). \(process.name)")
                            .lineLimit(1)
                        Spacer()
                        Text("\(format(process.cpuPercent, "%.1f"))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var batteryText: String {
        if let percent = monitor.batteryPercent {
            return "\(format(percent, "%.0f"))% • \(monitor.batteryTimeRemaining)"
        }
        return "Not available"
    }

    private func format(_ value: Double, _ specifier: String) -> String {
        String(format: specifier, value)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
