// Logic checks for Updates.swift: versions, reading the feed, kind of
// installation. Built with -DUPDATE_TEST (see scripts/test-updates.sh).
import Foundation

@main struct UpdateChecks {
    static var failures = 0
    static func expect(_ name: String, _ ok: Bool) {
        print((ok ? "PASS" : "FAIL") + ": " + name)
        if !ok { failures += 1 }
    }
    static func feed(_ version: String, url: String = "https://github.com/gordasgdc/pe-sarma/releases/download/v1.1.2/PeSarma-1.1.2.dmg",
                     sha: String = String(repeating: "a", count: 64), size: Any = 3048324) -> Data {
        let o: [String: Any] = ["version": version, "download_url": url, "sha256": sha, "size": size,
                                "changes": ["ro": "Schimbare", "en": "Change", "es": "Cambio"]]
        return try! JSONSerialization.data(withJSONObject: o)
    }
    static func main() {
        expect("1.10.0 is newer than 1.9.9", Updates.compare("1.9.9", "1.10.0") < 0)
        expect("1.1.2 equals 1.1.2.0", Updates.compare("1.1.2", "1.1.2.0") == 0)
        if case .newer(let o) = Updates.interpret(feed("1.1.2"), current: "1.1.1", language: "es") {
            expect("older installed: offer 1.1.2 with Spanish text", o.version == "1.1.2" && o.changes == "Cambio")
        } else { expect("older installed: offer", false) }
        if case .upToDate = Updates.interpret(feed("1.1.1"), current: "1.1.1", language: "ro") { expect("same version: up to date", true) } else { expect("same version: up to date", false) }
        if case .upToDate = Updates.interpret(feed("1.1.1"), current: "1.1.2", language: "ro") { expect("installed newer than feed: up to date", true) } else { expect("installed newer than feed", false) }
        func invalid(_ n: String, _ d: Data) {
            if case .invalidFeed = Updates.interpret(d, current: "1.1.1", language: "ro") { expect("invalid feed: " + n, true) } else { expect("invalid feed: " + n, false) }
        }
        invalid("not JSON", Data("<html>".utf8))
        invalid("empty", Data())
        invalid("no version", Data("{}".utf8))
        invalid("odd version", feed("v1.1.2"))
        invalid("download outside the repository releases", feed("1.1.2", url: "https://example.com/PeSarma.dmg"))
        invalid("download over http", feed("1.1.2", url: "http://github.com/gordasgdc/pe-sarma/releases/download/v1.1.2/x.dmg"))
        invalid("download from another repository", feed("1.1.2", url: "https://github.com/other/repo/releases/download/v1/x.dmg"))
        invalid("short hash", feed("1.1.2", sha: "abc"))
        invalid("size zero", feed("1.1.2", size: 0))

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pesarma-kind-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let apps = root.appendingPathComponent("Applications"), cask = root.appendingPathComponent("Caskroom/pe-sarma/1.1.1")
        try! fm.createDirectory(at: apps.appendingPathComponent("PeSarma.app"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: cask, withIntermediateDirectories: true)
        setenv("PESARMA_CASKROOM", root.appendingPathComponent("Caskroom").path, 1)
        setenv("PESARMA_CASK_TOKEN", "pe-sarma", 1)
        let mine = apps.appendingPathComponent("PeSarma.app")
        expect("no Caskroom link: direct", Updates.installKind(bundle: mine) == .direct)
        try! fm.createSymbolicLink(at: cask.appendingPathComponent("PeSarma.app"), withDestinationURL: mine)
        expect("Caskroom link to this app: homebrew", Updates.installKind(bundle: mine) == .homebrew)
        let other = root.appendingPathComponent("Elsewhere/PeSarma.app")
        try! fm.createDirectory(at: other, withIntermediateDirectories: true)
        expect("a copy elsewhere with the same name: direct", Updates.installKind(bundle: other) == .direct)
        setenv("PESARMA_CASKROOM", root.appendingPathComponent("Nope").path, 1)
        expect("no Caskroom at all: direct", Updates.installKind(bundle: mine) == .direct)
        let onImage = URL(fileURLWithPath: "/Volumes/Pe sârmă/PeSarma.app"), onDisk = URL(fileURLWithPath: "/Volumes/External/PeSarma.app")
        expect("run from a read-only disk image: target is Applications", Updates.installTarget(bundle: onImage, volumeReadOnly: true).path == "/Applications/PeSarma.app")
        expect("kept on another writable disk: updates in place", Updates.installTarget(bundle: onDisk, volumeReadOnly: false) == onDisk)
        expect("translocated copy: target is Applications", Updates.installTarget(bundle: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/PeSarma.app"), volumeReadOnly: false).path == "/Applications/PeSarma.app")
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
