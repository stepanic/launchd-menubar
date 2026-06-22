import Foundation

/// Tiny wrapper around Process for running launchctl and friends.
enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }
}
