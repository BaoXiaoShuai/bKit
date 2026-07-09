//
//  HotKeyManager.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Carbon

// 这里使用 Carbon 的 RegisterEventHotKey 来注册全局快捷键。
// 原因是它对 macOS 全局热键来说足够直接，而且不需要额外第三方依赖。
final class HotKeyManager {
    var onHotKeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    private(set) var registeredShortcut: KeyboardShortcut?

    init(signature: OSType = OSType(0x42504153), id: UInt32 = 1) {
        self.hotKeyID = EventHotKeyID(signature: signature, id: id)
        installHandler()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @discardableResult
    func register(shortcut: KeyboardShortcut) -> Bool {
        let previousShortcut = registeredShortcut
        let previousHotKeyRef = hotKeyRef

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        // 每次快捷键变更时，都先注销旧热键，再注册新热键。
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, hotKeyRef != nil else {
            registeredShortcut = nil

            // 如果新快捷键注册失败，就尽量把旧快捷键恢复回来，避免出现“彻底打不开”的状态。
            if let previousShortcut {
                var restoredRef: EventHotKeyRef?
                let restoreStatus = RegisterEventHotKey(
                    previousShortcut.keyCode,
                    previousShortcut.carbonModifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &restoredRef
                )

                if restoreStatus == noErr {
                    hotKeyRef = restoredRef
                    registeredShortcut = previousShortcut
                } else {
                    hotKeyRef = previousHotKeyRef
                }
            }

            return false
        }

        registeredShortcut = shortcut
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registeredShortcut = nil
    }

    private func installHandler() {
        // 安装一个应用级事件处理器，用来接收全局热键按下事件。
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard
                    let userData,
                    let eventRef
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr,
                      hotKeyID.signature == manager.hotKeyID.signature,
                      hotKeyID.id == manager.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                // 这里不直接做 UI 操作，只回调给上层控制器。
                manager.onHotKeyPressed?()
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
