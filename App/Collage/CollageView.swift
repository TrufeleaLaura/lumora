import LumoraCore
import PhotosUI
import SwiftUI

/// Collage, story and moodboard maker: choose a layout, fill the cells, pan/zoom each photo.
struct CollageView: View {
    @StateObject private var model: CollageModel
    let projects: [ProjectMetadata]
    let thumbnail: (ProjectMetadata) -> UIImage?
    let onClose: () -> Void

    @State private var pickingCell: Int?
    @State private var pickerItem: PhotosPickerItem?
    @State private var zoomStart: Double?
    @State private var dragStart: SIMD2<Double>?

    init(store: ProjectStore, projects: [ProjectMetadata], thumbnail: @escaping (ProjectMetadata) -> UIImage?, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CollageModel(store: store))
        self.projects = projects
        self.thumbnail = thumbnail
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
                .padding(16)
                .frame(maxHeight: .infinity)
            controls
        }
        .background(AuraBackground(intensity: 0.55))
        .overlay(alignment: .top) {
            if let toast = model.toast {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Aura.gradient)
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Aura.textPrimary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .auraGlass(Capsule(), tint: 0.5)
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Aura.bouncy, value: model.toast)
        .sheet(isPresented: Binding(get: { pickingCell != nil }, set: { if !$0 { pickingCell = nil } })) {
            photoPicker
                .presentationDetents([.medium, .large])
                .presentationBackground(Aura.plum)
                .presentationCornerRadius(30)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item, let index = pickingCell else { return }
            pickingCell = nil
            Task {
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.use(photoData: data, in: index)
                }
            }
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack {
            AuraIconButton(symbol: "xmark", action: onClose)
                .accessibilityLabel("Close")
            Spacer()
            Text("Collage")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Aura.textPrimary)
            Spacer()
            Button {
                model.save()
            } label: {
                ZStack {
                    Text("Save").opacity(model.isExporting ? 0 : 1)
                    if model.isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Aura.ink)
                    }
                }
            }
            .buttonStyle(AuraPrimaryButtonStyle(compact: true))
            .disabled(model.isExporting || model.cells.allSatisfy { $0.image == nil })
            .opacity(model.cells.allSatisfy { $0.image == nil } ? 0.45 : 1)
            .accessibilityLabel("Save")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let size = model.settings.aspect.pixelSize
            let pixelWidth = Double(size.width), pixelHeight = Double(size.height)
            let scale = min(geometry.size.width / CGFloat(pixelWidth), geometry.size.height / CGFloat(pixelHeight))
            let viewWidth = CGFloat(pixelWidth) * scale, viewHeight = CGFloat(pixelHeight) * scale
            let background = model.settings.background
            let radius = CGFloat(model.settings.cornerRadius(width: pixelWidth, height: pixelHeight)) * scale
            ZStack(alignment: .topLeading) {
                Color(red: background.red, green: background.green, blue: background.blue)
                ForEach(Array(model.settings.cellRects(width: pixelWidth, height: pixelHeight).enumerated()), id: \.offset) { index, cell in
                    let rect = CGRect(
                        x: CGFloat(cell.x) * scale,
                        y: viewHeight - CGFloat(cell.y + cell.height) * scale,
                        width: CGFloat(cell.width) * scale,
                        height: CGFloat(cell.height) * scale
                    )
                    cellView(index, cell: cell, rect: rect, scale: scale, radius: radius)
                }
            }
            .frame(width: viewWidth, height: viewHeight)
            .clipShape(Rectangle())
            .shadow(color: .black.opacity(0.4), radius: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func cellView(_ index: Int, cell: CGRectValue, rect: CGRect, scale: CGFloat, radius: CGFloat) -> some View {
        let item = index < model.cells.count ? model.cells[index] : CollageModel.Cell()
        let selected = model.selected == index
        ZStack {
            if let preview = item.preview {
                let imageRect = CollageMath.imageRect(imageWidth: Double(preview.size.width), imageHeight: Double(preview.size.height), cell: cell, crop: item.crop)
                // Position relative to the cell (view coordinates, y down).
                let x = CGFloat(imageRect.x - cell.x) * scale
                let y = CGFloat((cell.y + cell.height) - (imageRect.y + imageRect.height)) * scale
                Image(uiImage: preview)
                    .resizable()
                    .frame(width: CGFloat(imageRect.width) * scale, height: CGFloat(imageRect.height) * scale)
                    .position(x: x + CGFloat(imageRect.width) * scale / 2, y: y + CGFloat(imageRect.height) * scale / 2)
            } else {
                Color.black.opacity(0.08)
                Image(systemName: model.loadingCell == index ? "hourglass" : "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(selected ? AnyShapeStyle(Aura.diagonal) : AnyShapeStyle(Color.clear), lineWidth: 2.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if item.image == nil {
                pickingCell = index
            } else {
                model.selected = selected ? nil : index
            }
        }
        .gesture(cellGestures(index, rect: rect), including: selected ? .all : .none)
        .position(x: rect.midX, y: rect.midY)
    }

    private func cellGestures(_ index: Int, rect: CGRect) -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                guard index < model.cells.count else { return }
                if dragStart == nil { dragStart = model.cells[index].crop.offset }
                guard let start = dragStart else { return }
                model.cells[index].crop.offset = SIMD2(
                    start.x + Double(value.translation.width / rect.width),
                    start.y - Double(value.translation.height / rect.height)
                )
            }
            .onEnded { _ in dragStart = nil }
        let zoom = MagnificationGesture()
            .onChanged { value in
                guard index < model.cells.count else { return }
                if zoomStart == nil { zoomStart = model.cells[index].crop.zoom }
                model.cells[index].crop.zoom = min(max((zoomStart ?? 1) * Double(value), 1), 5)
            }
            .onEnded { _ in zoomStart = nil }
        return drag.simultaneously(with: zoom)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CollageLayout.allCases) { layout in
                        Button {
                            model.settings.layout = layout
                        } label: {
                            LayoutIcon(layout: layout, selected: model.settings.layout == layout)
                        }
                        .buttonStyle(AuraPressStyle())
                        .accessibilityLabel(layout.title)
                    }
                }
            }
            Picker("Shape", selection: $model.settings.aspect) {
                ForEach(CollageAspect.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .pickerStyle(.segmented)
            if let index = model.selected, index < model.cells.count, model.cells[index].image != nil {
                HStack {
                    Text("Drag and pinch to frame the photo")
                        .font(.caption)
                        .foregroundStyle(Aura.textSecondary)
                    Spacer()
                    Button("Replace") { pickingCell = index }
                        .font(.footnote.weight(.semibold))
                    Button(role: .destructive) {
                        model.clearCell(index)
                        model.selected = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .font(.footnote)
                }
            } else {
                ToolSlider(title: "Spacing", value: $model.settings.spacing, range: 0...100, format: { "\(Int($0.rounded()))" })
                ToolSlider(title: "Margin", value: $model.settings.margin, range: 0...100, format: { "\(Int($0.rounded()))" })
                ToolSlider(title: "Corners", value: $model.settings.cornerRadius, range: 0...100, format: { "\(Int($0.rounded()))" })
                ColorRow(selected: model.settings.background) { model.settings.background = $0 }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
            ZStack {
                shape.fill(Aura.surface.opacity(0.92))
                shape.stroke(Aura.rim, lineWidth: 0.8)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.15)))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Picking photos

    private var photoPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .auraChip(true, shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if !projects.isEmpty {
                        Text("Your edits")
                            .font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], spacing: 4) {
                            ForEach(projects) { project in
                                ProjectTile(image: thumbnail(project))
                                    .onTapGesture {
                                        if let index = pickingCell {
                                            model.use(project, in: index)
                                        }
                                        pickingCell = nil
                                    }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pickingCell = nil }
                }
            }
        }
    }
}

/// A small drawing of a layout's cells.
private struct LayoutIcon: View {
    let layout: CollageLayout
    let selected: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.cells.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? Color.black.opacity(0.75) : Color.white.opacity(0.7))
                    .frame(width: CGFloat(cell.width) * 34 - 2, height: CGFloat(cell.height) * 42 - 2)
                    .position(x: CGFloat(cell.x + cell.width / 2) * 34, y: CGFloat(1 - cell.y - cell.height / 2) * 42)
            }
        }
        .frame(width: 34, height: 42)
        .padding(7)
        .auraChipBackground(selected, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
