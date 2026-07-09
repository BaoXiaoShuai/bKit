//
//  KeyboardShortcut.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Carbon

// 这是我们自己的快捷键模型。
// 用它把“按键 + 修饰键”统一表示成一个可保存、可展示、可注册的值对象。
struct KeyboardShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    // macOS 键盘里 C 的 keyCode 是 8，所以这里对应默认快捷键 Command + Shift + C。
    static let `default` = KeyboardShortcut(keyCode: 8, modifiers: [.command, .shift])

    // Carbon 的全局热键注册 API 使用的是另一套修饰键常量，
    // 这里把 AppKit 的修饰键转换成 Carbon 所需的值。
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    // 用于在 UI 上显示快捷键，例如“⇧⌘C”。
    var displayString: String {
        "\(modifierGlyphs)\(keyDisplay)"
    }

    private var modifierGlyphs: String {
        var result = ""
        if modifiers.contains(.control) { result += "^" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private var keyDisplay: String {
        // 这里只映射了当前项目里最常见的一些按键。
        // 如果后续你要支持更完整的键盘录制，可以继续扩展这个映射表。
        switch keyCode {
        case 0...25:
            let map: [UInt32: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
                8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
                16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
                38: "J", 40: "K", 45: "N", 46: "M"
            ]
            return map[keyCode] ?? "Key \(keyCode)"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 36: return "Return"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Esc"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}
