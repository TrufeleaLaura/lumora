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

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                newEditButton
                HStack(spacing: 12) {
                    collageButton
                    sampleButton
                }

                if !library.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Your edits")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Aura.textPrimary)
                            Text("\(library.projects.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Aura.gradient)
                            Spacer()
                            if mode == .edits {
                                Button(isSelecting ? "Done" : "Select") {
                                    withAnimation(Aura.spring) {
                                        isSelecting.toggle()
                                        selection.removeAll()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Aura.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .auraGlass(Capsule(), tint: 0.5, rim: 0.5)
                                .buttonStyle(AuraPressStyle())
                            }
                        }
                        AuraSegmented(selection: $mode, options: Mode.allCases) { $0.title }
                            .frame(maxWidth: 260)
                    }
                    .padding(.top, 6)
                    if mode == .feed {
                        feedGrid
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(library.projects.enumerated()), id: \.element.id) { index, project in
                            ProjectTile(image: library.thumbnail(for: project))
                                .overlay(alignment: .topTrailing) {
                                    if isSelecting {
                                        let chosen = selection.contains(project.id)
                                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(chosen ? AnyShapeStyle(Aura.gradient) : AnyShapeStyle(Color.white))
                                            .shadow(color: chosen ? Aura.lavender.opacity(0.8) : .black.opacity(0.4), radius: 4)
                                            .padding(7)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .overlay {
                                    if isSelecting && selection.contains(project.id) {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Aura.diagonal, lineWidth: 2.5)
                                    }
                                }
                                .scaleEffect(isSelecting && selection.contains(project.id) ? 0.94 : 1)
                                .animation(Aura.bouncy, value: selection)
                                .opacity(tilesAppeared ? 1 : 0)
                                .offset(y: tilesAppeared ? 0 : 18)
                                .animation(Aura.spring.delay(Double(min(index, 14)) * 0.035), value: tilesAppeared)
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
                    }
                    .transition(.opacity.combined(with: .offset(y: 12)))
                    .onAppear { tilesAppeared = true }
                    }
                } else {
                    emptyState
                }

                if let message = library.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                VStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(Aura.gradient)
                    Text("Lumora \(Bundle.main.appVersion) · made on your iPhone, for you")
                        .font(.caption2)
                        .foregroundStyle(Aura.textSecondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .animation(Aura.spring, value: mode)
        }
        .scrollIndicators(.hidden)
        .background(AuraBackground(paused: isCovered))
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
                    Aura.plum.opacity(0.55).ignoresSafeArea()
                    AuraLoader(caption: "Opening…")
                        .padding(.horizontal, 30)
                        .padding(.vertical, 24)
                        .auraGlass(cornerRadius: 24)
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
        .animation(Aura.soft, value: library.isBusy)
        .sheet(isPresented: $isShowingSettings, onDismiss: { library.reload() }) {
            SettingsView(store: library.store) {
                library.delete(library.projects.map(\.id))
            }
            .presentationBackground(Aura.plum)
            .presentationCornerRadius(30)
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
            Text(selection.isEmpty ? "Select photos" : "\(selection.count) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Aura.textPrimary)
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
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .auraGlass(Capsule(), tint: 0.6)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Another screen covers the library: its ambient motion pauses (the editor needs the GPU).
    private var isCovered: Bool {
        session != nil || isMakingCollage || !hasSeenOnboarding
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(2.2)
                    .foregroundStyle(Aura.textSecondary)
                LumoraWordmark()
                Text("Your photos, in their best light.")
                    .font(.subheadline)
                    .foregroundStyle(Aura.textSecondary)
            }
            Spacer()
            AuraIconButton(symbol: "gearshape", size: 42) {
                isShowingSettings = true
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 14)
    }

    private var newEditButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
            AuraHeroCard(
                eyebrow: "New edit",
                title: "Make it glow",
                subtitle: "Choose a photo from your library",
                symbol: "plus",
                paused: isCovered
            )
        }
        .buttonStyle(AuraPressStyle(scale: 0.97))
        .disabled(library.isBusy)
        .accessibilityLabel("New edit")
    }

    private var collageButton: some View {
        Button {
            isMakingCollage = true
        } label: {
            AuraFeatureCard(symbol: "square.grid.2x2", title: "Collage & story", subtitle: "Layouts, moodboards, 9:16")
        }
        .buttonStyle(AuraPressStyle(scale: 0.96))
        .disabled(library.isBusy)
    }

    private var sampleButton: some View {
        Button {
            Task { session = await library.openSample() }
        } label: {
            AuraFeatureCard(symbol: "wand.and.stars", title: "Try a sample", subtitle: "Explore every tool")
        }
        .buttonStyle(AuraPressStyle(scale: 0.96))
        .disabled(library.isBusy)
    }

    /// Instagram-style 3-column preview of the planned feed; drag tiles to reorder.
    private var feedGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag photos to plan how your grid will look. Top-left is the newest post.")
                .font(.caption)
                .foregroundStyle(Aura.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(library.feed) { project in
                    Aura.surfaceRaised
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Aura.rim, lineWidth: 0.8))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Aura.diagonal)
                    .frame(width: 96, height: 96)
                    .blur(radius: 28)
                    .opacity(0.55)
                Image(systemName: "photo.stack")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Aura.gradient)
                    .frame(width: 76, height: 76)
                    .auraGlass(Circle(), tint: 0.4)
            }
            Text("Your edits will live here")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Aura.textPrimary)
            Text("Every photo keeps its original, so you can change your mind anytime.")
                .font(.footnote)
                .foregroundStyle(Aura.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Aura.surfaceRaised
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .contentShape(shape)
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
