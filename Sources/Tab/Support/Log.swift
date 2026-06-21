import Foundation

/// Lightweight diagnostics. Writes to the system log *and* `/tmp/tab.log` so a
/// running session can be inspected with `tail -f /tmp/tab.log` during dev.
enum Log {
    private static let path = "/tmp/tab.log"

    static func info(_ message: String) {
        NSLog("Tab: %@", message)
        let line = "\(timestamp()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
