import AppKit

/// Brings the Claude desktop app to the front. Claude has no API to jump to one session,
/// so every session opens the app.
@MainActor
enum ClaudeLauncher {
    static let bundleIdentifiers = ["com.anthropic.claudefordesktop"]

    static func isClaude(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return bundleIdentifiers.contains(id)
    }

    static var isFrontmost: Bool { isClaude(NSWorkspace.shared.frontmostApplication) }

    static func open(cwd: String?) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { isClaude($0) }) {
            running.activate()
            return
        }
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
    }
}
