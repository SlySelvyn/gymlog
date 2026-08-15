// ProfileView.swift — spec §6.5. Profile stub (username/avatar, all local) and
// Settings: units, theme, Action Button mode, confirm mode, rest-timer cap,
// export (Markdown/CSV via share sheet), about. Lightweight prefs mirror to
// NSUbiquitousKeyValueStore (§10: iCloud KV backup of prefs only).

import SwiftUI
import GymLogCore

struct ProfileView: View {
    @EnvironmentObject var coordinator: SessionCoordinator

    // §6.5 settings — AppStorage keys shared with the coordinator/capture view.
    @AppStorage("username") private var username = ""
    @AppStorage("units") private var unitsRaw = WeightUnit.lb.rawValue
    @AppStorage("theme") private var theme = "system"
    @AppStorage("confirmMode") private var confirmFirst = false
    @AppStorage("restCapSeconds") private var restCap = 600
    @AppStorage("actionButtonMode") private var actionButtonMode = "openAndListen"
    @AppStorage("allowWeightOnlyDraft") private var allowWeightOnly = false

    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Username (optional)", text: $username)
                }

                Section("Units & appearance") {
                    Picker("Units", selection: $unitsRaw) {
                        Text("Pounds (lb)").tag(WeightUnit.lb.rawValue)
                        Text("Kilograms (kg)").tag(WeightUnit.kg.rawValue)
                    }
                    Picker("Theme", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section {
                    Picker("Action Button", selection: $actionButtonMode) {
                        Text("Open app & listen").tag("openAndListen")
                        Text("Siri phrase").tag("siriPhrase")
                    }
                    Toggle("Confirm before saving", isOn: $confirmFirst)
                    Toggle("Allow weight-only sets", isOn: $allowWeightOnly)
                    Stepper("Rest cap: \(restCap / 60) min",
                            value: $restCap, in: 120...1800, step: 60)
                } header: {
                    Text("Voice logging")
                } footer: {
                    Text("Assign the “Log a Set” shortcut to the Action Button in iOS Settings → Action Button. Confirm mode shows the parsed set before saving; otherwise sets auto-commit with an easy Undo.")
                }

                Section {
                    Button {
                        exportURL = writeExport(ExportService.markdown(coordinator.history,
                                                                       displayUnit: coordinator.displayUnit),
                                                filename: "gymlog-export.md")
                    } label: {
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                    Button {
                        exportURL = writeExport(ExportService.csv(coordinator.history),
                                                filename: "gymlog-export.csv")
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("All data lives on this device, encrypted at rest. Exports contain every logged set.")
                }

                Section("About") {
                    LabeledContent("Version",
                                   value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
                    LabeledContent("Storage", value: "On-device (Core Data)")
                }
            }
            .navigationTitle("Profile")
            .onChange(of: unitsRaw) { syncPrefsToICloudKV() }
            .onChange(of: theme) { syncPrefsToICloudKV() }
            .onChange(of: actionButtonMode) { syncPrefsToICloudKV() }
        }
    }

    // MARK: Export file writing (share sheet needs a file URL)

    private func writeExport(_ content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: §10 — iCloud Key-Value backup of lightweight prefs ONLY

    private func syncPrefsToICloudKV() {
        let kv = NSUbiquitousKeyValueStore.default
        kv.set(unitsRaw, forKey: "units")
        kv.set(theme, forKey: "theme")
        kv.set(actionButtonMode, forKey: "actionButtonMode")
        kv.synchronize()
    }
}
