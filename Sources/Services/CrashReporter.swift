import Foundation

/// Local crash reporting for Conductor.
/// Captures uncaught Objective-C exceptions, writes structured logs to disk.
/// Logs directory: ~/Library/Application Support/Conductor/crash_logs/
///
/// TO ADD REMOTE CRASH REPORTING (Sentry):
///   1. Create a project at sentry.io
///   2. Add to project.yml packages:
///        Sentry:
///          url: https://github.com/getsentry/sentry-cocoa
///          from: "8.0.0"
///   3. Add `- package: Sentry` under target dependencies
///   4. Run `xcodegen generate`
///   5. Replace sentryDSN below with your project DSN
///   6. Uncomment the SentrySDK block in initialize()
final class CrashReporter {

    // MARK: - Configuration
    // private static let sentryDSN = "https://YOUR_KEY@sentry.io/YOUR_PROJECT_ID"

    // MARK: - Log Directory

    static var logDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support.appendingPathComponent("Conductor/crash_logs", isDirectory: true)
    }

    // MARK: - Initialization

    static func initialize() {
        createLogDirectoryIfNeeded()
        installExceptionHandler()
        checkForPreviousCrashes()

        // Uncomment after configuring Sentry DSN above:
        // SentrySDK.start { options in
        //     options.dsn = sentryDSN
        //     options.debug = false
        //     options.tracesSampleRate = 0.2
        //     options.attachViewHierarchy = false
        // }
    }

    // MARK: - Exception Handler

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let log = CrashLog(
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                exception: exception.name.rawValue,
                reason: exception.reason ?? "No reason provided",
                callStack: exception.callStackSymbols.joined(separator: "\n")
            )
            CrashReporter.write(log)
        }
    }

    // MARK: - Log Writing

    private static func write(_ log: CrashLog) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "crash-\(timestamp).json"
        let url = logDirectory.appendingPathComponent(filename)

        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Startup Check

    private static func checkForPreviousCrashes() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ), !files.isEmpty else { return }

        // Post notification — UI can surface a "Previous crash detected" banner if desired
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(
                name: .conductorCrashDetected,
                object: nil,
                userInfo: ["crashCount": files.count]
            )
        }
    }

    private static func createLogDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
    }
}

// MARK: - Log Model

private struct CrashLog: Codable {
    let version: String
    let build: String
    let exception: String
    let reason: String
    let callStack: String
    let timestamp: String
    let platform: String

    init(version: String, build: String, exception: String, reason: String, callStack: String) {
        self.version = version
        self.build = build
        self.exception = exception
        self.reason = reason
        self.callStack = callStack
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.platform = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}

// MARK: - Notification

extension Notification.Name {
    static let conductorCrashDetected = Notification.Name("conductorCrashDetected")
}
