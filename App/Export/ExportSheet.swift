import LumoraCore
import LumoraEngine
import SwiftUI
import UIKit

/// Export options: format, quality, size, metadata; then save to Photos or share.
struct ExportSheet: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss

    @AppStorage("export.format") private var format: ExportFormat = .heic
    @AppStorage("export.quality") private var quality: Double = 0.92
    @AppStorage("export.size") private var size: ExportSize = .original
    @AppStorage("export.metadata") private var metadata: MetadataPolicy = .removeLocation

    @State private var shareItem: ShareItem?

    private var options: ExportOptions {
        ExportOptions(format: format, quality: quality, size: size, metadata: metadata)
    }

    private var outputSize: String {
        let pixels = session.outputPixelSize
        var scale: CGFloat = 1
        if let maxEdge = size.maxLongEdge {
            scale = min(1, CGFloat(maxEdge) / max(pixels.width, pixels.height))
        } else if size == .enlarged {
            scale = 2
        }
        return "\(Int((pixels.width * scale).rounded(.down))) × \(Int((pixels.height * scale).rounded(.down))) px"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    if format.supportsQuality {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Quality")
                                Spacer()
                                Text("\(Int((quality * 100).rounded()))%")
                                    .foregroundStyle(Aura.gradient)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            Slider(value: $quality, in: 0.5...1.0, step: 0.01)
                        }
                    }
                }
                .auraRow()

                Section {
                    Picker("Size", selection: $size) {
                        ForEach(ExportSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    Picker("Metadata", selection: $metadata) {
                        ForEach(MetadataPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                } footer: {
                    Text("Output: \(outputSize)")
                }
                .auraRow()
            }
            .auraFormStyle()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        session.saveToPhotos(options: options)
                        dismiss()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AuraPrimaryButtonStyle())
                    .disabled(session.isExporting)

                    Button {
                        Task {
                            if let url = await session.exportFile(options: options) {
                                shareItem = ShareItem(url: url)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if session.isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text("Share…")
                        }
                        .font(.headline)
                        .foregroundStyle(Aura.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .auraGlass(Capsule(), tint: 0.5)
                    }
                    .buttonStyle(AuraPressStyle())
                    .disabled(session.isExporting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
                    .ignoresSafeArea()
            }
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
