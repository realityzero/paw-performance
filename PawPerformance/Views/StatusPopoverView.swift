import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var model: AppModel
    let onSelectRunner: (String) -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusCardView(
                monitor: model.monitor,
                runnerName: model.selectedRunnerPack?.name ?? "Runner"
            )

            MetricsPanelView(monitor: model.monitor)

            Divider()

            HStack {
                RunnerPickerView(packs: model.runnerPacks, selectedID: $model.selectedRunnerID)
                    .frame(maxWidth: 160)
                    .onChange(of: model.selectedRunnerID) { _, newValue in
                        model.persistPreferences()
                        onSelectRunner(newValue)
                    }

                Spacer()

                Picker("Menu Metric", selection: $model.menuMetricMode) {
                    Text("No Text").tag("none")
                    Text("CPU %").tag("cpu")
                    Text("Memory %").tag("memory")
                }
                .frame(width: 110)
                .onChange(of: model.menuMetricMode) { _, _ in
                    model.persistPreferences()
                }

                Button("Quit", role: .destructive, action: onQuit)
            }
        }
        .padding(12)
        .frame(width: 380)
    }
}
