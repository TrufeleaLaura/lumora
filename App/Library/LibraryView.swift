import LumoraCore
import LumoraEngine
import PhotosUI
import SwiftUI

struct LibraryView: View {
    @StateObject private var library = LibraryModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var session: EditorSession?
    @State private var projectToDelete: ProjectMetadata?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                newEditButton

                if !library.projects.isEmpty {
                    Text("Recent")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(library.projects) { project in
                            ProjectTile(image: library.thumbnail(for: project))
                                .onTapGesture { open(project) }
                                .contextMenu {
                                    Button {
                                        library.duplicate(project)
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } else {
                    emptyState
                }

                if let message = library.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("Version \(Bundle.main.appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if library.isBusy {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Opening…")
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onAppear { library.reload() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .fullScreenCover(item: $session, onDismiss: { library.reload() }) { session in
            EditorView(session: session) {
                self.session = nil
            }
        }
        .confirmationDialog(
            "Delete this edit?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    library.delete(project)
                }
                projectToDelete = nil
            }
        } message: {
            Text("The edit is removed from Lumora. Your original photo in the Photos app is not affected.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lumora")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.gradient)
            Text("Edit, retouch and reshape — beautifully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    private var newEditButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("New edit")
                        .font(.headline)
                    Text("Choose a photo from your library")
                        .font(.caption)
                        .opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(library.isBusy)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Your edits will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { pickerItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    library.errorMessage = LibraryError.unreadablePhoto.localizedDescription
                    return
                }
                session = await library.importPhoto(data: data)
            } catch {
                library.errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ project: ProjectMetadata) {
        Task {
            session = await library.open(project)
        }
    }
}

struct ProjectTile: View {
    let image: UIImage?

    var body: some View {
        Theme.panelRaised
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
    }
}
