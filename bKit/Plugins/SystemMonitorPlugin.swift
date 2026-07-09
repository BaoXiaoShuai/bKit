//
//  SystemMonitorPlugin.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Combine 状态发布能力
import Combine
// Foundation 基础类型
import Foundation

struct SystemMonitorSnapshot: Equatable {
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

    /// 计算内存占用比例，供主窗口 Dashboard 进度展示使用。
    var memoryUsagePercent: Double {
        guard memoryTotalGB > 0 else { return 0 }
        return (memoryUsedGB / memoryTotalGB) * 100
    }

    /// 计算磁盘占用比例，供主窗口 Dashboard 进度展示使用。
    var diskUsagePercent: Double {
        guard diskTotalGB > 0 else { return 0 }
        return (diskUsedGB / diskTotalGB) * 100
    }
}

@MainActor
final class SystemMonitorPlugin: BasePlugin {
    @Published private(set) var snapshot: SystemMonitorSnapshot

    let settings: SystemMonitorSettings

    private let service: SystemMonitorService

    init() {
        settings = SystemMonitorSettings()
        service = SystemMonitorService()
        snapshot = SystemMonitorSnapshot(
            cpuUsagePercent: 21.4,
            memoryUsedGB: 18.6,
            memoryTotalGB: 36.0,
            diskUsedGB: 412.3,
            diskTotalGB: 1024.0,
            uploadSpeedKBps: 186.0,
            downloadSpeedKBps: 824.0,
            temperatureCelsius: nil,
            fanSpeedRPM: nil,
            uploadHistoryKBps: [186.0, 220.0, 160.0, 240.0, 180.0],
            downloadHistoryKBps: [824.0, 760.0, 910.0, 840.0, 790.0]
        )

        super.init(
            id: "system-monitor",
            name: "系统监控",
            description: "预留 CPU、内存、磁盘、实时上传下载网速监控入口。",
            icon: "waveform.path.ecg.rectangle",
            isEnabled: true,
            status: .stopped
        )

        // 统一把底层采集结果映射为插件快照，保持 UI 读取入口稳定。
        service.onUpdate = { [weak self] metrics in
            guard let self else { return }
            self.snapshot = SystemMonitorSnapshot(
                cpuUsagePercent: metrics.cpuUsagePercent,
                memoryUsedGB: metrics.memoryUsedGB,
                memoryTotalGB: metrics.memoryTotalGB,
                diskUsedGB: metrics.diskUsedGB,
                diskTotalGB: metrics.diskTotalGB,
                uploadSpeedKBps: metrics.uploadSpeedKBps,
                downloadSpeedKBps: metrics.downloadSpeedKBps,
                temperatureCelsius: metrics.temperatureCelsius,
                fanSpeedRPM: metrics.fanSpeedRPM,
                uploadHistoryKBps: metrics.uploadHistoryKBps,
                downloadHistoryKBps: metrics.downloadHistoryKBps
            )
        }
    }

    /// 启动系统监控采集服务，并持续刷新快照数据。
    override func start() {
        service.start()
        updateStatus(.running)
    }

    /// 停止系统监控采集服务。
    override func stop() {
        service.stop()
        updateStatus(.stopped)
    }
}
