import Combine
import Darwin.POSIX
import Foundation
import IOKit.ps

struct TopProcess: Identifiable {
    let rank: Int
    let name: String
    let cpuPercent: Double

    var id: Int { rank }
}

final class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var memoryPressure: String = "Normal"
    @Published var topProcesses: [TopProcess] = []
    @Published var batteryPercent: Double?
    @Published var batteryTimeRemaining: String = "--"
    @Published var diskUsedGB: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var networkDownloadKBps: Double = 0
    @Published var networkUploadKBps: Double = 0

    private let hostPort: mach_port_t = mach_host_self()
    private var timer: DispatchSourceTimer?
    private var previousCPUTicks: [UInt32]?
    private var previousNetworkBytes: (received: UInt64, sent: UInt64)?
    private var previousNetworkSampleDate: Date?
    private var slowPollCounter: UInt = 0

    func start() {
        guard timer == nil else { return }
        refreshAll()

        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        source.schedule(deadline: .now() + 2, repeating: .seconds(2))
        source.setEventHandler { [weak self] in
            self?.refreshAll()
        }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        timer?.cancel()
    }

    private func refreshAll() {
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let network = sampleNetwork()
        let processes = sampleTopProcesses()

        let runSlowPoll = (slowPollCounter % 15 == 0)
        slowPollCounter &+= 1
        let battery = runSlowPoll ? sampleBattery() : nil
        let disk = runSlowPoll ? sampleDisk() : nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cpuUsage = cpu
            self.memoryUsedGB = memory.usedGB
            self.memoryTotalGB = memory.totalGB
            self.memoryPressure = memory.pressure
            self.topProcesses = processes
            self.networkDownloadKBps = network.downloadKBps
            self.networkUploadKBps = network.uploadKBps
            if let battery {
                self.batteryPercent = battery.percent
                self.batteryTimeRemaining = battery.remainingTime
            }
            if let disk {
                self.diskUsedGB = disk.usedGB
                self.diskFreeGB = disk.freeGB
            }
        }
    }

    private func sampleCPU() -> Double {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else { return cpuUsage }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(cpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            )
        }

        let tickCount = Int(cpuInfoCount)
        var ticks: [UInt32] = []
        ticks.reserveCapacity(tickCount)
        for i in 0 ..< tickCount {
            ticks.append(UInt32(cpuInfo[i]))
        }

        guard let previous = previousCPUTicks, previous.count == ticks.count else {
            previousCPUTicks = ticks
            return cpuUsage
        }

        var totalDiff: UInt64 = 0
        var idleDiff: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)

        for cpuIndex in 0 ..< Int(cpuCount) {
            let base = cpuIndex * stride
            guard base + Int(CPU_STATE_IDLE) < ticks.count else { break }

            for state in 0 ..< stride {
                totalDiff += UInt64(ticks[base + state] &- previous[base + state])
            }
            idleDiff += UInt64(ticks[base + Int(CPU_STATE_IDLE)] &- previous[base + Int(CPU_STATE_IDLE)])
        }

        previousCPUTicks = ticks
        guard totalDiff > 0 else { return cpuUsage }
        let usage = (1.0 - Double(idleDiff) / Double(totalDiff)) * 100
        return min(max(usage, 0), 100)
    }

    private func sampleMemory() -> (usedGB: Double, totalGB: Double, pressure: String) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(hostPort, HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (memoryUsedGB, memoryTotalGB, memoryPressure)
        }

        let pageSize = Double(vm_kernel_page_size)
        let usedPages = Double(vmStats.active_count + vmStats.wire_count + vmStats.compressor_page_count)
        let totalPages = Double(vmStats.active_count + vmStats.inactive_count + vmStats.wire_count + vmStats.free_count + vmStats.compressor_page_count)

        let usedBytes = usedPages * pageSize
        let totalBytes = totalPages * pageSize

        let usedGB = usedBytes / 1_073_741_824
        let totalGB = max(totalBytes / 1_073_741_824, usedGB)
        let pressureValue = totalGB > 0 ? (usedGB / totalGB) : 0
        let pressure: String
        switch pressureValue {
        case ..<0.70:
            pressure = "Normal"
        case ..<0.88:
            pressure = "Warning"
        default:
            pressure = "Critical"
        }

        return (usedGB, totalGB, pressure)
    }

    private func sampleTopProcesses() -> [TopProcess] {
        let bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferSize > 0 else { return topProcesses }

        let pidCount = Int(bufferSize) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: pidCount)
        let actualSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferSize)
        guard actualSize > 0 else { return topProcesses }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.stride
        var candidates: [(name: String, cpu: Double)] = []
        candidates.reserveCapacity(8)

        for i in 0 ..< actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard result == taskInfoSize else { continue }

            let totalTime = Double(taskInfo.pti_total_user + taskInfo.pti_total_system)
            guard totalTime > 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN + 1))
            proc_name(pid, &nameBuffer, UInt32(MAXCOMLEN + 1))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }

            let cpuPercent = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 10_000_000
            candidates.append((name, cpuPercent))
        }

        candidates.sort { $0.cpu > $1.cpu }
        return candidates.prefix(3).enumerated().map { index, item in
            TopProcess(rank: index, name: item.name, cpuPercent: item.cpu)
        }
    }

    private func sampleBattery() -> (percent: Double?, remainingTime: String) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return (nil, "--")
        }

        let current = description[kIOPSCurrentCapacityKey] as? Double
        let max = description[kIOPSMaxCapacityKey] as? Double
        let percent = (current != nil && max != nil && max! > 0) ? (current! / max! * 100.0) : nil

        var remainingTime = "--"
        if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
            remainingTime = "\(minutes / 60)h \(minutes % 60)m"
        } else if let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
            remainingTime = "Charging \(minutes / 60)h \(minutes % 60)m"
        }

        return (percent, remainingTime)
    }

    private func sampleDisk() -> (usedGB: Double, freeGB: Double) {
        let home = NSHomeDirectory()
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: home)
            let total = (attributes[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (attributes[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let used = max(0, total - free)
            return (used / 1_073_741_824, free / 1_073_741_824)
        } catch {
            return (diskUsedGB, diskFreeGB)
        }
    }

    private func sampleNetwork() -> (downloadKBps: Double, uploadKBps: Double) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (networkDownloadKBps, networkUploadKBps)
        }
        defer { freeifaddrs(ifaddrPtr) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer?.pointee {
            let flags = Int32(current.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, !isLoopback, let data = current.ifa_data?.assumingMemoryBound(to: if_data.self) {
                received += UInt64(data.pointee.ifi_ibytes)
                sent += UInt64(data.pointee.ifi_obytes)
            }
            pointer = current.ifa_next
        }

        let now = Date()
        defer {
            previousNetworkBytes = (received, sent)
            previousNetworkSampleDate = now
        }

        guard let previous = previousNetworkBytes,
              let previousDate = previousNetworkSampleDate else {
            return (networkDownloadKBps, networkUploadKBps)
        }

        let deltaSeconds = now.timeIntervalSince(previousDate)
        guard deltaSeconds > 0 else { return (networkDownloadKBps, networkUploadKBps) }

        let downDelta = received >= previous.received ? Double(received - previous.received) : 0
        let upDelta = sent >= previous.sent ? Double(sent - previous.sent) : 0
        let downKBps = downDelta / 1024 / deltaSeconds
        let upKBps = upDelta / 1024 / deltaSeconds
        return (downKBps, upKBps)
    }
}
