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
        let candidate = job.stdoutPath ?? job.stderrPath
        guard let path = candidate, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
