//
//  ClipboardHistoryOverlaySupport.swift
//  bPaste
//
//  Created by 鲍小帅 on 2026/3/12.
//

import AppKit
import SwiftUI

// 这个文件集中管理历史窗口和 AppKit 浮层之间的桥接：
// 1. 屏幕坐标采集
// 2. 下拉菜单浮层
// 3. 悬浮详情浮层
// 这些能力都比较依赖 NSPanel 和屏幕坐标，不和主 View 混在一起更易维护。

struct ScreenFrameReader: NSViewRepresentable {
    @Binding var frame: CGRect

    func makeNSView(context: Context) -> ScreenFrameReportingView {
        let view = ScreenFrameReportingView()
        view.onFrameChange = { rect in
            DispatchQueue.main.async {
                guard self.frame != rect else { return }
                self.frame = rect
            }
        }
        return view
    }

    func updateNSView(_ nsView: ScreenFrameReportingView, context: Context) {
        nsView.onFrameChange = { rect in
            DispatchQueue.main.async {
                guard self.frame != rect else { return }
                self.frame = rect
            }
        }
        DispatchQueue.main.async {
            nsView.reportFrame()
        }
    }
}

final class ScreenFrameReportingView: NSView {
    var onFrameChange: ((CGRect) -> Void)?
    private var windowObservers: [NSObjectProtocol] = []

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshWindowObservers()
        refreshSuperviewObservers()
        reportFrame()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeWindowObservers()
        removeSuperviewObservers()
    }

    func reportFrame() {
        guard let window else { return }
        let rectInWindow = convert(bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        onFrameChange?(rectOnScreen)
    }

    private func refreshWindowObservers() {
        removeWindowObservers()

        guard let window else { return }
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification
        ]

        windowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.reportFrame()
            }
        }
    }

    private func refreshSuperviewObservers() {
        removeSuperviewObservers()
        
        // 监听所有父视图的 bounds 变化（主要是 ScrollView 滚动）
        var current = superview
        while let view = current {
            if view is NSClipView {
                view.postsBoundsChangedNotifications = true
                let observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: view,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
                windowObservers.append(observer)
            }
            current = view.superview
        }
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }

    private func removeSuperviewObservers() {
        // 由于我们将 superview observer 也存在 windowObservers 里统一管理，
        // 这里不需要额外操作，但为了语义清晰保留方法名。
    }

    deinit {
        removeWindowObservers()
    }
}

