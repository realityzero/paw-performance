import AppKit
import Combine
import Foundation

final class AnimationController {
    private weak var statusItem: NSStatusItem?
    private weak var monitor: SystemMonitor?
    private var cancellables = Set<AnyCancellable>()

    private var timer: DispatchSourceTimer?
    private var currentFrames: [NSImage] = []
    private var currentFrameIndex = 0
    private var currentState: RunnerState = .idle
    private var currentInterval: TimeInterval = 0.30

    private(set) var selectedPack: RunnerPack?

    deinit {
        timer?.cancel()
    }

    func attach(statusItem: NSStatusItem, monitor: SystemMonitor) {
        self.statusItem = statusItem
        self.monitor = monitor

        monitor.$cpuUsage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu in
                self?.updateTier(for: cpu)
            }
            .store(in: &cancellables)

        updateTier(for: monitor.cpuUsage)
    }

    func selectPack(_ pack: RunnerPack) {
        selectedPack = pack
        currentFrameIndex = 0
        let tier = SpeedTier.tier(forCPU: monitor?.cpuUsage ?? 0)
        currentState = tier.state
        currentFrames = pack.framesByState[tier.state] ?? []
        if currentFrames.isEmpty {
            currentFrames = pack.framesByState[.idle] ?? []
        }
        setInterval(tier.frameInterval / max(0.2, pack.speedMultiplier))
        renderCurrentFrame()
    }

    private func updateTier(for cpuUsage: Double) {
        let tier = SpeedTier.tier(forCPU: cpuUsage)
        guard let pack = selectedPack else { return }

        let adjustedInterval = tier.frameInterval / max(0.2, pack.speedMultiplier)

        if tier.state != currentState {
            currentState = tier.state
            let desiredFrames = pack.framesByState[tier.state] ?? pack.framesByState[.idle] ?? []
            currentFrames = desiredFrames
            currentFrameIndex = 0
            renderCurrentFrame()
        }

        setInterval(adjustedInterval)
    }

    private func setInterval(_ interval: TimeInterval) {
        guard abs(currentInterval - interval) > 0.001 || timer == nil else { return }
        currentInterval = interval

        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            self?.advanceFrame()
        }
        source.resume()
        timer = source
    }

    private func advanceFrame() {
        guard !currentFrames.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % currentFrames.count
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard let button = statusItem?.button else { return }
        let image = currentFrames.indices.contains(currentFrameIndex)
            ? currentFrames[currentFrameIndex]
            : currentFrames.first
        button.image = image
        button.imagePosition = .imageLeft
        button.appearsDisabled = false
    }
}
