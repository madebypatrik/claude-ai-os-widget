import ClaudePillCore
import Foundation
import Observation
import ServiceManagement

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let defaultPort = 47824

    private enum Key {
        static let port = "port"
        static let soundEnabled = "soundEnabled"
        static let autoExpand = "autoExpand"
        static let didOnboard = "didCompleteOnboarding"
        static let alwaysVisible = "alwaysVisible"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    var autoExpand: Bool { didSet { defaults.set(autoExpand, forKey: Key.autoExpand) } }
    var didCompleteOnboarding: Bool { didSet { defaults.set(didCompleteOnboarding, forKey: Key.didOnboard) } }
    /// Floating small widget under the pill all the time (off: info lives in the pill, card drops down when needed).
    var alwaysVisible: Bool { didSet { defaults.set(alwaysVisible, forKey: Key.alwaysVisible) } }

    /// Backed by `SMAppService`, so it reflects what System Settings says.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("ClaudePill: launch at login failed: \(error.localizedDescription)")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.port: Self.defaultPort,
            Key.soundEnabled: true,
            Key.autoExpand: true,
            Key.didOnboard: false,
            Key.alwaysVisible: false,
        ])
        port = defaults.integer(forKey: Key.port)
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        autoExpand = defaults.bool(forKey: Key.autoExpand)
        didCompleteOnboarding = defaults.bool(forKey: Key.didOnboard)
        alwaysVisible = defaults.bool(forKey: Key.alwaysVisible)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var stateMachineConfig: StateMachineConfig {
        StateMachineConfig() // Claude Code reports approvals explicitly; no timer heuristic
    }

    var validPort: UInt16 {
        (1024...65535).contains(port) ? UInt16(port) : UInt16(Self.defaultPort)
    }
}
