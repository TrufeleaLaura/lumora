import LumoraCore
import SwiftUI

/// App settings: export defaults, storage and about.
struct SettingsView: View {
    let store: ProjectStore
    let onDeleteAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.format") private var format: ExportFormat = .heic
    @AppStorage("export.quality") private var quality: Double = 0.92
    @AppStorage("export.size") private var size: ExportSize = .original
    @AppStorage("export.metadata") private var metadata: MetadataPolicy = .removeLocation
    @AppStorage("onboarding.seen") private var hasSeenOnboarding = true

    @State private var storageText = "…"
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Export defaults") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    if format.supportsQuality {
                        HStack {
                            Text("Quality")
                            Slider(value: $quality, in: 0.5...1)
                            Text("\(Int((quality * 100).rounded()))")
                                .monospacedDigit()
                                .foregroundStyle(Aura.textSecondary)
                        }
                    }
                    Picker("Size", selection: $size) {
                        ForEach(ExportSize.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Metadata", selection: $metadata) {
                        ForEach(MetadataPolicy.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                .auraRow()

                Section {
                    LabeledContent("Saved edits", value: storageText)
                    Button("Delete all edits", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Edits keep a copy of each original so they can be changed later. Your Photos library is never changed.")
                }
                .auraRow()

                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    Button("Show the welcome tour") {
                        hasSeenOnboarding = false
                        dismiss()
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Everything in Lumora runs on your iPhone: no account, no uploads, no tracking. Sample photo by Tan Duong on Unsplash.")
                }
                .auraRow()

                Section {
                    VStack(spacing: 6) {
                        LumoraWordmark(size: 28)
                        Text("Your photos, in their best light.")
                            .font(.footnote)
                            .foregroundStyle(Aura.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
            }
            .auraFormStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete all edits?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    onDeleteAll()
                    refreshStorage()
                }
            } message: {
                Text("All edits are removed from Lumora. Your original photos in the Photos app are not affected.")
            }
            .task { refreshStorage() }
        }
    }

    private func refreshStorage() {
        let root = store.rootURL
        let count = store.list().count
        Task.detached(priority: .utility) {
            var bytes: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in enumerator {
                    bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            let text = "\(count) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
            await MainActor.run { storageText = text }
        }
    }
}
