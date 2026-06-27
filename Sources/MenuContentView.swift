import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            jobList
            Divider()
            footer
        }
        .frame(width: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
            Text("LaunchdBar")
                .font(.headline)
            Spacer()
            Toggle("Only mine", isOn: $store.showOnlyMine)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomLeading) {
            if let updated = store.lastUpdated {
                Text("updated \(timeString(updated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .offset(y: 2)
            }
        }
    }

    // MARK: - List

    private var jobList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.visibleJobs) { job in
                    JobRow(job: job, store: store)
                    Divider()
                }
            }
        }
        .frame(minHeight: 360, maxHeight: 480)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(store.visibleJobs.count) jobs")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

struct JobRow: View {
    let job: LaunchdJob
    @ObservedObject var store: JobStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.label)
                    .font(.system(size: 12, weight: job.isMine ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(job.schedule)
                    Text("·")
                    Text(job.statusText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if hovering {
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Run now") { store.runNow(job) }
            if job.plistPath != nil {
                Button("Reveal plist") { store.reveal(job) }
            }
            if job.stdoutPath != nil || job.stderrPath != nil {
                Button("Open log") { store.openLog(job) }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                store.runNow(job)
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Run now")

            Button {
                store.reveal(job)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .disabled(job.plistPath == nil)
            .help("Reveal plist")

            Button {
                store.openLog(job)
            } label: {
                Image(systemName: "text.alignleft")
            }
            .disabled(job.stdoutPath == nil && job.stderrPath == nil)
            .help("Open log")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
    }

    private var statusColor: Color {
        if job.isRunning { return .green }
        if let code = job.lastExitStatus, code != 0 { return .red }
        return .gray
    }
}
