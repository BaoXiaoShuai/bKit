//
//  HistoryPanel.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit

// 无标题栏的 NSPanel 默认不一定愿意成为 key window。
// 搜索框无法输入，根因通常就是窗口本身拿不到稳定的键盘焦点。
// 这里显式允许它成为 key/main window，这样文本输入、焦点切换才会正常。
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
