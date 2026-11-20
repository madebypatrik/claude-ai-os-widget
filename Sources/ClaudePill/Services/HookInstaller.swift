import Foundation

/// Installs ClaudePill hooks into Claude Code's user settings (`~/.claude/settings.json`).
///
/// That file is shared with everything else Claude Code uses, so it is never overwritten wholesale:
/// the JSON is parsed, one hook group per event pointing at `~/.claudepill/report.sh` is added,
/// and uninstall removes only those groups. A one-time backup is kept as `settings.json.claudepill.bak`.
struct HookInstaller {
    static let marker = "ClaudePill"
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]
    /// Tool events take a matcher; "*" matches every tool.
    private static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]

    enum InstallError: LocalizedError {
        case unreadableSettings(String)
        var errorDescription: String? {
            switch self {
            case .unreadableSettings(let reason): "Kunde inte läsa ~/.claude/settings.json: \(reason)"
            }
        }
    }

    let home: URL

    /// `CLAUDEPILL_HOME` overrides the home folder (used to test install/uninstall safely).
    init(home: URL = ProcessInfo.processInfo.environment["CLAUDEPILL_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    var scriptURL: URL { home.appendingPathComponent(".claudepill/report.sh") }
    var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    var backupURL: URL { home.appendingPathComponent(".claude/settings.json.claudepill.bak") }

    var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path),
              let settings = try? readSettings(),
              let hooks = settings["hooks"] as? [String: Any]
        else { return false }
        return Self.events.allSatisfy { event in
            (hooks[event] as? [Any])?.contains(where: isOurGroup) ?? false
        }
    }

    var installedPort: Int? {
        guard let script = try? String(contentsOf: scriptURL, encoding: .utf8),
              let range = script.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression)
        else { return nil }
        return Int(script[range].split(separator: ":").last ?? "")
    }

    func scriptContents(port: UInt16) -> String {
        """
        #!/bin/bash
        # \(Self.marker): skickar Claude Code hook-payload till ClaudePill. Får ALDRIG skriva till stdout.
        curl -s -m 1 -X POST \\
          -H "Content-Type: application/json" \\
          --data-binary @- \\
          http://127.0.0.1:\(port)/event >/dev/null 2>&1
        exit 0

        """
    }

    func install(port: UInt16) throws {
        let fm = FileManager.default
        var settings = try readSettings() // fail before touching anything if unreadable
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scriptContents(port: port).write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        if fm.fileExists(atPath: settingsURL.path), !fm.fileExists(atPath: backupURL.path) {
            try fm.copyItem(at: settingsURL, to: backupURL)
        }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            var groups = (hooks[event] as? [Any] ?? []).filter { !isOurGroup($0) }
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": scriptURL.path, "timeout": 2]],
            ]
            if Self.toolEvents.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    func uninstall() throws {
        var settings = try readSettings()
        if var hooks = settings["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard let groups = value as? [Any] else { continue }
                let kept = groups.filter { !isOurGroup($0) }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
            try writeSettings(settings)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: scriptURL.path) { try fm.removeItem(at: scriptURL) }
        let dir = scriptURL.deletingLastPathComponent()
        if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true { try? fm.removeItem(at: dir) }
    }

    // MARK: - Helpers

    private func isOurGroup(_ value: Any) -> Bool {
        guard let group = value as? [String: Any], let hooks = group["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains("/.claudepill/report.sh") == true }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            // Never overwrite a settings file we cannot parse.
            throw InstallError.unreadableSettings(error.localizedDescription)
        }
        guard let dict = object as? [String: Any] else { throw InstallError.unreadableSettings("inte ett JSON-objekt") }
        return dict
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic)
    }
}
