import AppKit
import SwiftUI

/// First-run flow: install hooks into Claude Code, allow notifications.
struct OnboardingView: View {
    let settings: AppSettings
    let installHooks: () -> String?   // returns an error message, or nil on success
    let requestNotifications: () async -> Bool
    let onDone: () -> Void

    @State private var hooksInstalled = HookInstaller().isInstalled
    @State private var hookError: String?
    @State private var notificationsGranted: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle().fill(Theme.source).frame(width: 10, height: 10)
                Text("Välkommen till ClaudePill").font(.title2.weight(.semibold))
            }
            Text("ClaudePill visar i menyraden vilka Claude Code-sessioner som arbetar och när någon väntar på dig.")
                .foregroundStyle(.secondary)

            step(1, "Installera hooks", done: hooksInstalled) {
                Text("Lägger till ClaudePill i `~/.claude/settings.json` (befintliga hooks behålls, backup som `settings.json.claudepill.bak`) och skapar `~/.claudepill/report.sh`.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(hooksInstalled ? "Installera om" : "Installera hooks") {
                        hookError = installHooks()
                        hooksInstalled = HookInstaller().isInstalled
                    }
                    if let hookError { Text(hookError).foregroundStyle(.red).font(.caption) }
                }
                Text("Gäller sessioner som startas efter installationen.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            step(2, "Tillåt notiser", done: notificationsGranted == true, optional: true) {
                Button(notificationButtonTitle) {
                    Task { notificationsGranted = await requestNotifications() }
                }
            }

            Divider()

            HStack {
                Toggle("Starta vid inloggning", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                Spacer()
                Button("Klar") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var notificationButtonTitle: String {
        switch notificationsGranted {
        case .some(true): "Notiser på ✓"
        case .some(false): "Notiser nekade"
        case .none: "Tillåt notiser"
        }
    }

    @ViewBuilder
    private func step(_ number: Int, _ title: String, done: Bool, optional: Bool = false,
                      @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Theme.green : Color.primary.opacity(0.1)).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if optional { Text("valfritt").font(.caption).foregroundStyle(.tertiary) }
                }
                content()
            }
        }
    }
}
