import AppKit
import CryptoKit

/// How this copy of Pe sârmă got onto the Mac, which decides how it is updated.
enum InstallKind: Equatable {
    /// Installed by Homebrew: Homebrew keeps the record, so it updates it.
    case homebrew
    /// Copied from the DMG (or anywhere else): the app can replace itself.
    case direct
}

/// What the public feed says about a newer version.
struct UpdateOffer: Equatable {
    let version: String
    let changes: String
    let url: URL
    let sha256: String
    let size: Int64
}

enum UpdateResult: Equatable {
    case upToDate(current: String, published: String)
    case newer(UpdateOffer)
    /// No answer: no connection, a server error or a timeout.
    case unreachable(String)
    /// An answer that is not a valid feed.
    case invalidFeed(String)
}

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The update check and the in-place update. The check is the only thing in
/// the app that uses the network, and only runs when the user asks for it.
enum Updates {
    static let teamID = "8AR6XP8MG7"
    static let caskToken = "pe-sarma"
    static let brewCommand = "brew upgrade --cask gordasgdc/tap/pe-sarma"
    static let downloadPrefix = "https://github.com/gordasgdc/pe-sarma/releases/download/"

    // MARK: Test hooks (compiled only into test builds, never shipped)

    static var feedURL: URL {
        #if UPDATE_TEST
        if let s = ProcessInfo.processInfo.environment["PESARMA_FEED_URL"], let u = URL(string: s) { return u }
        #endif
        return URL(string: "https://gordas.dev/pe-sarma/update.json")!
    }

    private static var token: String {
        #if UPDATE_TEST
        if let t = ProcessInfo.processInfo.environment["PESARMA_CASK_TOKEN"] { return t }
        #endif
        return caskToken
    }

