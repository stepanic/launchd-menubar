import AppKit
import Foundation
import SwiftUI

/// One collapsible group in the menu (Night / Daytime / Pollers / Services / …).
struct JobSection: Identifiable {
    let category: JobCategory
    let jobs: [LaunchdJob]
    var id: String { category.rawValue }
}

@MainActor
final class JobStore: ObservableObject {
    @Published var jobs: [LaunchdJob] = []
    @Published var showOnlyMine: Bool = true
    @Published var searchText: String = ""
    @Published var lastUpdated: Date?
    @Published var isLoading: Bool = false

    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    var visibleJobs: [LaunchdJob] {
        let filtered = showOnlyMine ? jobs.filter(\.isMine) : jobs
        let matched = searchText.isEmpty ? filtered : filtered.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
        }
        return matched.sorted { a, b in
            if a.isMine != b.isMine { return a.isMine }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
        }
    }

    /// `visibleJobs` bucketed by category, in display order, empty sections dropped.
    ///
    /// Within a section jobs sort by when they actually fire (00:10 before 01:00,
    /// every 90s before every 30m) rather than alphabetically — with 23 jobs the
    /// timeline is what you scan for, and it makes a gap in the night window obvious.
    var sections: [JobSection] {
        let grouped = Dictionary(grouping: visibleJobs, by: \.category)
        return JobCategory.allCases.compactMap { category in
            guard let jobs = grouped[category], !jobs.isEmpty else { return nil }
            let sorted = jobs.sorted { a, b in
                if a.spec.sortValue != b.spec.sortValue { return a.spec.sortValue < b.spec.sortValue }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }
            return JobSection(category: category, jobs: sorted)
        }
    }

    func reload() {
        if isLoading { return }
        isLoading = true
        Task.detached {
            let loaded = LaunchdLoader.loadAll()
            await MainActor.run {
                self.jobs = loaded
                self.lastUpdated = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Actions

    func runNow(_ job: LaunchdJob) {
        let uid = getuid()
        Shell.run("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/\(job.label)"])
        reload()
    }

    func reveal(_ job: LaunchdJob) {
        guard let path = job.plistPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openLog(_ job: LaunchdJob) {
        guard let url = JobStore.bestLogURL(for: job) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Pick the most useful log to open.
    ///
    /// The plist's `StandardOutPath`/`StandardErrorPath` are often stale because the
    /// job's script redirects its own output to a dated file (e.g. `nightly_2026-06-27.log`)
    /// in the same directory. So we consider both the declared paths *and* the newest
    /// `*.log` sitting next to them, and open whichever was modified most recently.
    ///
    /// Multiple jobs can log into the same directory (e.g. nightly + priority both use
    /// `automatic/logs/`), so the dir scan only considers logs whose filename mentions
    /// the job's short name (last label component). Without that filter, a chatty
    /// sibling job's log always wins on mtime. Falls back to the unfiltered newest log
    /// when nothing matches, preserving the old behavior for unrelated naming schemes.
    static func bestLogURL(for job: LaunchdJob) -> URL? {
        let fm = FileManager.default
        let shortName = job.label.split(separator: ".").last.map(String.init)?.lowercased()
        var candidates: Set<String> = []

        for path in [job.stdoutPath, job.stderrPath].compactMap({ $0 }) {
            if fm.fileExists(atPath: path) { candidates.insert(path) }
            let dir = (path as NSString).deletingLastPathComponent
            if let newest = newestLog(in: dir, matching: shortName, fm: fm)
                ?? newestLog(in: dir, matching: nil, fm: fm) {
                candidates.insert(newest)
            }
        }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .max { modDate($0, fm) < modDate($1, fm) }
    }

    /// Most recently modified `*.log` file directly inside `dir`, if any.
    /// When `matching` is non-nil, only filenames containing that substring count.
    private static func newestLog(in dir: String, matching: String?, fm: FileManager) -> String? {
        guard !dir.isEmpty,
              let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        return entries
            .filter { $0.hasSuffix(".log") }
            .filter { name in
                guard let token = matching else { return true }
                return name.lowercased().contains(token)
            }
            .map { "\(dir)/\($0)" }
            .max { modDate(URL(fileURLWithPath: $0), fm) < modDate(URL(fileURLWithPath: $1), fm) }
    }

    private static func modDate(_ url: URL, _ fm: FileManager) -> Date {
        (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}
