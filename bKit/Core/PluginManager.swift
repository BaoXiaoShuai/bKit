//
//  PluginManager.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Combine 状态发布能力
import Combine
// Foundation 基础类型
import Foundation

@MainActor
final class PluginManager: ObservableObject {
    @Published private(set) var plugins: [BasePlugin] = []

    private var pluginCancellables: [String: AnyCancellable] = [:]

    /// 注册插件实例，并绑定插件自身状态变化到插件列表刷新。
    func register(_ plugin: BasePlugin) {
        guard !plugins.contains(where: { $0.id == plugin.id }) else { return }
        plugins.append(plugin)

        pluginCancellables[plugin.id] = plugin.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if plugin.isEnabled {
            plugin.start()
        }
    }

    /// 根据插件 id 查找插件实例，找不到时返回 nil。
    func plugin(id: String) -> BasePlugin? {
        plugins.first { $0.id == id }
    }

    /// 启用指定插件，并触发插件启动流程。
    func enablePlugin(id: String) {
        guard let plugin = plugin(id: id), !plugin.isEnabled else { return }
        plugin.isEnabled = true
        plugin.start()
    }

    /// 停用指定插件，并触发插件停止流程。
    func disablePlugin(id: String) {
        guard let plugin = plugin(id: id), plugin.isEnabled else { return }
        plugin.isEnabled = false
        plugin.stop()
    }

    /// 切换指定插件启用状态，便于 UI 开关直接调用。
    func togglePlugin(id: String) {
        guard let plugin = plugin(id: id) else { return }

        if plugin.isEnabled {
            disablePlugin(id: id)
        } else {
            enablePlugin(id: id)
        }
    }
}