    private static var caskrooms: [URL] {
        #if UPDATE_TEST
        if let d = ProcessInfo.processInfo.environment["PESARMA_CASKROOM"] { return [URL(fileURLWithPath: d)] }
        #endif
        return ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].map { URL(fileURLWithPath: $0) }
    }

    private static func downloadAllowed(_ url: URL) -> Bool {
        #if UPDATE_TEST
        if url.isFileURL { return true }
        #endif
        return url.absoluteString.hasPrefix(downloadPrefix) && url.scheme == "https"
    }

    // MARK: Versions and feed

    /// 1.10.0 is newer than 1.9.9: compared number by number.
    static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    private static func validVersion(_ s: String) -> Bool {
        s.range(of: #"^\d+(\.\d+){1,3}$"#, options: .regularExpression) != nil
    }

    /// Reads the feed. The version is always required; the download fields
    /// only when there is something newer to offer.
    static func interpret(_ data: Data, current: String, language: String) -> UpdateResult {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = json["version"] as? String, validVersion(version) else {
            return .invalidFeed("version")
        }
        if compare(version, current) <= 0 { return .upToDate(current: current, published: version) }
        guard let urlString = json["download_url"] as? String, let url = URL(string: urlString), downloadAllowed(url) else {
            return .invalidFeed("download_url")
        }
        guard let sha = json["sha256"] as? String, sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            return .invalidFeed("sha256")
        }
        guard let size = (json["size"] as? NSNumber)?.int64Value, size > 0 else { return .invalidFeed("size") }
        let all = json["changes"] as? [String: String] ?? [:]
        let changes = all[language] ?? all["en"] ?? all["ro"] ?? ""
        return .newer(UpdateOffer(version: version, changes: changes, url: url, sha256: sha.lowercased(), size: size))
    }

    static func check(current: String, language: String) async -> UpdateResult {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("PeSarma/\(current)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .unreachable("HTTP \(http.statusCode)")
            }
            return interpret(data, current: current, language: language)
        } catch {
            return .unreachable((error as? URLError).map { "\($0.code.rawValue)" } ?? error.localizedDescription)
        }
    }

    // MARK: Kind of installation

    /// Homebrew leaves `Caskroom/<token>/<version>/PeSarma.app`, a link to the
    /// copy it put in Applications. A copy is Homebrew's only when that link
    /// leads to this very app; a copy dragged from the DMG has none.
    static func installKind(bundle: URL = Bundle.main.bundleURL) -> InstallKind {
        let fm = FileManager.default
        let mine = bundle.resolvingSymlinksInPath().standardizedFileURL.path
        for room in caskrooms {
            let dir = room.appendingPathComponent(token)
            for version in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !version.hasPrefix(".") {
                let link = dir.appendingPathComponent(version).appendingPathComponent(bundle.lastPathComponent)
                if link.resolvingSymlinksInPath().standardizedFileURL.path == mine { return .homebrew }
            }
        }
        return .direct
    }

    /// Where an update goes: this very copy, or Applications when this one
    /// runs from the (read-only) disk image or from a translocated path.
    /// An app kept on another disk updates where it is.
    static func installTarget(bundle: URL = Bundle.main.bundleURL, volumeReadOnly: Bool? = nil) -> URL {
        let readOnly = volumeReadOnly
            ?? ((try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false)
        if bundle.path.contains("/AppTranslocation/") || readOnly {
            return URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle.lastPathComponent)
        }
        return bundle
    }

    /// The app only replaces itself where it can write without asking for a
    /// password; elsewhere it offers the download instead.
    static func canReplaceInPlace(_ target: URL = installTarget()) -> Bool {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent().path
        return fm.isWritableFile(atPath: parent) && (!fm.fileExists(atPath: target.path) || fm.isWritableFile(atPath: target.path))
    }

    // MARK: In-place update

    /// Downloads the DMG, checks it against the feed, checks the app inside
    /// (identity, version, Developer ID signature of this team), replaces the
    /// installed copy and returns where it now is. Nothing is replaced unless
    /// every check passed; the old copy stays until the new one is in place.
    static func install(_ offer: UpdateOffer, progress: @escaping @MainActor (String) -> Void) async throws -> URL {
        await progress(L("Downloading…"))
        let dmg = try await download(offer)
        await progress(L("Checking the signature…"))
        let staged = try await Task.detached { try stage(dmg: dmg, offer: offer) }.value
        await progress(L("Installing…"))
        let target = installTarget()
        try await Task.detached { try replace(target, with: staged) }.value
        try? FileManager.default.removeItem(at: dmg)
        return target
    }

    private static func download(_ offer: UpdateOffer) async throws -> URL {
        let (tmp, response) = try await URLSession(configuration: .ephemeral).download(from: offer.url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError(message: L("The server answered with status %@.").replacingOccurrences(of: "%@", with: "\(http.statusCode)"))
        }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.gordas.PeSarma/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("PeSarma-\(offer.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        let attributes = try FileManager.default.attributesOfItem(atPath: dest.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == offer.size, try sha256(of: dest) == offer.sha256 else {
            try? FileManager.default.removeItem(at: dest)
            throw UpdateError(message: L("The downloaded file does not match the published one."))
        }
        return dest
    }

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw UpdateError(message: "\((tool as NSString).lastPathComponent): \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }

    /// Mounts the image read-only, checks the app inside and copies it next to
    /// the installed one, so the swap stays on one volume.
    nonisolated private static func stage(dmg: URL, offer: UpdateOffer) throws -> URL {
        let id = Bundle.main.bundleIdentifier ?? "dev.gordas.PeSarma"
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("PeSarma-update-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }
        let apps = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: {
            $0.pathExtension == "app"
                && (NSDictionary(contentsOf: $0.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String) == id
        }), let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let found = info["CFBundleShortVersionString"] as? String else {
            throw UpdateError(message: L("The downloaded image does not contain Pe sârmă."))
        }
        guard found == offer.version else {
            throw UpdateError(message: L("The downloaded image has a different version than the announced one."))
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let details = try run("/usr/bin/codesign", ["-dvv", app.path])
        guard details.contains("TeamIdentifier=\(teamID)"), details.contains("Authority=Developer ID Application") else {
            throw UpdateError(message: L("The signature of the new version is not the developer's."))
        }
        let staged = installTarget().deletingLastPathComponent().appendingPathComponent(".PeSarma-\(offer.version).new.app")
        try? fm.removeItem(at: staged)
        try run("/usr/bin/ditto", [app.path, staged.path])
        return staged
    }

    /// Swaps the new copy in; if that fails the old one is put back.
    nonisolated private static func replace(_ target: URL, with staged: URL) throws {
        let fm = FileManager.default
        let old = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).old")
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: target.path) { try fm.moveItem(at: target, to: old) }
        do {
            try fm.moveItem(at: staged, to: target)
        } catch {
            if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: target) }
            try? fm.removeItem(at: staged)
            throw error
        }
        try? fm.removeItem(at: old)
    }

    /// Opens the new copy once this process is gone; an `open` while this one
    /// still runs would just bring the old instance forward.
    static func relaunchAfterExit(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? task.run()
    }
}
