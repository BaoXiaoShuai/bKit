//
//  ClipboardSourceApp.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit

// 记录复制动作发生时的前台应用信息，
// 用于在历史列表里展示“从哪个应用复制”的图标和名称。
struct ClipboardSourceApp {
    let name: String?
    let bundleIdentifier: String?

    init(runningApplication: NSRunningApplication?) {
        name = runningApplication?.localizedName
        bundleIdentifier = runningApplication?.bundleIdentifier
    }
}
