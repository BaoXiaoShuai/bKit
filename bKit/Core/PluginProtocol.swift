//
//  PluginProtocol.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Foundation 基础类型
import Foundation

@MainActor
protocol PluginProtocol: AnyObject, Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var icon: String { get }
    var isEnabled: Bool { get set }
    var status: PluginStatus { get }

    /// 启动插件服务，插件内部自行决定需要监听、轮询或加载哪些资源。
    func start()

    /// 停止插件服务，插件内部需要释放定时器、监听器等运行态资源。
    func stop()
}
