//
//  ClipboardPlugin.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Foundation 基础类型
import Foundation

@MainActor
final class ClipboardPlugin: BasePlugin {
    let settings: SettingsStore
    let store: ClipboardStore

    private let monitor: ClipboardMonitor

    init() {
        let settings = SettingsStore()
        let store = ClipboardStore(settings: settings)

        self.settings = settings
        self.store = store
        monitor = ClipboardMonitor(store: store, settings: settings)

        super.init(
            id: "clipboard",
            name: "剪切板",
            description: "记录文本、图片和文件复制历史，支持恢复到系统剪切板。",
            icon: "doc.on.clipboard",
            isEnabled: true,
            status: .stopped
        )

        store.bootstrapIfNeeded()
    }

    /// 启动剪切板插件，开始监听系统剪切板变化。
    override func start() {
        monitor.start()
        updateStatus(.running)
    }

    /// 停止剪切板插件，暂停剪切板监听。
    override func stop() {
        monitor.stop()
        updateStatus(.stopped)
    }
}
