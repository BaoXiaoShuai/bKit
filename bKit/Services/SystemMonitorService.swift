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

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyDataVers {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyDataPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyDataKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCKeyDataVers()
    var pLimitData = SMCKeyDataPLimitData()
    var keyInfo = SMCKeyDataKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                           UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
}

private struct SMCVal {
    var key: String = ""
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
}

private final class SMCReader {
    private enum Command: UInt8 {
        case kernelIndex = 2
        case readBytes = 5
        case readKeyInfo = 9
    }

    private let temperatureKeys = [
        "Te05", "Te0S", "Te09", "Te0H",
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
        "mTPL", "TC0P", "TC0E", "TC0F"
    ]
    private let debugEnabled = ProcessInfo.processInfo.environment["BKIT_SMC_DEBUG"] == "1"

    private var connection: io_connect_t = 0

    deinit {
        close()
    }

    /// 读取当前 CPU 温度，优先命中本机 Apple Silicon 上可用的温度 key。
    func currentTemperatureCelsius() -> Double? {
        guard open() else { return nil }
        var values: [Double] = []

        for key in temperatureKeys {
            guard let temperature = readNumericValue(for: key) else {
                debugLog("temperature key=\(key) read failed")
                continue
            }

            guard temperature >= 10, temperature <= 120 else {
                debugLog("temperature key=\(key) value=\(String(format: "%.2f", temperature)) filtered")
                continue
            }

            debugLog("temperature key=\(key) value=\(String(format: "%.2f", temperature))")
            values.append(temperature)
        }

        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 读取当前风扇转速，优先取本机实际存在风扇中的最高转速。
    func currentFanSpeedRPM() -> Double? {
        guard open() else { return nil }
        guard let fanCount = readNumericValue(for: "FNum") else {
            debugLog("fan count key=FNum read failed")
            return nil
        }

        var values: [Double] = []
        for index in 0..<max(1, Int(fanCount.rounded())) {
            let key = "F\(index)Ac"
            guard let rpm = readNumericValue(for: key) else {
                debugLog("fan key=\(key) read failed")
                continue
            }

            guard rpm > 0 else {
                debugLog("fan key=\(key) value=\(String(format: "%.0f", rpm)) filtered")
                continue
            }

            debugLog("fan key=\(key) value=\(String(format: "%.0f", rpm))")
            values.append(rpm)
        }

        return values.max()
    }

    /// 建立 AppleSMC user client 连接，连接已存在时直接复用。
    private func open() -> Bool {
        if connection != 0 {
            return true
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            debugLog("open failed: AppleSMC service not found")
            return false
        }

        defer {
            IOObjectRelease(service)
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result != KERN_SUCCESS {
            debugLog("open failed: IOServiceOpen result=\(result)")
            connection = 0
            return false
        }

        debugLog("open success")
        return true
    }

    /// 关闭 AppleSMC 连接，避免后台采集停止后仍持有 user client。
    private func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    /// 按 key 读取 SMC 原始值，失败时返回 nil 由上层继续走其他候选 key。
    private func readValue(for key: String) -> SMCVal? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        var value = SMCVal()

        input.key = fourCharCode(from: key)
        input.data8 = Command.readKeyInfo.rawValue

        let keyInfoResult = callSmc(input: &input, output: &output)
        guard keyInfoResult == KERN_SUCCESS else {
            debugLog("keyInfo failed key=\(key) result=\(keyInfoResult)")
            return nil
        }

        value.key = key
        value.dataSize = output.keyInfo.dataSize
        value.dataType = string(from: output.keyInfo.dataType)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue

        let readBytesResult = callSmc(input: &input, output: &output)
        guard readBytesResult == KERN_SUCCESS else {
            debugLog("readBytes failed key=\(key) result=\(readBytesResult)")
            return nil
        }

        value.bytes = bytesArray(from: output.bytes)
        return value
    }

    /// 统一读取并解析 SMC 数值，便于温度与风扇逻辑复用。
    private func readNumericValue(for key: String) -> Double? {
        guard let value = readValue(for: key) else {
            return nil
        }

        guard let decoded = decodeNumericValue(value) else {
            debugLog("numeric key=\(key) type=\(value.dataType) bytes=\(hexBytes(value.bytes, count: 4)) decode failed")
            return nil
        }

        debugLog("numeric key=\(key) type=\(value.dataType) bytes=\(hexBytes(value.bytes, count: 4)) value=\(String(format: "%.2f", decoded))")
        return decoded
    }

    /// 调用 AppleSMC struct method，沿用 SMC 常见的读 key 协议。
    private func callSmc(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        var inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        return withUnsafeMutablePointer(to: &input) { inputPointer in
            inputPointer.withMemoryRebound(to: UInt8.self, capacity: inputSize) { inputBytes in
                withUnsafeMutablePointer(to: &output) { outputPointer in
                    outputPointer.withMemoryRebound(to: UInt8.self, capacity: outputSize) { outputBytes in
                        IOConnectCallStructMethod(
                            connection,
                            UInt32(Command.kernelIndex.rawValue),
                            inputBytes,
                            inputSize,
                            outputBytes,
                            &outputSize
                        )
                    }
                }
            }
        }
    }

    /// 解析 SMC 数值编码，兼容温度和风扇常见的几种数据格式。
    private func decodeNumericValue(_ value: SMCVal) -> Double? {
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 256
        case "sp96":
            guard value.bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 64
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            let bits = UInt32(value.bytes[0]) | UInt32(value.bytes[1]) << 8 | UInt32(value.bytes[2]) << 16 | UInt32(value.bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw)
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4
        case "ui8 ":
            guard let firstByte = value.bytes.first else { return nil }
            return Double(firstByte)
        case "ui32":
            guard value.bytes.count >= 4 else { return nil }
            let raw = UInt32(value.bytes[0]) << 24 | UInt32(value.bytes[1]) << 16 | UInt32(value.bytes[2]) << 8 | UInt32(value.bytes[3])
            return Double(raw)
        default:
            return nil
        }
    }

