import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model.loadRunnerPacks()
        model.persistPreferences()
        setupStatusItem()
        setupPopover()

        model.animationController.attach(statusItem: statusItem, monitor: model.monitor)
        applySelectedRunner()
        model.monitor.start()
        bindStatusTextUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.monitor.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Paw Performance")
        statusItem.button?.image?.isTemplate = true
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(
                model: model,
                onSelectRunner: { [weak self] _ in
                    self?.applySelectedRunner()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
    }

    private func bindStatusTextUpdates() {
        Publishers.CombineLatest(model.monitor.$cpuUsage, model.monitor.$memoryUsedGB.combineLatest(model.monitor.$memoryTotalGB))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, memoryTuple in
                guard let self else { return }
                let memoryPercent = memoryTuple.1 > 0 ? (memoryTuple.0 / memoryTuple.1) * 100 : 0
                self.updateStatusText(cpu: cpu, memoryPercent: memoryPercent)
            }
            .store(in: &cancellables)
    }

    private func updateStatusText(cpu: Double, memoryPercent: Double) {
        guard let button = statusItem.button else { return }
        switch model.menuMetricMode {
        case "cpu":
            button.title = " \(Int(cpu.rounded()))%"
        case "memory":
            button.title = " \(Int(memoryPercent.rounded()))%"
        default:
            button.title = ""
        }
    }

    private func applySelectedRunner() {
        guard let selected = model.selectedRunnerPack else { return }
        model.animationController.selectPack(selected)
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}
