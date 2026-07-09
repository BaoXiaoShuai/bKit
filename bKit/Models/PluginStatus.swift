//
//  PluginStatus.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// Foundation 基础类型
import Foundation

enum PluginStatus: Equatable {
    case stopped
    case running
    case error(message: String)
    case unavailable(reason: String)

    var title: String {
        switch self {
        case .stopped:
            return "已停用"
        case .running:
            return "运行中"
        case .error:
            return "异常"
        case .unavailable:
            return "不可用"
        }
    }

    var detail: String? {
        switch self {
        case .stopped, .running:
            return nil
        case .error(let message):
            return message
        case .unavailable(let reason):
            return reason
        }
    }
}
