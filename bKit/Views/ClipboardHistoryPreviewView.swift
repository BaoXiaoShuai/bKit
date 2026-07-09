//
//  ClipboardHistoryPreviewView.swift
//  bKit
//
//  Created by 鲍小帅 on 2026/7/8.
//

// AppKit 来源应用图标能力
import AppKit
// SwiftUI 剪切板历史视图
import SwiftUI

struct ClipboardHistoryPreviewView: View {
    @ObservedObject var store: ClipboardStore

    @State private var query = ""

    private var visibleItems: [ClipboardItem] {
        Array(store.filteredItems(query: query).prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("剪切板历史", systemImage: "list.bullet.clipboard")
                    .font(.headline)

                Spacer()

                if !store.items.isEmpty {
                    Button("清空") {
                        store.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }

            TextField("搜索历史", text: $query)
                .textFieldStyle(.roundedBorder)

            if visibleItems.isEmpty {
                ContentUnavailableView(
                    "暂无剪切板记录",
                    systemImage: "doc.on.clipboard",
                    description: Text("复制文本、图片或文件后会显示在这里")
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        ClipboardHistoryRowView(
                            item: item,
                            sourceIcon: store.sourceIcon(for: item),
                            restore: {
                                store.restoreToPasteboard(item)
                            },
                            delete: {
                                store.deleteItem(id: item.id)
                            }
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ClipboardHistoryRowView: View {
    let item: ClipboardItem
    let sourceIcon: NSImage

    // 恢复当前历史到系统剪切板。
    let restore: () -> Void
    // 删除当前历史。
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: sourceIcon)
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                restore()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("恢复到剪切板")

            Button {
                delete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(.vertical, 4)
    }

    private var metaText: String {
        let kindText: String
        switch item.kind {
        case .text:
            kindText = "文本"
        case .image:
            kindText = "图片"
        case .file:
            kindText = "文件"
        }

        let sourceText = item.sourceAppName ?? "未知来源"
        return "\(kindText) · \(sourceText)"
    }
}
