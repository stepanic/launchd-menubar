import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: JobStore

    /// Which sections the user has folded away, persisted across launches.
    @AppStorage("collapsedSections") private var collapsedRaw: String = JobCategory.allCases
        .filter(\.startsCollapsed).map(\.rawValue).joined(separator: ",")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            jobList
            Divider()
            footer
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text("LaunchdBar")
                    .font(.headline)
                if let updated = store.lastUpdated {
                    Text(timeString(updated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Filter jobs", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - List

    /// The list grows with its content instead of sitting at a fixed 480pt, and only
    /// starts scrolling once it would run past the screen. `MenuBarExtra(.window)`
    /// sizes itself to the content, so an unbounded frame here would happily draw a
    /// menu taller than the display — hence the screen-derived ceiling rather than none.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, screen - 160)
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(store.sections) { section in
                    Section {
                        if !isCollapsed(section.category) {
                            ForEach(section.jobs) { job in
                                JobRow(job: job, store: store)
                                Divider()
                            }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }

                if store.sections.isEmpty {
                    Text(store.searchText.isEmpty ? "No jobs" : "No match for “\(store.searchText)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            }
        }
        .frame(maxHeight: maxListHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ section: JobSection) -> some View {
        let collapsed = isCollapsed(section.category)
        return Button {
            toggle(section.category)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                Image(systemName: section.category.systemImage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(section.category.title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(section.jobs.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                Spacer()
                if section.jobs.contains(where: \.hasFailed) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(.bar)
    }

    private func isCollapsed(_ category: JobCategory) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(category.rawValue))
    }

    private func toggle(_ category: JobCategory) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(category.rawValue) {
            set.remove(category.rawValue)
        } else {
            set.insert(category.rawValue)
        }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(store.visibleJobs.count) jobs")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.visibleJobs.contains(where: \.hasFailed) {
                Text("· \(store.visibleJobs.filter(\.hasFailed).count) failing")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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

            VStack(alignment: .leading, spacing: 1) {
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

            Spacer(minLength: 4)

            if hovering {
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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
        if job.hasFailed { return .red }
        return .gray
    }
}
