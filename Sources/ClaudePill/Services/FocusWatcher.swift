import AppKit

/// Calls `onClaudeActivated` when the Claude app becomes active.
@MainActor
final class FocusWatcher {
    var onClaudeActivated: (() -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let bundleId = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let bundleId, ClaudeLauncher.bundleIdentifiers.contains(bundleId) else { return }
                self?.onClaudeActivated?()
            }
        }
    }
}
