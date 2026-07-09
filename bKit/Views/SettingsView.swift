//
//  SettingsView.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 快捷键录制能力
import AppKit
// SwiftUI 设置界面
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case clipboard
    case codexQuota
    case systemMonitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .clipboard:
            return "剪切板"
        case .codexQuota:
            return "Codex 额度"
        case .systemMonitor:
            return "系统监控"
        }
    }
}

struct SettingsView: View {
    private enum Preset {
        static let retentionDays = [30, 60]
        static let historyVisibleLimits = [30, 50, 60, 90, 120, 150, 200, 250, 300, 0]
    }

    @ObservedObject var settings: SettingsStore
    @ObservedObject var pluginManager: PluginManager
    let clearHistory: () -> Void

    @State private var selectedTab: SettingsTab = .general
    @State private var isConfirmingClearHistory = false

    private var localizer: Localizer {
        Localizer(language: settings.language)
    }

    private var clipboardPlugin: BasePlugin? {
        pluginManager.plugin(id: "clipboard")
    }

    private var codexQuotaPlugin: BasePlugin? {
        pluginManager.plugin(id: "codex-quota")
    }

    private var systemMonitorPlugin: BasePlugin? {
        pluginManager.plugin(id: "system-monitor")
    }

    private var codexQuotaTypedPlugin: CodexQuotaPlugin? {
        pluginManager.plugin(id: "codex-quota") as? CodexQuotaPlugin
    }

