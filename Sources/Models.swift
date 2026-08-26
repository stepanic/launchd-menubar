import Foundation

/// Prefixes of labels we treat as "the user's own" jobs (see CLAUDE.md).
let minePrefixes: [String] = [
    "ai.domovina", "tv.domovina", "com.domovina", "com.italk", "com.pediludium",
    "com.revenuecat", "com.stepanic", "com.airkuna", "homebrew.",
]

/// End of the "background window" — the hours the Mac is on but the user is asleep.
/// Jobs firing before this land in the Night section; everything later is Daytime.
/// See SCHEDULING.md: the whole point of the 2026-08-26 reshuffle is keeping the
/// AI-consuming jobs on the night side of this line.
let nightWindowEndMinutes = 8 * 60 + 30   // 08:30

struct LaunchdJob: Identifiable, Hashable {
    var label: String
    var pid: Int?
    var lastExitStatus: Int?
    var plistPath: String?
    var schedule: String
    var spec: ScheduleSpec
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
        spec: ScheduleSpec = ScheduleSpec(),
        stdoutPath: String? = nil,
        stderrPath: String? = nil,
        program: String? = nil
    ) {
        self.label = label
        self.pid = pid
        self.lastExitStatus = lastExitStatus
        self.plistPath = plistPath
        self.schedule = schedule
        self.spec = spec
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.program = program
    }

    var isMine: Bool {
        minePrefixes.contains { label.hasPrefix($0) }
    }

    var isRunning: Bool { pid != nil }

    /// Last run ended non-zero. Drives the red dot and the per-section warning badge.
    var hasFailed: Bool {
        if let code = lastExitStatus { return code != 0 }
        return false
    }

    var category: JobCategory { spec.category }

    /// Second-level grouping key: which product/area the job belongs to
    /// (`tv.domovina.fetch.nightly` → `domovina`, `com.italk.yc-jobwatch` → `italk`).
    var owner: String {
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return label }
        // Reverse-DNS labels: the second component is the product, except for
        // `ai.domovina`/`tv.domovina`/`com.domovina` which are all one product.
        return String(parts[1])
    }

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

// MARK: - Schedule model

/// One `StartCalendarInterval` entry.
struct CalendarEntry: Hashable {
    var hour: Int?
    var minute: Int?
    var weekday: Int?
    var day: Int?

    /// Minutes past midnight, when the entry pins an hour. A `Minute`-only entry
    /// means "every hour at :MM", which has no single fire time.
    var minutesFromMidnight: Int? {
        guard let hour else { return nil }
        return hour * 60 + (minute ?? 0)
    }

    var isHourly: Bool { hour == nil && minute != nil }
}

/// Structured view of everything in a plist that decides *when* a job runs.
/// The UI groups and sorts on this; `describeSchedule` renders it for humans.
struct ScheduleSpec: Hashable {
    var calendar: [CalendarEntry] = []
    var intervalSeconds: Int?
    var runAtLoad = false
    var keepAlive = false
    var watchesPaths = false

    /// Earliest wall-clock fire time across all calendar entries, in minutes past midnight.
    var earliestFireMinutes: Int? {
        calendar.compactMap(\.minutesFromMidnight).min()
    }

    var isHourly: Bool {
        !calendar.isEmpty && calendar.allSatisfy(\.isHourly)
    }

    var category: JobCategory {
        // Order matters: a job can be several of these at once (e.g. pediludium
        // matchsync is RunAtLoad *and* every 15m — the interval is what defines it).
        if intervalSeconds != nil || isHourly { return .periodic }
        if let fire = earliestFireMinutes {
            return fire < nightWindowEndMinutes ? .night : .daytime
        }
        if keepAlive || runAtLoad { return .service }
        if watchesPaths { return .periodic }
        return .manual
    }

    /// Sort key within a section: fire time for scheduled jobs, interval for pollers.
    var sortValue: Int {
        if let fire = earliestFireMinutes { return fire }
        if let interval = intervalSeconds { return interval }
        if isHourly { return calendar.first?.minute ?? 0 }
        return Int.max
    }
}

