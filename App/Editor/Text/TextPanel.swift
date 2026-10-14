import LumoraCore
import SwiftUI

/// Text and stickers: add, pick a layer, style it. Drag layers on the photo to move them.
struct TextPanel: View {
    @ObservedObject var session: EditorSession
    @State private var isAddingText = false
    @State private var isEditingText = false
    @State private var draft = ""
    @State private var showsStickers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    draft = ""
                    isAddingText = true
                } label: {
                    Label("Text", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .drChip(true, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(PressStyle())
                Button {
                    showsStickers.toggle()
                } label: {
                    Label("Sticker", systemImage: "heart")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .drChip(showsStickers, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(PressStyle())
                layerChips
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showsStickers {
                        stickerGrid
                    }
                    if let index = session.selectedTextIndex, !session.document.texts[index].isSticker {
                        styleChips(index)
                    }
                    if let index = session.selectedTextIndex {
                        LayerEditor(session: session, index: index, onEditText: {
                            draft = session.document.texts[index].text
                            isEditingText = true
                        })
                    } else if session.document.texts.isEmpty && !showsStickers {
                        Text("Add text or stickers, then drag them on the photo.")
                            .font(.footnote)
                            .foregroundStyle(Darkroom.stone)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .alert("Add text", isPresented: $isAddingText) {
            TextField("Text", text: $draft)
            Button("Add") { session.addText(draft) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Edit text", isPresented: $isEditingText) {
            TextField("Text", text: $draft)
            Button("Done") {
                let text = draft
                session.updateSelectedText("Edit text") { $0.text = text }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var layerChips: some View {
        HScroll {
            HStack(spacing: 6) {
                ForEach(session.document.texts) { layer in
                    let selected = layer.id == session.selectedTextID
                    Button {
                        session.selectedTextID = selected ? nil : layer.id
                    } label: {
                        Group {
                            if let symbol = layer.symbol {
                                Image(systemName: symbol)
                            } else {
                                Text(layer.text).lineLimit(1)
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: 90)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .drChip(selected, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    /// One-tap text styles, shown in their own font.
    private func styleChips(_ index: Int) -> some View {
        HScroll {
            HStack(spacing: 6) {
                ForEach(TextStylePreset.all) { preset in
                    Button {
                        session.updateSelectedText("Style \(preset.title)") { preset.style(&$0) }
                    } label: {
                        Text(preset.title)
                            .font(previewFont(for: preset))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .drTile(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
    }

    private func previewFont(for preset: TextStylePreset) -> Font {
        var layer = TextLayer()
        preset.style(&layer)
        switch layer.font {
        case .sans: return .system(size: 14, weight: .semibold)
        case .serif: return .system(size: 14, weight: .semibold, design: .serif)
        case .rounded: return .system(size: 14, weight: .semibold, design: .rounded)
        case .mono: return .system(size: 14, weight: .semibold, design: .monospaced)
        default: return .custom(layer.font.fontName ?? "", size: 15)
        }
    }

    private var stickerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 10) {
            ForEach(StickerCatalog.symbols, id: \.self) { symbol in
                Button {
                    session.addSticker(symbol)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .drTile(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

/// Style controls of one text or sticker layer.
private struct LayerEditor: View {
    @ObservedObject var session: EditorSession
    let index: Int
    let onEditText: () -> Void

    var body: some View {
        let layer = session.document.texts[index]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if !layer.isSticker {
                    Button(action: onEditText) {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                Button {
                    session.updateSelectedText(layer.shadow ? "No shadow" : "Shadow") { $0.shadow.toggle() }
                } label: {
                    Label("Shadow", systemImage: layer.shadow ? "shadow" : "circle.dashed")
                }
                Button {
                    session.duplicateSelectedText()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .accessibilityLabel("Duplicate")
                Spacer()
                Button(role: .destructive) {
                    session.deleteSelectedText()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
            .font(.footnote)

            if !layer.isSticker {
                HScroll {
                    HStack(spacing: 6) {
                        ForEach(TextFont.allCases) { font in
                            let selected = layer.font == font
                            Button {
                                session.updateSelectedText("Font \(font.title)") { $0.font = font }
                            } label: {
                                Text(font.title)
                                    .font(previewFont(font))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .drChip(selected, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                Picker("Alignment", selection: Binding(
                    get: { layer.alignment },
                    set: { value in session.updateSelectedText("Alignment") { $0.alignment = value } }
                )) {
                    Image(systemName: "text.alignleft").tag(TextAlign.left)
                    Image(systemName: "text.aligncenter").tag(TextAlign.center)
                    Image(systemName: "text.alignright").tag(TextAlign.right)
                }
                .pickerStyle(.segmented)
            }
            ColorRow(selected: layer.color) { color in
                session.updateSelectedText("Color") { $0.color = color }
            }
            if !layer.isSticker {
                HStack(spacing: 8) {
                    toggle("Label", on: layer.background) { $0.background.toggle() }
                    toggle("Outline", on: layer.outline) { $0.outline.toggle() }
                    toggle("Glow", on: layer.glow) { $0.glow.toggle() }
                    toggle("CAPS", on: layer.uppercase) { $0.uppercase.toggle() }
                }
                if layer.background {
                    Text("Label color")
                        .font(.caption)
                        .foregroundStyle(Darkroom.stone)
                    ColorRow(selected: layer.backgroundColor) { color in
                        session.updateSelectedText("Label color") { $0.backgroundColor = color }
                    }
                }
                if layer.outline {
                    Text("Outline color")
                        .font(.caption)
                        .foregroundStyle(Darkroom.stone)
                    ColorRow(selected: layer.outlineColor) { color in
                        session.updateSelectedText("Outline color") { $0.outlineColor = color }
                    }
                }
            }
            SliderList(session: session, specs: specs(layer))
        }
    }

    private func specs(_ layer: TextLayer) -> [SliderSpec] {
        let path = \EditDocument.texts[index]
        var specs = [
            SliderSpec(id: "text.size", title: "Size", range: 0.02...0.4, defaultValue: layer.isSticker ? 0.1 : 0.07, style: .percent, keyPath: path.appending(path: \.size)),
            SliderSpec(id: "text.rotation", title: "Rotation", range: -180...180, style: .degrees, keyPath: path.appending(path: \.rotation)),
            SliderSpec(id: "text.opacity", title: "Opacity", range: 0...100, defaultValue: 100, style: .integer, keyPath: path.appending(path: \.opacity)),
        ]
        if !layer.isSticker {
            specs.append(SliderSpec(id: "text.spacing", title: "Letter spacing", range: 0...100, style: .integer, keyPath: path.appending(path: \.spacing)))
            specs.append(SliderSpec(id: "text.lineSpacing", title: "Line spacing", range: 0...100, style: .integer, keyPath: path.appending(path: \.lineSpacing)))
            if layer.background {
                specs.append(SliderSpec(id: "text.backgroundOpacity", title: "Label opacity", range: 10...100, defaultValue: 90, style: .integer, keyPath: path.appending(path: \.backgroundOpacity)))
            }
        }
        return specs
    }

    private func toggle(_ title: String, on: Bool, _ change: @escaping (inout TextLayer) -> Void) -> some View {
        Button {
            session.updateSelectedText(title) { change(&$0) }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .drChip(on, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    private func previewFont(_ font: TextFont) -> Font {
        switch font {
        case .sans: return .system(size: 14, weight: .semibold)
        case .serif: return .system(size: 14, weight: .semibold, design: .serif)
        case .rounded: return .system(size: 14, weight: .semibold, design: .rounded)
        case .mono: return .system(size: 14, weight: .semibold, design: .monospaced)
        default: return .custom(font.fontName ?? "", size: 14)
        }
    }
}

/// Text layers on the canvas: tap to select, drag to move.
struct TextCanvasOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession
    @State private var dragStart: SIMD2<Double>?

    var body: some View {
        let frame = renderer.imageFrame
        let content = session.contentRectInOutput
        // The photo's area on screen (inside any frame).
        let photo = CGRect(
            x: frame.minX + content.minX * frame.width,
            y: frame.minY + (1 - content.maxY) * frame.height,
            width: content.width * frame.width,
            height: content.height * frame.height
        )
        ZStack(alignment: .topLeading) {
            if photo.width > 0 {
                ForEach(session.document.texts) { layer in
                    let selected = layer.id == session.selectedTextID
                    let center = CGPoint(x: photo.minX + CGFloat(layer.position.x) * photo.width, y: photo.minY + CGFloat(1 - layer.position.y) * photo.height)
                    let height = CGFloat(layer.size) * photo.width * 1.3
                    let width = layer.isSticker ? height : max(height, height * CGFloat(max(layer.text.count, 1)) * 0.55)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(selected ? Darkroom.safelight : Color.white.opacity(0.0001), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                        .rotationEffect(.degrees(-layer.rotation))
                        .position(center)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragStart == nil {
                                        session.selectedTextID = layer.id
                                        dragStart = layer.position
                                        session.beginChange()
                                    }
                                    guard let start = dragStart, let index = session.selectedTextIndex else { return }
                                    let dx = Double(value.translation.width / photo.width)
                                    let dy = Double(-value.translation.height / photo.height)
                                    session.document.texts[index].position = SIMD2(min(max(start.x + dx, 0), 1), min(max(start.y + dy, 0), 1))
                                }
                                .onEnded { _ in
                                    dragStart = nil
                                    session.endChange(label: "Move layer")
                                }
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
