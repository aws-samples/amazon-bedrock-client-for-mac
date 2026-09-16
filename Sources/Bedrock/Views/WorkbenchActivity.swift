import SwiftUI

struct WorkbenchActivityView: View {
    @ObservedObject private var store = WorkbenchStore.shared
    @State private var status: LocalRunStatus?
    @State private var model = ""
    @State private var days = 7
    @State private var selection: UUID?
    private var runs: [LocalRunRecord] {
        let cutoff = days == 1 ? Calendar.current.startOfDay(for: Date()) : Date().addingTimeInterval(-Double(days) * 86_400)
        return store.state.runs.filter {
            (status == nil || $0.status == status) && (model.isEmpty || $0.modelID == model) &&
            (days == 0 || $0.startedAt >= cutoff)
        }
    }
    private var selected: LocalRunRecord? { runs.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                WorkbenchPageHeader(title: "See what happened", subtitle: "Real request usage and execution history, saved on this Mac. Token counts appear when the model reports them.")
                HStack(spacing: 30) {
                    metric("Runs", value: runs.count.formatted())
                    metric("Input tokens", value: total(\.inputTokens))
                    metric("Output tokens", value: total(\.outputTokens))
                    metric("Cache reads", value: total(\.cacheReadTokens))
                    Spacer()
                    Button("Export", systemImage: "square.and.arrow.up", action: WorkbenchActions.exportActivity)
                }
                HStack {
                    WorkbenchMenuField(title: "Status", selection: $status,
                        options: [(nil, "All statuses")] + LocalRunStatus.allCases.map { (Optional($0), $0.title) }).frame(maxWidth: 200)
                    WorkbenchMenuField(title: "Model", selection: $model,
                        options: [("", "All models")] + Set(store.state.runs.map(\.modelID)).sorted().map { ($0, WorkbenchModelCatalog.shared.model($0).name) }).frame(maxWidth: 330)
                    Spacer()
                    WorkbenchMenuField(title: "Period", selection: $days,
                                       options: [(1, "Today"), (7, "7 days"), (30, "30 days"), (0, "All time")]).frame(width: 110)
                }
            }
            .padding(28)
            Divider()
            if runs.isEmpty {
                WorkbenchEmptyState(symbol: "chart.bar.xaxis", title: "No runs in this view", detail: "Send a prompt or adjust the filters. Usage will appear as requests complete.")
            } else {
                Table(runs, selection: $selection) {
                    TableColumn("Request") { run in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(run.title.isEmpty ? "Attachment analysis" : run.title).lineLimit(1)
                            Text(run.modelID).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 5)
                    }.width(min: 180, ideal: 300)
                    TableColumn("Status") { run in
                        Label(run.status.title, systemImage: run.status == .completed ? "checkmark.circle" : run.status == .running ? "circle.dotted" : "minus.circle")
                            .font(.caption).foregroundStyle(run.status == .failed || run.status == .timedOut ? Color.orange : Color.secondary)
                    }.width(95)
                    TableColumn("Started") { Text($0.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption) }.width(140)
                    TableColumn("Output") { Text($0.outputTokens?.formatted() ?? "—").monospacedDigit().font(.caption) }.width(70)
                    TableColumn("Time") { Text($0.duration.map { "\($0.formatted(.number.precision(.fractionLength(1))))s" } ?? "—").monospacedDigit().font(.caption) }.width(65)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let run = runs.first(where: { $0.id == id }) { Button("Open thread") { store.selectThread(run.threadID) } }
                } primaryAction: { ids in if let id = ids.first, let run = runs.first(where: { $0.id == id }) { store.selectThread(run.threadID) } }
                if let selected { detail(selected) }
            }
        }
        .accessibilityIdentifier("workbench.activity")
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit()
        }
    }
    private func total(_ keyPath: KeyPath<LocalRunRecord, Int?>) -> String {
        let values = runs.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? "—" : values.reduce(0, +).formatted() + (values.count < runs.count ? "+" : "")
    }
    private func detail(_ run: LocalRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 18) {
                Text("\(run.toolCalls) tool calls")
                Text("First token: \(run.timeToFirstToken.map { "\($0.formatted(.number.precision(.fractionLength(2))))s" } ?? "—")")
                Text("Cache writes: \(run.cacheWriteTokens?.formatted() ?? "—")")
                Spacer()
                Button("Open thread") { store.selectThread(run.threadID) }
            }
            .font(.caption)
            if let error = run.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled).lineLimit(4) }
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
    }
}