enum JobCategory: String, CaseIterable, Identifiable {
    case night
    case daytime
    case periodic
    case service
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "Night (00:00–08:30)"
        case .daytime: return "Daytime"
        case .periodic: return "Pollers"
        case .service: return "Services"
        case .manual: return "No schedule"
        }
    }

    var systemImage: String {
        switch self {
        case .night: return "moon.stars"
        case .daytime: return "sun.max"
        case .periodic: return "repeat"
        case .service: return "bolt.horizontal.circle"
        case .manual: return "hand.raised"
        }
    }

    /// Sections the user rarely acts on start collapsed, so the 23-job list opens
    /// on the part that actually changes day to day.
    var startsCollapsed: Bool {
        switch self {
        case .night, .daytime: return false
        case .periodic, .service, .manual: return true
        }
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

/// Pull the structured schedule out of a parsed plist dictionary.
func parseSchedule(_ plist: [String: Any]) -> ScheduleSpec {
    var spec = ScheduleSpec()

    spec.intervalSeconds = plist["StartInterval"] as? Int

    func entry(_ dict: [String: Any]) -> CalendarEntry {
        CalendarEntry(
            hour: dict["Hour"] as? Int,
            minute: dict["Minute"] as? Int,
            weekday: dict["Weekday"] as? Int,
            day: dict["Day"] as? Int
        )
    }

    if let cal = plist["StartCalendarInterval"] as? [String: Any] {
        spec.calendar = [entry(cal)]
    } else if let cals = plist["StartCalendarInterval"] as? [[String: Any]] {
        spec.calendar = cals.map(entry)
    }

    spec.runAtLoad = plist["RunAtLoad"] as? Bool == true
    spec.keepAlive = (plist["KeepAlive"] as? Bool == true) || (plist["KeepAlive"] is [String: Any])
    spec.watchesPaths = !((plist["WatchPaths"] as? [String]) ?? []).isEmpty

    return spec
}

/// Describe a single calendar entry → e.g. `at 08:30`, `Mon 09:00`, `day 1 at 03:00`.
private func describeCalendar(_ e: CalendarEntry) -> String {
    var time: String?
    if e.hour != nil || e.minute != nil {
        time = String(format: "%02d:%02d", e.hour ?? 0, e.minute ?? 0)
    }
    var parts: [String] = []
    if let wd = e.weekday { parts.append(weekdayName(wd)) }
    if let day = e.day { parts.append("day \(day)") }
    if e.isHourly, let minute = e.minute {
        return String(format: "hourly at :%02d", minute)
    }
    if let time {
        parts.append(parts.isEmpty ? "at \(time)" : time)
    } else if parts.isEmpty {
        return "at calendar"
    }
    return parts.joined(separator: " ")
}

/// Build a short human schedule string from a parsed schedule spec.
func describeSchedule(_ spec: ScheduleSpec) -> String {
    var parts: [String] = []

    if let interval = spec.intervalSeconds {
        parts.append("every \(formatInterval(interval))")
    }

    if !spec.calendar.isEmpty {
        // Weekday variants of the same time collapse: `Mon 00:50, Thu 00:50` → `Mon, Thu 00:50`.
        let times = Set(spec.calendar.map { $0.minutesFromMidnight })
        if times.count == 1, spec.calendar.count > 1,
           spec.calendar.allSatisfy({ $0.weekday != nil }) {
            let days = spec.calendar.compactMap(\.weekday).map(weekdayName).joined(separator: ", ")
            let first = spec.calendar[0]
            parts.append(String(format: "%@ %02d:%02d", days, first.hour ?? 0, first.minute ?? 0))
        } else {
            parts.append(spec.calendar.map(describeCalendar).joined(separator: ", "))
        }
    }

    if spec.runAtLoad { parts.append("at load") }
    if spec.watchesPaths { parts.append("on change") }
    if spec.keepAlive { parts.append("keepalive") }

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
                job.spec = parseSchedule(parsed)
                job.schedule = describeSchedule(job.spec)
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