@MainActor
final class DropdownPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var dismissAction: (() -> Void)?
    private var passthroughFrames: [CGRect] = []

    func present(content: AnyView, anchorFrame: CGRect, width: CGFloat, passthroughFrames: [CGRect] = [], onDismiss: @escaping () -> Void) {
        dismissAction = onDismiss
        self.passthroughFrames = passthroughFrames

        let rootView = content
            .frame(width: width)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
            )

        let hostingView = NSHostingView(rootView: rootView)
        let size = hostingView.fittingSize
        let panel = panel ?? makePanel()

        panel.contentView = hostingView
        panel.setContentSize(size)
        panel.setFrame(
            NSRect(
                x: anchorFrame.minX,
                y: anchorFrame.minY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel.orderFront(nil)
        installDismissMonitors(for: panel)
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissMonitors()
        dismissAction = nil
        passthroughFrames = []
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func installDismissMonitors(for panel: NSPanel) {
        removeDismissMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            let point = event.window.map { $0.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin } ?? NSEvent.mouseLocation
            if !panel.frame.contains(point), !self.containsPassthroughPoint(point) {
                let dismissAction = self.dismissAction
                self.close()
                dismissAction?()
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            let point = NSEvent.mouseLocation
            if !panel.frame.contains(point), !self.containsPassthroughPoint(point) {
                Task { @MainActor in
                    let dismissAction = self.dismissAction
                    self.close()
                    dismissAction?()
                }
            }
        }
    }

    private func containsPassthroughPoint(_ point: CGPoint) -> Bool {
        passthroughFrames.contains { $0.contains(point) }
    }

    private func removeDismissMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}

@MainActor
final class HoverPreviewPanelController {
    private var panel: NSPanel?
    private var visibleItemID: ClipboardItem.ID?
    private let arrowSize = CGSize(width: 8, height: 22)
    private let cornerRadius: CGFloat = 14

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func present(
        itemID: ClipboardItem.ID,
        content: AnyView,
        anchorFrame: CGRect,
        width: CGFloat,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        visibleItemID = itemID
        let panel = panel ?? makePanel()
        let layout = layout(for: width, anchorFrame: anchorFrame)

        let measuringView = NSHostingView(
            rootView: HoverPreviewBubbleView(
                content: content,
                contentWidth: width,
                arrowEdge: layout.arrowEdge,
                arrowOffset: 140,
                arrowSize: arrowSize,
                cornerRadius: cornerRadius
            )
        )
        let size = measuringView.fittingSize
        let frame = frameForPanel(size: size, anchorFrame: anchorFrame, prefersRight: layout.prefersRight)
        let arrowOffset = max(
            cornerRadius + arrowSize.height / 2 + 4,
            min(
                size.height - cornerRadius - arrowSize.height / 2 - 4,
                frame.maxY - anchorFrame.midY
            )
        )
        let hostingView = NSHostingView(
            rootView: HoverPreviewBubbleView(
                content: content,
                contentWidth: width,
                arrowEdge: layout.arrowEdge,
                arrowOffset: arrowOffset,
                arrowSize: arrowSize,
                cornerRadius: cornerRadius
            )
            .onHover(perform: onHoverChanged)
        )

        panel.contentView = hostingView
        panel.setContentSize(size)
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        visibleItemID = nil
    }

    func isVisible(for itemID: ClipboardItem.ID) -> Bool {
        visibleItemID == itemID && panel?.isVisible == true
    }

    private func makePanel() -> NSPanel {
        let panel = HoverPreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // 详情窗背景和阴影都尽量和主历史面板保持一致。
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func layout(for width: CGFloat, anchorFrame: CGRect) -> (prefersRight: Bool, arrowEdge: Edge) {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)) })
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let horizontalSpacing: CGFloat = 12
        let prefersRight = anchorFrame.maxX + horizontalSpacing + width <= visibleFrame.maxX
        return (prefersRight, prefersRight ? .leading : .trailing)
    }

    private func frameForPanel(size: NSSize, anchorFrame: CGRect, prefersRight: Bool) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)) })
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let horizontalSpacing: CGFloat = 12
        let verticalMargin: CGFloat = 12

        let x = prefersRight
            ? anchorFrame.maxX + horizontalSpacing
            : max(visibleFrame.minX + verticalMargin, anchorFrame.minX - size.width - horizontalSpacing)

        // 详情窗始终以当前条目的垂直中心作为锚点，
        // 切换不同高度内容时不会再因为顶部对齐产生明显“漂移”。
        let proposedY = anchorFrame.midY - (size.height / 2)
        let y = min(
            max(visibleFrame.minY + verticalMargin, proposedY),
            visibleFrame.maxY - size.height - verticalMargin
        )

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private final class HoverPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct HoverPreviewBubbleView: View {
    let content: AnyView
    let contentWidth: CGFloat
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    let arrowSize: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        content
            .frame(width: contentWidth)
            .padding(contentPadding)
            .background(GlassBackground())
            .clipShape(bubbleShape)
            .overlay(
                bubbleShape
                    .stroke(Color.white.opacity(0.55), lineWidth: 0.8)
            )
    }

    private var contentPadding: EdgeInsets {
        switch arrowEdge {
        case .leading:
            return EdgeInsets(top: 0, leading: arrowSize.width, bottom: 0, trailing: 0)
        case .trailing:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: arrowSize.width)
        default:
            return EdgeInsets()
        }
    }

    private var bubbleShape: HoverPreviewBubbleShape {
        HoverPreviewBubbleShape(
            arrowEdge: arrowEdge,
            arrowOffset: arrowOffset,
            arrowSize: arrowSize,
            cornerRadius: cornerRadius
        )
    }
}

private struct HoverPreviewBubbleShape: Shape {
    let arrowEdge: Edge
    let arrowOffset: CGFloat
    let arrowSize: CGSize
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let arrowHalfHeight = arrowSize.height / 2
        let arrowMidY = max(
            cornerRadius + arrowHalfHeight + 4,
            min(rect.height - cornerRadius - arrowHalfHeight - 4, arrowOffset)
        )
        let bubbleRect = arrowEdge == .leading
            ? CGRect(x: rect.minX + arrowSize.width, y: rect.minY, width: rect.width - arrowSize.width, height: rect.height)
            : arrowEdge == .trailing
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - arrowSize.width, height: rect.height)
            : rect

        return Path { path in
            switch arrowEdge {
            case .leading:
                path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
                path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + cornerRadius),
                    control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY),
                    control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - cornerRadius),
                    control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.minX, y: arrowMidY + arrowHalfHeight))
                
                // 简单的三角形箭头
                path.addLine(to: CGPoint(x: rect.minX, y: arrowMidY))
                path.addLine(to: CGPoint(x: bubbleRect.minX, y: arrowMidY - arrowHalfHeight))
                
                path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY),
                    control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
                )

            case .trailing:
                path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
                path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + cornerRadius),
                    control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.maxX, y: arrowMidY - arrowHalfHeight))
                
                // 简单的三角形箭头
                path.addLine(to: CGPoint(x: rect.maxX, y: arrowMidY))
                path.addLine(to: CGPoint(x: bubbleRect.maxX, y: arrowMidY + arrowHalfHeight))
                
                path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY),
                    control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - cornerRadius),
                    control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
                )
                path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
                path.addQuadCurve(
                    to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY),
                    control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
                )

            default:
                path.addRoundedRect(in: bubbleRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            }

            path.closeSubpath()
        }
    }
}
