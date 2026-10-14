import LumoraCore
import LumoraEngine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var library = LibraryModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var session: EditorSession?
    @State private var projectToDelete: ProjectMetadata?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var isConfirmingBatchDelete = false
    @State private var mode: Mode = .edits
    @State private var isMakingCollage = false
    @State private var dragged: UUID?
    @State private var isShowingSettings = false
    /// Tiles rise in one after another the first time the grid shows.
    @State private var tilesAppeared = false
    @AppStorage("onboarding.seen") private var hasSeenOnboarding = false

    enum Mode: String, CaseIterable, Identifiable {
        case edits, feed
        var id: String { rawValue }
        var title: String { self == .edits ? "Edits" : "Feed plan" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                newEditButton
                    .padding(.top, 22)
                VStack(spacing: 0) {
                    row("Collage and story", detail: "Layouts, moodboards and 9:16 stories", symbol: "square.grid.2x2") {
                        isMakingCollage = true
                    }
                    Hairline()
                    row("Sample photo", detail: "Try every tool on a portrait", symbol: "photo") {
                        Task { session = await library.openSample() }
                    }
                    Hairline()
                }
                .padding(.top, 14)

                if !library.projects.isEmpty {
                    HStack(alignment: .center) {
                        SegmentedTabs(selection: $mode, options: Mode.allCases) { $0.title }
                            .frame(maxWidth: 230)
                        Spacer()
                        if mode == .edits {
                            Button(isSelecting ? "Done" : "Select") {
                                withAnimation(Darkroom.spring) {
                                    isSelecting.toggle()
                                    selection.removeAll()
                                }
                            }
                            .caps(11)
                            .foregroundStyle(isSelecting ? Darkroom.safelight : Darkroom.cream)
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 14)
                    if mode == .feed {
                        feedGrid
                            .transition(.opacity)
                    } else {
                        contactSheet
                            .transition(.opacity)
                    }
                } else {
                    emptyState
                }

                if let message = library.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Darkroom.safelight)
                        .padding(.top, 12)
                }

                Text("Lumora \(Bundle.main.appVersion) · processed on device")
                    .filmCode(9)
                    .foregroundStyle(Darkroom.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .animation(Darkroom.ease, value: mode)
        }
        .scrollIndicators(.hidden)
        .background(Darkroom.ink.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) edits?",
            isPresented: $isConfirmingBatchDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.delete(Array(selection))
                selection.removeAll()
                isSelecting = false
            }
        } message: {
            Text("Your original photos in the Photos app are not affected.")
        }
        .overlay {
            if library.isBusy {
                ZStack {
                    Darkroom.ink.opacity(0.55).ignoresSafeArea()
                    DevelopingIndicator(caption: "Opening…")
                        .padding(.horizontal, 30)
                        .padding(.vertical, 24)
                        .drSurface(cornerRadius: 4)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            library.reload()
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-skipOnboarding") {
                hasSeenOnboarding = true
            }
            if arguments.contains("-demo"), session == nil {
                Task { session = await library.openSample() }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .animation(Darkroom.ease, value: library.isBusy)
        .sheet(isPresented: $isShowingSettings, onDismiss: { library.reload() }) {
            SettingsView(store: library.store) {
                library.delete(library.projects.map(\.id))
            }
            .presentationBackground(Darkroom.ink)
        }
        .fullScreenCover(isPresented: Binding(get: { !hasSeenOnboarding }, set: { if !$0 { hasSeenOnboarding = true } })) {
            OnboardingView { hasSeenOnboarding = true }
        }
        .fullScreenCover(isPresented: $isMakingCollage) {
            CollageView(store: library.store, projects: library.projects, thumbnail: { library.thumbnail(for: $0) }) {
                isMakingCollage = false
            }
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

    private var selectionBar: some View {
        HStack(spacing: 18) {
            Text(selection.isEmpty ? "Select frames" : "\(selection.count) selected")
                .caps(11)
                .foregroundStyle(Darkroom.cream)
                .contentTransition(.numericText())
            Spacer()
            Button {
                guard let copied = EditClipboard.document else { return }
                let ids = Array(selection)
                Task {
                    await library.pasteEdits(copied, to: ids)
                    selection.removeAll()
                    isSelecting = false
                }
            } label: {
                Label("Paste edits", systemImage: "doc.on.clipboard")
            }
            .disabled(selection.isEmpty || EditClipboard.document == nil)
            Button(role: .destructive) {
                isConfirmingBatchDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selection.isEmpty)
            .accessibilityLabel("Delete selected")
        }
        .font(.system(size: 15, weight: .light))
        .foregroundStyle(Darkroom.cream)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Darkroom.surface)
        .overlay(alignment: .top) { Hairline() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Wordmark(size: 20)
                Spacer()
                IconButton(symbol: "gearshape") {
                    isShowingSettings = true
                }
                .padding(.trailing, -10)
                .accessibilityLabel("Settings")
            }
            // A film-edge code line.
            HStack(spacing: 8) {
                Text("\u{25B8}")
                    .foregroundStyle(Darkroom.safelight)
                Text("LUMORA 400")
                Spacer()
                Text(frameCount)
            }
            .filmCode(10)
            .foregroundStyle(Darkroom.stone)
            Hairline()
        }
        .padding(.top, 8)
    }

    private var frameCount: String {
        let count = library.projects.count
        if count == 0 { return "NO FRAMES" }
        return "\(count) FRAME" + (count == 1 ? "" : "S")
    }

    private var newEditButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .ultraLight))
                VStack(alignment: .leading, spacing: 4) {
                    Text("New edit")
                        .caps(13)
                    Text("Choose a photo from your library")
                        .font(.footnote)
                        .foregroundStyle(Darkroom.stone)
                }
                Spacer()
                Circle()
                    .fill(Darkroom.safelight)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(Darkroom.cream)
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .background(Darkroom.surface)
            .overlay(ViewfinderFrame(length: 12).stroke(Darkroom.cream, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .disabled(library.isBusy)
        .accessibilityLabel("New edit")
    }

    private func row(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .light))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(Darkroom.cream)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Darkroom.stone)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Darkroom.stone)
            }
            .foregroundStyle(Darkroom.cream)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.99))
        .disabled(library.isBusy)
    }

    /// Edits laid out like a contact sheet: strips of three frames between sprocket holes.
    private var contactSheet: some View {
        let projects = library.projects
        let rows = stride(from: 0, to: projects.count, by: 3).map { Array(projects[$0..<min($0 + 3, projects.count)]) }
        return LazyVStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                VStack(spacing: 7) {
                    Sprockets()
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.element.id) { column, project in
                            frame(project, index: rowIndex * 3 + column)
                        }
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    Sprockets()
                }
                .padding(7)
                .background(Darkroom.film)
                .opacity(tilesAppeared ? 1 : 0)
                .offset(y: tilesAppeared ? 0 : 8)
                .animation(Darkroom.ease.delay(Double(min(rowIndex, 8)) * 0.05), value: tilesAppeared)
            }
        }
        .onAppear { tilesAppeared = true }
    }

    private func frame(_ project: ProjectMetadata, index: Int) -> some View {
        let chosen = isSelecting && selection.contains(project.id)
        return VStack(alignment: .leading, spacing: 5) {
            ProjectTile(image: library.thumbnail(for: project))
                .overlay {
                    if chosen {
                        Rectangle().strokeBorder(Darkroom.cream, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: chosen ? "checkmark.square.fill" : "square")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(chosen ? Darkroom.safelight : Color.white.opacity(0.85))
                            .padding(6)
                            .transition(.opacity)
                    }
                }
            Text(Darkroom.frameCode(index))
                .filmCode(9)
                .foregroundStyle(Darkroom.safelight)
        }
        .frame(maxWidth: .infinity)
        .animation(Darkroom.ease, value: chosen)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selection.contains(project.id) {
                    selection.remove(project.id)
                } else {
                    selection.insert(project.id)
                }
            } else {
                open(project)
            }
        }
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

    /// Instagram-style 3-column preview of the planned feed; drag tiles to reorder.
    private var feedGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag photos to plan how your grid will look. Top-left is the newest post.")
                .font(.caption)
                .foregroundStyle(Darkroom.stone)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(library.feed) { project in
                    Darkroom.raised
                        .aspectRatio(4.0 / 5.0, contentMode: .fit)
                        .overlay {
                            if let image = library.thumbnail(for: project) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .clipped()
                        .opacity(dragged == project.id ? 0.5 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { open(project) }
                        .onDrag {
                            dragged = project.id
                            return NSItemProvider(object: project.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: FeedDropDelegate(target: project.id, dragged: $dragged, library: library))
                }
            }
            .overlay(Rectangle().strokeBorder(Darkroom.line, lineWidth: 0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                ViewfinderFrame(length: 16)
                    .stroke(Darkroom.cream.opacity(0.55), lineWidth: 1)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(Darkroom.stone)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("00")
                    .filmCode(9)
                    .foregroundStyle(Darkroom.safelight)
                    .padding(8)
            }
            .frame(width: 116, height: 145)
            Text("No frames yet")
                .caps(12)
                .foregroundStyle(Darkroom.cream)
            Text("Your edits appear here as a contact sheet. Originals are always kept, so you can change your mind anytime.")
                .font(.footnote)
                .foregroundStyle(Darkroom.stone)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
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
        Darkroom.raised
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(Rectangle())
            .contentShape(Rectangle())
    }
}

/// Reorders the feed plan while a tile is dragged over another.
struct FeedDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragged: UUID?
    let library: LibraryModel

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        MainActor.assumeIsolated {
            withAnimation(.easeInOut(duration: 0.15)) {
                library.moveInFeed(dragged, to: target)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
