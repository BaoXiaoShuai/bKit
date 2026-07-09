//
//  ClipboardMonitor.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/11.
//

import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipboardStore
    private let settings: SettingsStore
    private var lastChangeCount: Int
    private var timer: Timer?

    init(store: ClipboardStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        // macOS 对剪贴板变化没有直接的高层回调，
        // 第一版最稳妥的方式就是轮询 NSPasteboard.changeCount。
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.captureIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func captureIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !settings.isCapturePaused else { return }

        // 在剪贴板变化发生时抓一份当前前台应用信息，
        // 后续展示历史时可以知道内容来自微信、Chrome、Xcode 等哪个应用。
        let sourceApp = ClipboardSourceApp(runningApplication: NSWorkspace.shared.frontmostApplication)

        if let fileURLs = copiedFileURLs, !fileURLs.isEmpty {
            store.addFiles(urls: fileURLs, sourceApp: sourceApp)
            return
        }

        // 优先读取文本，其次读取 png/tiff 图片。
        // 第一版不处理文件、富文本、HTML 等更复杂内容。
        if let text = pasteboard.string(forType: .string) {
            store.addText(text, sourceApp: sourceApp)
            return
        }

        if let pngData = pasteboard.data(forType: .png) {
            store.addImage(data: pngData, sourceApp: sourceApp)
            return
        }

        if
            let tiffData = pasteboard.data(forType: .tiff),
            let image = NSImage(data: tiffData),
            let pngData = image.pngData()
        {
            store.addImage(data: pngData, sourceApp: sourceApp)
        }
    }

    private var copiedFileURLs: [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
    }
}

private extension NSImage {
    func pngData() -> Data? {
        // 历史图片统一转成 png 存储，便于后续展示和体积估算。
        guard
            let tiffData = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
