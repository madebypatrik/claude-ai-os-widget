import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let runningPort: UInt16
    let serverStatus: () -> String
    let installHooks: () -> String?
    let uninstallHooks: () -> String?

    @State private var hooksInstalled = HookInstaller().isInstalled
    @State private var installedPort = HookInstaller().installedPort
    @State private var message: String?

    var body: some View {
        Form {
            Section("Beteende") {
                Toggle("Visa flytande widget under pillen hela tiden", isOn: $settings.alwaysVisible)
                Toggle("Fäll ut kortet automatiskt", isOn: $settings.autoExpand)
                    .disabled(settings.alwaysVisible)
                Toggle("Spela ljud vid godkännande", isOn: $settings.soundEnabled)
                Toggle("Starta vid inloggning", isOn: $settings.launchAtLogin)
            }

            Section("Server och hooks") {
                LabeledContent("Server", value: serverStatus())
                LabeledContent("Port") {
                    TextField("", value: $settings.port, format: .number.grouping(.never))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                if settings.port != Int(runningPort) {
                    Text("Ny port används efter omstart. Installera om hooks så att report.sh pekar rätt.")
                        .font(.caption).foregroundStyle(Theme.orange)
                }
                LabeledContent("Hooks i ~/.claude/settings.json") {
                    HStack {
                        Text(hookStatus).foregroundStyle(.secondary)
                        Button(hooksInstalled ? "Installera om" : "Installera") {
                            message = installHooks()
                            refresh()
                        }
                        if hooksInstalled {
                            Button("Avinstallera") {
                                message = uninstallHooks()
                                refresh()
                            }
                        }
                    }
                }
                Text("Nya hooks gäller för Claude Code-sessioner som startas efter installationen.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
    }

    private var hookStatus: String {
        guard hooksInstalled else { return "Ej installerade" }
        if let installedPort { return "Installerade (port \(installedPort))" }
        return "Installerade"
    }

    private func refresh() {
        let installer = HookInstaller()
        hooksInstalled = installer.isInstalled
        installedPort = installer.installedPort
    }
}
