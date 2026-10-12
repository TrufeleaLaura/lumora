import LumoraEngine
import PhotosUI
import SwiftUI

struct LibraryView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var session: EditorSession?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 10) {
                    Text("Lumora")
                        .font(.system(size: 48, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.gradient)
                    Text("Edit, retouch and reshape — beautifully.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                    Label("Edit a photo", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(Theme.gradient, in: Capsule())
                }
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Text("Version \(Bundle.main.appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            open(item)
        }
        .fullScreenCover(item: $session) { session in
            EditorView(session: session) {
                self.session = nil
            }
        }
    }

    private func open(_ item: PhotosPickerItem) {
        isLoading = true
        errorMessage = nil
        Task {
            defer {
                isLoading = false
                pickerItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let source = ImageSource(data: data) else {
                    errorMessage = "This photo couldn't be opened."
                    return
                }
                session = EditorSession(source: source)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
