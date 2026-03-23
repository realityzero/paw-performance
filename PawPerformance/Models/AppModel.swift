import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var runnerPacks: [RunnerPack] = []
    @Published var selectedRunnerID: String = UserDefaults.standard.string(forKey: "selectedRunnerID") ?? "cat"
    @Published var menuMetricMode: String = UserDefaults.standard.string(forKey: "menuMetricMode") ?? "none"

    let monitor = SystemMonitor()
    let loader = RunnerPackLoader()
    let animationController = AnimationController()

    var selectedRunnerPack: RunnerPack? {
        runnerPacks.first(where: { $0.id == selectedRunnerID }) ?? runnerPacks.first
    }

    func loadRunnerPacks() {
        do {
            runnerPacks = try loader.loadPacks()
        } catch {
            runnerPacks = []
            fputs("Failed to load runner packs: \(error)\n", stderr)
        }

        if runnerPacks.contains(where: { $0.id == selectedRunnerID }) == false,
           let first = runnerPacks.first {
            selectedRunnerID = first.id
        }
    }

    func persistPreferences() {
        UserDefaults.standard.set(selectedRunnerID, forKey: "selectedRunnerID")
        UserDefaults.standard.set(menuMetricMode, forKey: "menuMetricMode")
    }
}
