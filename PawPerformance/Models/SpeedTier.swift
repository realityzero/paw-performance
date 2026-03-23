import Foundation

struct SpeedTier {
    struct Tier {
        let state: RunnerState
        let range: ClosedRange<Double>
        let frameInterval: TimeInterval
        let moodLine: String
    }

    static let thresholds: [Tier] = [
        .init(state: .idle, range: 0 ... 15, frameInterval: 0.25, moodLine: "Just stretching..."),
        .init(state: .trot, range: 16 ... 40, frameInterval: 0.20, moodLine: "Picking up the pace"),
        .init(state: .sprint, range: 41 ... 70, frameInterval: 0.12, moodLine: "Legs are burning!"),
        .init(state: .panic, range: 71 ... 100, frameInterval: 0.15, moodLine: "PLEASE CLOSE CHROME")
    ]

    static func tier(forCPU cpuUsage: Double) -> Tier {
        let clamped = min(max(cpuUsage, 0), 100)
        return thresholds.first(where: { $0.range.contains(clamped) }) ?? thresholds[0]
    }
}
