//
//  bKitApp.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// SwiftUI 应用入口
import SwiftUI

@main
struct bKitApp: App {
    // 注入 AppKit 生命周期，用于设置菜单栏常驻模式。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // 应用级状态，负责插件、状态栏、主面板和设置窗口的装配。
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
