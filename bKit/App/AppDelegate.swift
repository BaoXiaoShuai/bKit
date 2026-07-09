//
//  AppDelegate.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 应用生命周期
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用启动后切换为 accessory，避免在 Dock 栏显示普通应用图标。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