    /// 把四字符 key 转成 SMC 调用需要的 UInt32。
    private func fourCharCode(from string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }

    /// 把 SMC 的 data type 四字节转回字符串，便于上层按编码分支解析。
    private func string(from value: UInt32) -> String {
        let scalars = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: scalars, encoding: .macOSRoman) ?? ""
    }

    /// 展开固定 32 字节元组，统一给温度和风扇解析逻辑复用。
    private func bytesArray(from bytes: SMCBytes) -> [UInt8] {
        [
            bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11, bytes.12, bytes.13, bytes.14, bytes.15,
            bytes.16, bytes.17, bytes.18, bytes.19, bytes.20, bytes.21, bytes.22, bytes.23,
            bytes.24, bytes.25, bytes.26, bytes.27, bytes.28, bytes.29, bytes.30, bytes.31
        ]
    }

    /// 只在显式调试开关打开时输出底层 SMC 读数证据，避免污染正常日志。
    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[SMC] \(message)")
    }

    /// 截取前几个字节做十六进制展示，便于判断本机返回编码格式。
    private func hexBytes(_ bytes: [UInt8], count: Int) -> String {
        bytes.prefix(count).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
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
    private let preferredNetworkPrefixes = ["en", "bridge", "pdp_ip", "utun"]
    private let smcReader = SMCReader()
    private let debugEnabled = ProcessInfo.processInfo.environment["BKIT_SMC_DEBUG"] == "1"

    func start() {
        stop()
        debugLog("service start")

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
        debugLog("capture cpu=\(String(format: "%.1f", cpuUsagePercent)) temp=\(temperatureCelsius.map { String(format: "%.2f", $0) } ?? "nil") fan=\(fanSpeedRPM.map { String(format: "%.0f", $0) } ?? "nil")")

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

    /// 统计优先网卡的上传下载总字节数，再按相邻采样间隔换算成 KB/s。
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

    /// 汇总当前活跃网卡流量，优先选择真实业务网卡，拿不到时再回退到全部可用网卡。
    private func currentNetworkCounters() -> (receivedBytes: UInt64, sentBytes: UInt64)? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }

        defer {
            freeifaddrs(addressPointer)
        }

        var preferredReceivedBytes: UInt64 = 0
        var preferredSentBytes: UInt64 = 0
        var fallbackReceivedBytes: UInt64 = 0
        var fallbackSentBytes: UInt64 = 0
        var hasPreferredInterface = false

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

            let receivedBytes = UInt64(data.pointee.ifi_ibytes)
            let sentBytes = UInt64(data.pointee.ifi_obytes)

            fallbackReceivedBytes += receivedBytes
            fallbackSentBytes += sentBytes

            if isPreferredNetworkInterface(name) {
                preferredReceivedBytes += receivedBytes
                preferredSentBytes += sentBytes
                hasPreferredInterface = true
            }
        }

        if hasPreferredInterface {
            return (preferredReceivedBytes, preferredSentBytes)
        }

        return (fallbackReceivedBytes, fallbackSentBytes)
    }

    /// 判断网卡是否更接近真实网络流量入口，优先过滤掉噪声较大的虚拟接口。
    private func isPreferredNetworkInterface(_ name: String) -> Bool {
        preferredNetworkPrefixes.contains { name.hasPrefix($0) }
    }

    /// 温度先做 best effort；当前读不到时返回 nil，让 UI 保持占位。
    private func bestEffortTemperatureCelsius() -> Double? {
        smcReader.currentTemperatureCelsius()
    }

    /// 风扇转速先做 best effort；当前读不到时返回 nil，让 UI 保持占位。
    private func bestEffortFanSpeedRPM() -> Double? {
        smcReader.currentFanSpeedRPM()
    }

    /// 调试模式下输出系统监控服务生命周期，帮助确认采样链路是否真的启动。
    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        print("[SystemMonitor] \(message)")
    }
}
