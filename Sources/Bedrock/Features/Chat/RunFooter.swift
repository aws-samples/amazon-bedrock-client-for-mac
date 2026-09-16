import AppKit
import SwiftUI

struct RunFooter: View {
    let threadID: String
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var settings = PreferencesStore.shared
    private var run: RunRecord? { store.state.runs.first { $0.threadID == threadID } }
    var body: some View {
        if settings.showUsageInfo, let run {
            Group {
                if run.status == .running {
                    TimelineView(.periodic(from: run.startedAt, by: 1)) { context in metrics(run, date: context.date) }
                } else {
                    metrics(run, date: run.finishedAt ?? run.startedAt)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }
    private func metrics(_ run: RunRecord, date: Date) -> some View {
        HStack(spacing: 10) {
            if run.status == .running { ProgressView().controlSize(.mini) }
            if run.status != .completed { Text(run.status.title) }
            Text("\(max(0, date.timeIntervalSince(run.startedAt)).formatted(.number.precision(.fractionLength(1))))s").monospacedDigit()
            if let input = run.inputTokens { Text("\(input.formatted()) in").monospacedDigit() }
            if let output = run.outputTokens { Text("\(output.formatted()) out").monospacedDigit() }
            if let cache = run.cacheReadTokens, cache > 0 { Text("\(cache.formatted()) cached").monospacedDigit() }
            if let rate = run.tokensPerSecond { Text("\(rate.formatted(.number.precision(.fractionLength(1)))) tok/s").monospacedDigit() }
            Spacer(minLength: 0)
        }
        .font(DesignTokens.detail).foregroundStyle(.secondary).lineLimit(1)
        .frame(maxWidth: DesignTokens.contentWidth)
    }
}
