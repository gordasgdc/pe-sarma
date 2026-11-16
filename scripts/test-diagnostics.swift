// Checks the diagnostic log without the app: redaction, rotation and a
// logger that cannot write. Usage: scripts/test-diagnostics.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ message: String) {
    print(ok ? "PASS: \(message)" : "FAIL: \(message)")
    if !ok { failures += 1 }
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: dir)
Diag.fileURL = dir.appendingPathComponent("PeSarma.log")
Diag.maxBytes = 600
Diag.generations = 2

// Redaction
let r1 = Diag.redact("saved /Users/ana/Desktop/captura secreta.png to /Volumes/X/y")
check(!r1.contains("/Users") && !r1.contains("/Volumes") && r1.contains("<path>"), "paths are redacted")
check(Diag.redact("ana@example.com").contains("<email>"), "email addresses are redacted")
check(Diag.redact("https://example.com/a?token=1").contains("<url>"), "URLs are redacted")
check(Diag.redact("sk" + "_live_" + String(repeating: "a", count: 24)).contains("<token>"), "long tokens are redacted")
check(Diag.redact(String(repeating: "a", count: 500)).count <= 120, "values are capped")

// Rotation and retention
for i in 0..<80 { Diag.log(.info, "test.event", ["n": "\(i)"], subsystem: "test") }
Diag.flush()
let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
check(files.contains("PeSarma.log") && files.contains("PeSarma.log.1"), "log rotates")
check(!files.contains("PeSarma.log.3"), "only the configured generations are kept")
let total = files.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent($1).path)[.size] as? Int) ?? 0) }
check(total < 600 * 4, "disk use is bounded")
let text = (try? String(contentsOf: Diag.fileURL, encoding: .utf8)) ?? ""
check(text.contains("session=\(Diag.sessionID)") && text.contains("version=") && text.contains("event=test.event"), "lines carry session, version and event")
check(!text.contains(" debug "), "debug is off by default")

// Export holds logs and a manifest, nothing else
let zip = dir.appendingPathComponent("out.zip")
do { try Diag.export(to: zip) } catch { check(false, "export failed: \(error)") }
check(FileManager.default.fileExists(atPath: zip.path), "export creates a ZIP")
let list = Process(); list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); list.arguments = ["-Z1", zip.path]
let pipe = Pipe(); list.standardOutput = pipe; try? list.run(); list.waitUntilExit()
let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
check(names.contains("manifest.txt") && !names.contains(".png") && !names.contains(".mov"), "export has a manifest and no media")

// A logger that cannot write does not throw or block
Diag.fileURL = URL(fileURLWithPath: "/System/forbidden/PeSarma.log")
Diag.log(.error, "test.unwritable")
Diag.flush()
check(true, "an unwritable log directory does not stop the caller")

exit(failures == 0 ? 0 : 1)
