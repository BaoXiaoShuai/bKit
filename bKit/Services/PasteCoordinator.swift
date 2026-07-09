//
//  PasteCoordinator.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class PasteCoordinator {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func restoreAndPaste(_ item: ClipboardItem, targetApp: NSRunningApplication?) {
        // 先把内容写回系统剪贴板，再切回原应用执行一次 Command + V。
        store.restoreToPasteboard(item)

        guard let targetApp else { return }

#if DEBUG
        let targetName = targetApp.localizedName ?? "unknown"
        print(
            "[PasteFlow] restore item=\(item.id.uuidString) kind=\(item.kind.rawValue) target=\(targetName)"
        )
#endif

        targetApp.activate(options: [])

        let pasteDelay: TimeInterval = item.kind == .file ? 0.28 : 0.12

        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
#if DEBUG
            print("[PasteFlow] sendPasteShortcut delay=\(pasteDelay)")
#endif
            Self.sendPasteShortcut()
        }
    }

    private static func sendPasteShortcut() {
        // 模拟一次全局的 Command + V。
        // 这依赖系统允许应用发送辅助功能键盘事件。
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
