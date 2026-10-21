import SwiftUI

struct HistoryView: View {
    @Environment(\.nestTheme) private var theme
    @EnvironmentObject private var store: RestStore
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("每次停下来，\n都在好好照顾自己。")
                        .font(.title.weight(.semibold)).padding(.top, 12)
                    NestCard {
                        HStack(spacing: 32) {
                            metric("\(store.completedCount)", "完成休息")
                            metric("\(store.totalMinutes)", "累计分钟")
                        }
                    }
                    if store.records.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "leaf").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(theme.accent)
                            Text("从片刻安静开始").font(.headline)
                            Text("结束一次休息后，足迹会出现在这里。\n所有记录只保存在这台 iPhone 上。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48).accessibilityIdentifier("history.empty")
                    } else {
                        ForEach(store.records) { record in
                            NestCard {
                                HStack(spacing: 16) {
                                    Image(systemName: record.completed ? "checkmark.circle" : "stop.circle")
                                        .font(.title2).foregroundStyle(theme.accent)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(record.completed ? "完成一段休息" : "提前结束").font(.headline)
                                        Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((record.seconds ?? record.minutes * 60) < 60 ? "\(record.seconds ?? 0) 秒" : "\(record.minutes) 分").font(.subheadline.monospacedDigit())
                                }
                            }.accessibilityIdentifier("history.record")
                        }
                        Button("清空本机记录", role: .destructive) { confirmClear = true }.frame(minHeight: 44)
                            .accessibilityIdentifier("history.clear")
                    }
                }.padding(24)
            }.background(theme.background).navigationTitle("休息足迹")
                .confirmationDialog("清空所有休息记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("清空记录", role: .destructive) { store.clearHistory() }
                } message: { Text("此操作只删除这台设备上的记录，无法恢复。") }
        }
    }

    /// 展示本机休息统计并保留完整可访问文本。
    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.light)).foregroundStyle(theme.accent)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
