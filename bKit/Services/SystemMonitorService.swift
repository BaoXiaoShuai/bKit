//
//  SystemMonitorService.swift
//  bKit
//
//  Created by Codex on 2026/7/8.
//

// Darwin 提供 Mach 与网络统计底层能力
import Darwin
// Foundation 基础类型与定时调度能力
import Foundation
// IOKit 预留硬件信息读取能力
import IOKit

struct SystemMonitorMetrics {
    let cpuUsagePercent: Double
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let diskUsedGB: Double
    let diskTotalGB: Double
    let uploadSpeedKBps: Double
    let downloadSpeedKBps: Double
    let temperatureCelsius: Double?
    let fanSpeedRPM: Double?
    let uploadHistoryKBps: [Double]
    let downloadHistoryKBps: [Double]
}

private struct NetworkCounterSample {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let capturedAt: Date
}

final class SystemMonitorService {
    /// 采集到新数据后回调给插件层，统一在主线程更新 UI 状态。
    var onUpdate: ((SystemMonitorMetrics) -> Void)?

    private let queue = DispatchQueue(label: "com.bkit.system-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastNetworkSample: NetworkCounterSample?
    private var previousCPUTicks: [UInt32]?
    private var uploadHistoryKBps: [Double] = []
    private var downloadHistoryKBps: [Double] = []
    private var smoothedUploadKBps: Double = 0
    private var smoothedDownloadKBps: Double = 0

    func start() {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1200))
        timer.setEventHandler { [weak self] in
            self?.captureMetrics()
        }

        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        lastNetworkSample = nil
        previousCPUTicks = nil
        uploadHistoryKBps = []
        downloadHistoryKBps = []
        smoothedUploadKBps = 0
        smoothedDownloadKBps = 0
    }

    /// 汇总一次系统指标采集，采集失败的字段使用上一次或兜底值保持稳定输出。
    private func captureMetrics() {
        let cpuUsagePercent = currentCPUUsagePercent() ?? 0
        let memorySnapshot = currentMemorySnapshot() ?? (usedGB: 0, totalGB: 0)
        let diskSnapshot = currentDiskSnapshot() ?? (usedGB: 0, totalGB: 0)
        let networkSnapshot = currentNetworkSpeedSnapshot() ?? (uploadKBps: 0, downloadKBps: 0)
        let temperatureCelsius = bestEffortTemperatureCelsius()
        let fanSpeedRPM = bestEffortFanSpeedRPM()

        let currentUploadKBps = smooth(current: networkSnapshot.uploadKBps, previous: smoothedUploadKBps)
        let currentDownloadKBps = smooth(current: networkSnapshot.downloadKBps, previous: smoothedDownloadKBps)
        smoothedUploadKBps = currentUploadKBps
        smoothedDownloadKBps = currentDownloadKBps

        appendHistory(uploadKBps: currentUploadKBps, downloadKBps: currentDownloadKBps)

        let metrics = SystemMonitorMetrics(
            cpuUsagePercent: cpuUsagePercent,
            memoryUsedGB: memorySnapshot.usedGB,
            memoryTotalGB: memorySnapshot.totalGB,
            diskUsedGB: diskSnapshot.usedGB,
            diskTotalGB: diskSnapshot.totalGB,
            uploadSpeedKBps: currentUploadKBps,
            downloadSpeedKBps: currentDownloadKBps,
            temperatureCelsius: temperatureCelsius,
            fanSpeedRPM: fanSpeedRPM,
            uploadHistoryKBps: uploadHistoryKBps,
            downloadHistoryKBps: downloadHistoryKBps
        )

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(metrics)
        }
    }

    /// 维护固定长度的网速历史，用于驱动主窗口里的实时趋势图。
    private func appendHistory(uploadKBps: Double, downloadKBps: Double) {
        uploadHistoryKBps.append(max(0, uploadKBps))
        downloadHistoryKBps.append(max(0, downloadKBps))

        let maxSampleCount = 30
        if uploadHistoryKBps.count > maxSampleCount {
            uploadHistoryKBps.removeFirst(uploadHistoryKBps.count - maxSampleCount)
        }
        if downloadHistoryKBps.count > maxSampleCount {
            downloadHistoryKBps.removeFirst(downloadHistoryKBps.count - maxSampleCount)
        }
    }

    /// 对网速采样做轻量平滑，减少数字和曲线跳变。
    private func smooth(current: Double, previous: Double) -> Double {
        let alpha = previous == 0 ? 1.0 : 0.18
        return (current * alpha) + (previous * (1 - alpha))
    }

    /// 使用 CPU tick 差值计算瞬时占用率，首次采样没有基线时返回 nil。
    private func currentCPUUsagePercent() -> Double? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        let tickCount = Int(cpuInfoCount)
        let currentTicks = Array(UnsafeBufferPointer(start: cpuInfo, count: tickCount)).map(UInt32.init)

        let releaseSize = vm_size_t(tickCount * MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), releaseSize)

        defer {
            previousCPUTicks = currentTicks
        }

        guard let previousCPUTicks, previousCPUTicks.count == currentTicks.count else {
            return nil
        }

        var usedTicks: UInt64 = 0
        var totalTicks: UInt64 = 0

        for index in stride(from: 0, to: currentTicks.count, by: Int(CPU_STATE_MAX)) {
            let user = UInt64(currentTicks[index + Int(CPU_STATE_USER)] - previousCPUTicks[index + Int(CPU_STATE_USER)])
            let system = UInt64(currentTicks[index + Int(CPU_STATE_SYSTEM)] - previousCPUTicks[index + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(currentTicks[index + Int(CPU_STATE_IDLE)] - previousCPUTicks[index + Int(CPU_STATE_IDLE)])
            let nice = UInt64(currentTicks[index + Int(CPU_STATE_NICE)] - previousCPUTicks[index + Int(CPU_STATE_NICE)])

            usedTicks += user + system + nice
            totalTicks += user + system + idle + nice
        }

        guard totalTicks > 0 else {
            return nil
        }

        return (Double(usedTicks) / Double(totalTicks)) * 100
    }

    /// 读取内存总量与已使用量，已使用量以 active/wired/compressed 为主。
    private func currentMemorySnapshot() -> (usedGB: Double, totalGB: Double)? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let usedPages = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        return (
            usedGB: Double(usedBytes) / 1_073_741_824,
            totalGB: Double(totalBytes) / 1_073_741_824
        )
    }

    /// 读取当前文件系统总容量与已用容量。
    private func currentDiskSnapshot() -> (usedGB: Double, totalGB: Double)? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let totalBytes = (attributes[.systemSize] as? NSNumber)?.uint64Value,
              let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value else {
            return nil
        }

        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return (
            usedGB: Double(usedBytes) / 1_073_741_824,
            totalGB: Double(totalBytes) / 1_073_741_824
        )
    }

    /// 统计所有非回环网卡的上传下载总字节数，再按相邻采样间隔换算成 KB/s。
    private func currentNetworkSpeedSnapshot() -> (uploadKBps: Double, downloadKBps: Double)? {
        guard let currentCounters = currentNetworkCounters() else {
            return nil
        }

        let now = Date()
        let sample = NetworkCounterSample(
            receivedBytes: currentCounters.receivedBytes,
            sentBytes: currentCounters.sentBytes,
            capturedAt: now
        )

        defer {
            lastNetworkSample = sample
        }

        guard let lastNetworkSample else {
            return (0, 0)
        }

        let elapsed = now.timeIntervalSince(lastNetworkSample.capturedAt)
        guard elapsed > 0 else {
            return (0, 0)
        }

        let receivedDelta = currentCounters.receivedBytes >= lastNetworkSample.receivedBytes
        ? currentCounters.receivedBytes - lastNetworkSample.receivedBytes
        : 0
        let sentDelta = currentCounters.sentBytes >= lastNetworkSample.sentBytes
        ? currentCounters.sentBytes - lastNetworkSample.sentBytes
        : 0

        return (
            uploadKBps: Double(sentDelta) / elapsed / 1024,
            downloadKBps: Double(receivedDelta) / elapsed / 1024
        )
    }

    private func currentNetworkCounters() -> (receivedBytes: UInt64, sentBytes: UInt64)? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }

        defer {
            freeifaddrs(addressPointer)
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0", (interface.ifa_flags & UInt32(IFF_UP)) != 0 else {
                continue
            }

            guard let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                continue
            }

            receivedBytes += UInt64(data.pointee.ifi_ibytes)
            sentBytes += UInt64(data.pointee.ifi_obytes)
        }

        return (receivedBytes, sentBytes)
    }

    /// 温度先做 best effort；当前读不到时返回 nil，让 UI 保持占位。
    private func bestEffortTemperatureCelsius() -> Double? {
        nil
    }

    /// 风扇转速先做 best effort；当前读不到时返回 nil，让 UI 保持占位。
    private func bestEffortFanSpeedRPM() -> Double? {
        nil
    }
}
