//
//  CodexQuotaPlugin.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Foundation 基础类型
import Foundation

@MainActor
final class CodexQuotaPlugin: BasePlugin {
    let settings: CodexQuotaSettings
    let store: CodexQuotaStore

    init() {
        let settings = CodexQuotaSettings()
        let store = CodexQuotaStore(settings: settings)
        self.settings = settings
        self.store = store

        super.init(
            id: "codex-quota",
            name: "Codex 额度监控",
            description: "展示 5 小时额度、7 天额度、刷新时间和节奏状态。",
            icon: "gauge.with.dots.needle.bottom.50percent",
            isEnabled: true,
            status: .stopped
        )
    }

    /// 启动 Codex 额度监控，并开始自动刷新。
    override func start() {
        store.loadCache()
        store.startAutoRefresh()
        store.refresh(reason: "plugin-start")
        updateStatus(.running)
    }

    /// 停止 Codex 额度监控自动刷新。
    override func stop() {
        store.stopAutoRefresh()
        updateStatus(.stopped)
    }
}
