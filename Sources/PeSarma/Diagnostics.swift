import AppKit

/// Local diagnostic log, following the OBSERVABILITY standard: structured,
/// rotating, and free of content. Only event names, counters, categories and
/// error codes are written; never the text, images or links on the line, file
/// names, paths or clipboard data. A failing logger never affects the app.
enum Diag {
    enum Level: String { case trace, debug, info, warning, error, critical }

    /// One id per launch, shown in the menu so a report can be matched to the log.
    static let sessionID = String(UUID().uuidString.prefix(8)).lowercased()
    /// Detailed logging: on only until the app quits.
    nonisolated(unsafe) static var detailed = false

    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    nonisolated(unsafe) static var fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/PeSarma/PeSarma.log")
    static var folder: URL { fileURL.deletingLastPathComponent() }
    nonisolated(unsafe) static var maxBytes = 1_000_000
    nonisolated(unsafe) static var generations = 3

    private static let queue = DispatchQueue(label: "dev.gordas.PeSarma.diagnostics", qos: .utility)
    private static let platform: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS\(v.majorVersion).\(v.minorVersion)"
    }()

    /// Writes one line. `fields` hold only safe values: they are redacted again
    /// here, so a path or an address that slips in is replaced.
    static func log(_ level: Level, _ event: String, _ fields: [String: String] = [:],
                    subsystem: String = "app", correlation: String? = nil) {
        if (level == .trace || level == .debug) && !detailed { return }
        var line = "\(timestamp()) \(level.rawValue) [\(subsystem)] event=\(event) session=\(sessionID) version=\(version) platform=\(platform)"
        if let correlation { line += " job=\(correlation)" }
        for key in fields.keys.sorted() { line += " \(key)=\(redact(fields[key] ?? ""))" }
        write(line + "\n")
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        f.timeZone = .current
        return f.string(from: date)
    }

    /// Replaces what must never reach a log: paths, addresses, long tokens,
    /// control characters. Output is capped.
    static func redact(_ value: String) -> String {
        var text = value.unicodeScalars.map { $0.value < 32 ? " " : String($0) }.joined()
        let rules: [(String, String)] = [
            (#"(?:/Users|/Volumes|/private|/var|/tmp|~)/[^\s,;"']*"#, "<path>"),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<email>"),
            (#"https?://[^\s]+"#, "<url>"),
            (#"\b[A-Za-z0-9_\-]{32,}\b"#, "<token>"),
        ]
        for (pattern, replacement) in rules {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        if text.contains(" ") { text = "\"" + text.replacingOccurrences(of: "\"", with: "'") + "\"" }
        return String(text.prefix(120))
    }

    private static func write(_ line: String) {
        queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                rotateIfNeeded(adding: line.utf8.count)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                // The logger must not change what the app does: fall back to the system log.
                NSLog("PeSarma diagnostics unavailable (code %ld)", (error as NSError).code)
            }
        }
    }

    private static func rotateIfNeeded(adding bytes: Int) {
        let fm = FileManager.default
        let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        guard size + bytes > maxBytes else { return }
        let base = fileURL.path
        try? fm.removeItem(atPath: "\(base).\(generations)")
        for i in stride(from: generations - 1, through: 1, by: -1) {
            if fm.fileExists(atPath: "\(base).\(i)") { try? fm.moveItem(atPath: "\(base).\(i)", toPath: "\(base).\(i + 1)") }
        }
        try? fm.moveItem(atPath: base, toPath: "\(base).1")
    }

    /// Waits for pending writes. Used before an export and in tests.
    static func flush() { queue.sync {} }

    /// Builds an inspectable ZIP: the logs, a manifest and a few non-sensitive
    /// settings. Nothing from the line, no media, no credentials. The user
    /// decides whether to send it; nothing is uploaded.
    static func export(to destination: URL) throws {
        flush()
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("pesarma-diag-\(sessionID)", isDirectory: true)
        try? fm.removeItem(at: stage)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        var settings = ""
        for key in ["inboxEnabled", "copyScreenshots", "showOverFullScreen", "menuBarRevealOff", "quietHang"] {
            settings += "\(key)=\(UserDefaults.standard.bool(forKey: key))\n"
        }
        let manifest = """
        Pe sârmă — pachet de diagnostic
        Versiune: \(version)
        Platformă: \(platform)
        Sesiune: \(sessionID)
        Creat: \(timestamp())
        Conține: jurnalele locale și setările tehnice de mai jos. Nu conține capturi, text copiat, linkuri, nume de fișiere sau căi.

        \(settings)
        """
        try manifest.write(to: stage.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
        let base = fileURL.lastPathComponent
        for name in [base] + (1...generations).map({ "\(base).\($0)" }) {
            let source = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: stage.appendingPathComponent(name)) }
        }
        try? fm.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", stage.path, destination.path]
        try ditto.run(); ditto.waitUntilExit()
        if ditto.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}
