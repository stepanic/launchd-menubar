import Foundation

/// Prefixes of labels we treat as "the user's own" jobs (see CLAUDE.md).
let minePrefixes: [String] = [
    "ai.domovina", "tv.domovina", "com.domovina", "com.italk", "com.pediludium",
    "com.revenuecat", "com.stepanic", "homebrew.",
]

struct LaunchdJob: Identifiable, Hashable {
    var label: String
    var pid: Int?
    var lastExitStatus: Int?
    var plistPath: String?
    var schedule: String
    var stdoutPath: String?
    var stderrPath: String?
    var program: String?

    var id: String { label }

    init(
        label: String,
        pid: Int? = nil,
        lastExitStatus: Int? = nil,
        plistPath: String? = nil,
        schedule: String = "manual",
        stdoutPath: String? = nil,
        stderrPath: String? = nil,
        program: String? = nil
    ) {
        self.label = label
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.plistPath = plistPath
        self.schedule = schedule
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.program = program
    }

    var isMine: Bool {
        minePrefixes.contains { label.hasPrefix($0) }
    }

    var isRunning: Bool { pid != nil }

    var statusText: String {
        if let pid {
            return "running · pid \(pid)"
        }
        if let code = lastExitStatus {
            return "idle · last exit \(code)"
        }
        return "idle"
    }
}

// MARK: - Schedule parsing

/// Format a number of seconds into a compact `1h` / `30m` / `45s` style string.
func formatInterval(_ seconds: Int) -> String {
    if seconds <= 0 { return "\(seconds)s" }
    if seconds % 3600 == 0 { return "\(seconds / 3600)h" }
    if seconds % 60 == 0 { return "\(seconds / 60)m" }
    return "\(seconds)s"
}

private let weekdayNames = [
    1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun", 0: "Sun",
]

func weekdayName(_ n: Int) -> String { weekdayNames[n] ?? "wd\(n)" }

/// Describe a single StartCalendarInterval dict → e.g. `at 08:30`, `Mon 09:00`, `day 1 at 03:00`.
private func describeCalendar(_ dict: [String: Any]) -> String {
    let hour = (dict["Hour"] as? Int)
    let minute = (dict["Minute"] as? Int)
    var time: String?
    if hour != nil || minute != nil {
        time = String(format: "%02d:%02d", hour ?? 0, minute ?? 0)
    }
    var parts: [String] = []
    if let wd = dict["Weekday"] as? Int { parts.append(weekdayName(wd)) }
    if let day = dict["Day"] as? Int { parts.append("day \(day)") }
    if let time {
        parts.append(parts.isEmpty ? "at \(time)" : time)
    } else if parts.isEmpty {
        return "at calendar"
    }
    return parts.joined(separator: " ")
}

/// Build a short human schedule string from a parsed plist dictionary.
func describeSchedule(_ plist: [String: Any]) -> String {
    var parts: [String] = []

    if let interval = plist["StartInterval"] as? Int {
        parts.append("every \(formatInterval(interval))")
    }

    if let cal = plist["StartCalendarInterval"] as? [String: Any] {
        parts.append(describeCalendar(cal))
    } else if let cals = plist["StartCalendarInterval"] as? [[String: Any]] {
        parts.append(cals.map(describeCalendar).joined(separator: ", "))
    }

    if plist["RunAtLoad"] as? Bool == true {
        parts.append("at load")
    }

    if let watch = plist["WatchPaths"] as? [String], !watch.isEmpty {
        parts.append("on change")
    }

    let keepAlive = (plist["KeepAlive"] as? Bool == true) || (plist["KeepAlive"] is [String: Any])
    if keepAlive {
        parts.append("keepalive")
    }

    return parts.isEmpty ? "manual" : parts.joined(separator: " · ")
}

// MARK: - Loader

enum LaunchdLoader {
    private static let plistDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/LaunchAgents",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]
    }()

    /// Merge runtime (`launchctl list`) info with plist metadata, keyed by Label.
    static func loadAll() -> [LaunchdJob] {
        var jobs: [String: LaunchdJob] = [:]

        // 1) Runtime view from `launchctl list`.
        let (out, _) = Shell.run("/bin/launchctl", ["list"])
        for line in out.split(separator: "\n").dropFirst() {
            let cols = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).filter { !$0.isEmpty }
            guard cols.count >= 3 else { continue }
            let pidStr = String(cols[0])
            let statusStr = String(cols[1])
            let label = cols[2...].joined(separator: " ")
            guard !label.isEmpty else { continue }

            var job = LaunchdJob(label: label)
            job.pid = Int(pidStr)
            job.lastExitStatus = Int(statusStr)
            jobs[label] = job
        }

        // 2) Plist metadata, merged in.
        let fm = FileManager.default
        for dir in plistDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let path = "\(dir)/\(entry)"
                guard let data = fm.contents(atPath: path),
                      let parsed = try? PropertyListSerialization.propertyList(
                          from: data, options: [], format: nil) as? [String: Any],
                      let label = parsed["Label"] as? String
                else { continue }

                var job = jobs[label] ?? LaunchdJob(label: label)
                job.plistPath = path
                job.schedule = describeSchedule(parsed)
                job.stdoutPath = parsed["StandardOutPath"] as? String
                job.stderrPath = parsed["StandardErrorPath"] as? String
                if let prog = parsed["Program"] as? String {
                    job.program = prog
                } else if let argv = parsed["ProgramArguments"] as? [String], let first = argv.first {
                    job.program = first
                }
                jobs[label] = job
            }
        }

        return Array(jobs.values)
    }
}