    private var systemMonitorTypedPlugin: SystemMonitorPlugin? {
        pluginManager.plugin(id: "system-monitor") as? SystemMonitorPlugin
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(localizer.clearHistoryConfirmTitle, isPresented: $isConfirmingClearHistory) {
            Button(localizer.cancelAction, role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button(localizer.clearHistoryConfirmAction, role: .destructive) {
                clearHistory()
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text(localizer.clearHistoryConfirmMessage)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:
            generalSettingsContent
        case .clipboard:
            clipboardSettingsContent
        case .codexQuota:
            codexQuotaSettingsContent
        case .systemMonitor:
            systemMonitorSettingsContent
        }
    }

    private var generalSettingsContent: some View {
        ScrollView {
            Form {
                Section(localizer.settingsSectionGeneral) {
                    SettingsRow(title: localizer.settingsLaunchAtLoginLabel) {
                        Toggle("", isOn: $settings.launchAtLoginEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                Section(localizer.settingsSectionLanguage) {
                    SettingsRow(title: localizer.settingsLanguageLabel) {
                        TrailingSelectionMenu(
                            title: settings.language.displayName,
                            width: 100
                        ) {
                            ForEach(AppLanguage.allCases) { language in
                                Button {
                                    settings.language = language
                                } label: {
                                    if language == settings.language {
                                        Label(language.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(language.displayName)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(12)
        }
    }

    private var clipboardSettingsContent: some View {
        ScrollView {
            Form {
                Section("插件") {
                    pluginToggleRow(plugin: clipboardPlugin)
                }

                Section(localizer.settingsSectionShortcut) {
                    SettingsRow(title: localizer.settingsOpenHistoryLabel) {
                        ShortcutRecorder(shortcut: $settings.shortcut, localizer: localizer)
                    }

                    Text(localizer.settingsShortcutHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section(localizer.settingsSectionCleanup) {
                    SettingsRow(title: localizer.settingsRetainHistoryLabel) {
                        PresetStepperControl(
                            value: $settings.retentionDays,
                            options: Preset.retentionDays,
                            displayText: localizer.dayText,
                            step: 1,
                            range: 1...365
                        )
                    }

                    SettingsRow(title: localizer.settingsVisibleHistoryLimitLabel) {
                        PresetStepperControl(
                            value: $settings.historyVisibleItemLimit,
                            options: Preset.historyVisibleLimits,
                            displayText: localizer.historyLimitText,
                            step: 10,
                            range: 0...1000,
                            decrementFromUnlimited: 300
                        )
                    }

                    SettingsRow(title: localizer.settingsStorageLimitLabel) {
                        ValueStepperControl(
                            text: localizer.storageText(settings.maxStorageMB),
                            onIncrement: {
                                settings.maxStorageMB = min(settings.maxStorageMB + 50, 1024)
                            },
                            onDecrement: {
                                settings.maxStorageMB = max(settings.maxStorageMB - 50, 50)
                            }
                        )
                    }

                    Text(localizer.settingsCleanupHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section(localizer.settingsSectionDisplay) {
                    SettingsRow(title: localizer.settingsHistoryTextFontSizeLabel) {
                        ValueStepperControl(
                            text: localizer.pixelText(settings.historyTextFontSize),
                            onIncrement: {
                                settings.historyTextFontSize = min(settings.historyTextFontSize + 1, 24)
                            },
                            onDecrement: {
                                settings.historyTextFontSize = max(settings.historyTextFontSize - 1, 12)
                            }
                        )
                    }

                    SettingsRow(title: localizer.settingsHistoryImageHeightLabel) {
                        ValueStepperControl(
                            text: localizer.pixelText(settings.historyImagePreviewHeight),
                            onIncrement: {
                                settings.historyImagePreviewHeight = min(settings.historyImagePreviewHeight + 10, 220)
                            },
                            onDecrement: {
                                settings.historyImagePreviewHeight = max(settings.historyImagePreviewHeight - 10, 100)
                            }
                        )
                    }
                }

                Section(localizer.settingsSectionHistory) {
                    Button(role: .destructive) {
                        isConfirmingClearHistory = true
                    } label: {
                        Text(localizer.settingsClearHistoryButton)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(12)
        }
    }

    private var codexQuotaSettingsContent: some View {
        ScrollView {
            Form {
                Section("插件") {
                    pluginToggleRow(plugin: codexQuotaPlugin)
                }

                if let plugin = codexQuotaTypedPlugin {
                    Section("状态栏展示") {
                        Toggle("显示 5 小时额度", isOn: binding(get: { plugin.settings.showFiveHour }, set: { plugin.settings.showFiveHour = $0 }))
                        Toggle("显示 7 天额度", isOn: binding(get: { plugin.settings.showWeekly }, set: { plugin.settings.showWeekly = $0 }))
                        Toggle("显示综合状态", isOn: binding(get: { plugin.settings.showSummary }, set: { plugin.settings.showSummary = $0 }))
                        Toggle("显示重置时间", isOn: binding(get: { plugin.settings.showResetTime }, set: { plugin.settings.showResetTime = $0 }))
                    }

                    Section("刷新") {
                        HStack {
                            Text("刷新间隔")
                            Spacer()
                            Text("\(Int(plugin.settings.refreshIntervalMinutes)) 分钟")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: binding(
                                get: { plugin.settings.refreshIntervalMinutes },
                                set: { plugin.settings.refreshIntervalMinutes = $0 }
                            ),
                            in: 1...30,
                            step: 1
                        )

                        Button("立即刷新") {
                            plugin.store.refresh(reason: "settings")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(12)
        }
    }

    private var systemMonitorSettingsContent: some View {
        ScrollView {
            Form {
                Section("插件") {
                    pluginToggleRow(plugin: systemMonitorPlugin)
                }

                if let plugin = systemMonitorTypedPlugin {
                    Section("状态栏展示") {
                        Toggle("显示上传网速", isOn: binding(get: { plugin.settings.showStatusBarUpload }, set: { plugin.settings.showStatusBarUpload = $0 }))
                        Toggle("显示下载网速", isOn: binding(get: { plugin.settings.showStatusBarDownload }, set: { plugin.settings.showStatusBarDownload = $0 }))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(12)
        }
    }

    private func pluginPlaceholderContent(plugin: BasePlugin?, summary: String) -> some View {
        ScrollView {
            Form {
                Section("插件") {
                    pluginToggleRow(plugin: plugin)
                }

                Section("说明") {
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(12)
        }
    }

    @ViewBuilder
    private func pluginToggleRow(plugin: BasePlugin?) -> some View {
        if let plugin {
            SettingsRow(title: "启用插件") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { newValue in
                            if newValue {
                                pluginManager.enablePlugin(id: plugin.id)
                            } else {
                                pluginManager.disablePlugin(id: plugin.id)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            SettingsRow(title: "当前状态") {
                StatusBadgeView(status: plugin.status)
            }
        }
    }

    private func binding<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: get,
            set: set
        )
    }
}

private struct SettingsRow<Control: View>: View {
    private let controlAreaWidth: CGFloat = 220

    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 16)
            control
                .frame(width: controlAreaWidth, alignment: .trailing)
        }
    }
}

private struct ValueStepperControl: View {
    let text: String
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .monospacedDigit()
                .frame(minWidth: 96, alignment: .trailing)

            Stepper("", onIncrement: onIncrement, onDecrement: onDecrement)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct PresetStepperControl: View {
    @Binding var value: Int
    let options: [Int]
    let displayText: (Int) -> String
    let step: Int
    let range: ClosedRange<Int>
    var decrementFromUnlimited: Int? = nil

    private var visibleOptions: [Int] {
        if options.contains(value) {
            return options
        }

        return (options + [value]).sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (0, 0):
                return false
            case (0, _):
                return false
            case (_, 0):
                return true
            default:
                return lhs < rhs
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            TrailingSelectionMenu(
                title: displayText(value),
                width: 132
            ) {
                ForEach(visibleOptions, id: \.self) { option in
                    Button {
                        value = option
                    } label: {
                        if option == value {
                            Label(displayText(option), systemImage: "checkmark")
                        } else {
                            Text(displayText(option))
                        }
                    }
                }
            }

            Stepper("", onIncrement: increment, onDecrement: decrement)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func increment() {
        guard value != 0 else { return }
        value = min(value + step, range.upperBound)
    }

    private func decrement() {
        if value == 0, let decrementFromUnlimited {
            value = decrementFromUnlimited
            return
        }

        value = max(value - step, range.lowerBound)
    }
}

private struct TrailingSelectionMenu<MenuContent: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder let content: MenuContent

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
            }
            .frame(width: width, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcut
    let localizer: Localizer

    // 录制快捷键时，临时监听本窗口内的 keyDown 事件。
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(isRecording ? localizer.shortcutRecording : shortcut.displayString) {
            toggleRecording()
        }
        .buttonStyle(.borderedProminent)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        stopRecording()
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !modifiers.isEmpty else { return nil }

            shortcut = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
