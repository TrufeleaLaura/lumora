import LumoraCore
import LumoraEngine
import SwiftUI
import UniformTypeIdentifiers

/// Browse and apply looks (built-in packs, saved presets, imported LUTs) with a strength slider.
struct LooksPanel: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var thumbnails: LookThumbnails

    @State private var pack: LookPack = .trending
    @State private var presets: [UserPreset] = []
    @State private var luts: [ImportedLUT] = []
    @State private var isNamingPreset = false
    @State private var presetName = ""
    @State private var isImportingLUT = false

    private static let cubeType = UTType(filenameExtension: "cube") ?? .data

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            packChips

            HScroll {
                HStack(alignment: .top, spacing: 10) {
                    if pack == .custom {
                        customCells
                    } else {
                        cell(title: "None", key: "none", document: EditDocument(), isSelected: !session.document.look.isActive) {
                            session.selectLook(nil)
                        }
                        ForEach(LookLibrary.looks(in: pack)) { look in
                            lookCell(look)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 108)

            if session.document.look.isActive {
                SliderList(session: session, specs: [AdjustmentCatalog.lookStrength])
            } else {
                Text("Tap a look to apply it. Your own adjustments stay editable underneath.")
                    .font(.caption)
                    .foregroundStyle(Darkroom.stone)
            }

            HStack {
                Button {
                    presetName = ""
                    isNamingPreset = true
                } label: {
                    Label("Save as preset", systemImage: "plus.square.on.square")
                }
                Spacer()
                if pack == .custom {
                    Button {
                        isImportingLUT = true
                    } label: {
                        Label("Import LUT", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .onAppear(perform: reloadCustom)
        .alert("Save preset", isPresented: $isNamingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") {
                session.saveCurrentAsPreset(name: presetName)
                reloadCustom()
                pack = .custom
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves your current adjustments (not the crop) so you can apply them to other photos.")
        }
        .fileImporter(isPresented: $isImportingLUT, allowedContentTypes: [Self.cubeType, .plainText, .data], allowsMultipleSelection: true) { result in
            importLUTs(result)
        }
    }

    // MARK: - Pieces

    private var packChips: some View {
        HScroll {
            HStack(spacing: 6) {
                ForEach(LookPack.allCases) { item in
                    Button {
                        pack = item
                    } label: {
                        Text(item.title)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .drChip(pack == item, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var customCells: some View {
        if presets.isEmpty && luts.isEmpty {
            Text("Saved presets and imported LUTs appear here.")
                .font(.caption)
                .foregroundStyle(Darkroom.stone)
                .frame(height: 90)
        }
        ForEach(presets) { preset in
            cell(title: preset.name, key: "preset.\(preset.id.uuidString)", document: preset.document, isSelected: false) {
                session.applyPreset(preset)
            }
            .contextMenu {
                Button(role: .destructive) {
                    try? PresetStore.shared.delete(preset.id)
                    reloadCustom()
                } label: {
                    Label("Delete preset", systemImage: "trash")
                }
            }
        }
        ForEach(luts) { lut in
            lookCell(lut.look)
                .contextMenu {
                    Button(role: .destructive) {
                        try? LUTStore.shared.delete(lut.id)
                        if session.document.look.lookID == lut.id {
                            session.selectLook(nil)
                        }
                        reloadCustom()
                    } label: {
                        Label("Delete LUT", systemImage: "trash")
                    }
                }
        }
    }

    private func lookCell(_ look: Look) -> some View {
        var document = EditDocument()
        document.look = LookSettings(look: look)
        return cell(title: look.name, key: look.id, document: document, isSelected: session.document.look.lookID == look.id && session.document.look.isActive) {
            session.selectLook(look)
        }
    }

    private func cell(title: String, key: String, document: EditDocument, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Darkroom.raised
                    if let image = thumbnails.image(for: key, document: document) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                // Selected: a cream frame line, like a frame marked on a contact sheet.
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Darkroom.cream, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                )
                .animation(Darkroom.ease, value: isSelected)
                Text(title)
                    .caps(9, weight: isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? Darkroom.cream : Darkroom.stone)
                    .lineLimit(1)
                    .frame(width: 66, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Data

    private func reloadCustom() {
        presets = PresetStore.shared.list()
        luts = LUTStore.shared.list()
    }

    private func importLUTs(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var imported = 0
        var failures: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                try LUTStore.shared.importCube(text: text, name: url.deletingPathExtension().lastPathComponent)
                imported += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        reloadCustom()
        pack = .custom
        if let first = failures.first {
            session.showToast(failures.count == 1 ? first : "\(failures.count) files couldn't be imported")
        } else if imported > 0 {
            session.showToast(imported == 1 ? "LUT imported" : "\(imported) LUTs imported")
        }
    }
}
