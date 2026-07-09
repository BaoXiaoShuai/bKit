//
//  BasePlugin.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Combine 状态发布能力
import Combine
// Foundation 基础类型
import Foundation

@MainActor
class BasePlugin: ObservableObject, PluginProtocol {
    let id: String
    let name: String
    let description: String
    let icon: String

    @Published var isEnabled: Bool
    @Published private(set) var status: PluginStatus

    init(
        id: String,
        name: String,
        description: String,
        icon: String,
        isEnabled: Bool = false,
        status: PluginStatus = .stopped
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isEnabled = isEnabled
        self.status = status
    }

    /// 更新插件运行状态，统一收敛状态写入入口。
    func updateStatus(_ status: PluginStatus) {
        self.status = status
    }

    /// 启动插件基础占位逻辑，子类按需覆盖。
    func start() {
        updateStatus(.running)
    }

    /// 停止插件基础占位逻辑，子类按需覆盖。
    func stop() {
        updateStatus(.stopped)
    }
}
