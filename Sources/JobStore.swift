import AppKit
import Foundation
import SwiftUI

@MainActor
final class JobStore: ObservableObject {
    @Published var jobs: [LaunchdJob] = []
    @Published var showOnlyMine: Bool = true
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
        return filtered.sorted { a, b in
            if a.isMine != b.isMine { return a.isMine }
            return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
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
    static func bestLogURL(for job: LaunchdJob) -> URL? {
        let fm = FileManager.default
        var candidates: Set<String> = []

        for path in [job.stdoutPath, job.stderrPath].compactMap({ $0 }) {
            if fm.fileExists(atPath: path) { candidates.insert(path) }
            let dir = (path as NSString).deletingLastPathComponent
            if let newest = newestLog(in: dir, fm: fm) { candidates.insert(newest) }
        }

        return candidates
            .map { URL(fileURLWithPath: $0) }
            .max { modDate($0, fm) < modDate($1, fm) }
    }

    /// Most recently modified `*.log` file directly inside `dir`, if any.
    private static func newestLog(in dir: String, fm: FileManager) -> String? {
        guard !dir.isEmpty,
              let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        return entries
            .filter { $0.hasSuffix(".log") }
            .map { "\(dir)/\($0)" }
            .max { modDate(URL(fileURLWithPath: $0), fm) < modDate(URL(fileURLWithPath: $1), fm) }
    }

    private static func modDate(_ url: URL, _ fm: FileManager) -> Date {
        (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
    }
}
