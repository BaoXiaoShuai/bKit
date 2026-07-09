//
//  SystemMonitorSettings.swift
//  bKit
//
//  Created by Codex on 2026/7/8.
//

// Combine 状态发布能力
import Combine
// 数据持久化基础库
import Foundation

final class SystemMonitorSettings: ObservableObject {
    @Published var showStatusBarUpload: Bool {
        didSet { defaults.set(showStatusBarUpload, forKey: Keys.showStatusBarUpload) }
    }

    @Published var showStatusBarDownload: Bool {
        didSet { defaults.set(showStatusBarDownload, forKey: Keys.showStatusBarDownload) }
    }

    private let defaults: UserDefaults

    /// 初始化系统监控配置，并从本地存储读取状态栏展示开关。
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showStatusBarUpload = defaults.object(forKey: Keys.showStatusBarUpload) as? Bool ?? true
        showStatusBarDownload = defaults.object(forKey: Keys.showStatusBarDownload) as? Bool ?? true
    }

    private enum Keys {
        static let showStatusBarUpload = "systemMonitor.statusBar.showUpload"
        static let showStatusBarDownload = "systemMonitor.statusBar.showDownload"
    }
}
