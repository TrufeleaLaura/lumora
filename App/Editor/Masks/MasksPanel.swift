import LumoraCore
import SwiftUI

/// Local adjustments: a strip of masks, then the selected mask's parts or its adjustments.
struct MasksPanel: View {
    @ObservedObject var session: EditorSession
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var showsPresets = true
    @State private var presetCategory: MaskPreset.Category = .portrait

    private static let creatable: [MaskKind] = [.subject, .sky, .background, .people, .object, .brush, .linear, .radial, .color, .luminance, .point]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preparing = session.preparingMask {
                ProgressView(preparing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.document.masks.isEmpty || showsPresets && session.selectedMaskID == nil {
                HStack {
                    Picker("Start", selection: $showsPresets) {
                        Text("One-tap presets").tag(true)
                        Text("Make a mask").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if !session.document.masks.isEmpty {
                        Button("Masks") { showsPresets = false; session.selectMask(session.document.masks.last?.id) }
                            .font(.footnote)
                    }
                }
                ScrollView {
                    if showsPresets {
                        presetsGrid
                    } else {
                        createGrid
                    }
                }
            } else {
                maskStrip
                if let maskIndex = session.selectedMaskIndex {
                    maskHeader(maskIndex)
                    ScrollView {
                        Group {
                            if session.maskPanel == .adjust {
                                SliderList(session: session, specs: MaskCatalog.sliders(maskIndex: maskIndex))
                            } else {
                                MaskComponentEditor(session: session, maskIndex: maskIndex)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    Text("Select a mask above, or add a new one with +")
                        .font(.footnote)
                        .foregroundStyle(Aura.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Rename mask", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") { session.renameSelectedMask(newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Creating

    private var createGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(Self.creatable) { kind in
                Button {
                    session.addMask(kind)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 18))
                        Text(kind.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .auraTile(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(AuraPressStyle())
            }
        }
    }

    private var presetsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MaskPreset.Category.allCases) { category in
                        Button {
                            presetCategory = category
                        } label: {
                            Label(category.title, systemImage: category.symbol)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .auraChip(presetCategory == category, shape: Capsule())
                        }
                        .buttonStyle(AuraPressStyle())
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(MaskPresetLibrary.presets(in: presetCategory)) { preset in
                    Button {
                        session.applyMaskPreset(preset)
                        showsPresets = false
                    } label: {
                        Text(preset.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, 4)
                            .auraTile(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(AuraPressStyle())
                }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                session.selectMask(nil)
                showsPresets = true
            } label: {
                Label("One-tap presets", systemImage: "wand.and.stars")
            }
            Divider()
            ForEach(Self.creatable) { kind in
                Button {
                    session.addMask(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .auraChip(true, shape: Circle())
        }
        .accessibilityLabel("New mask")
    }

    // MARK: - Masks

    private var maskStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.document.masks) { mask in
                        let selected = mask.id == session.selectedMaskID
                        Button {
                            session.selectMask(selected ? nil : mask.id)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mask.components.first?.kind.symbol ?? "circle.dashed")
                                Text(mask.name)
                                    .lineLimit(1)
                            }
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .auraChip(selected, shape: Capsule())
                            .opacity(mask.isVisible ? 1 : 0.5)
                        }
                        .buttonStyle(AuraPressStyle())
                    }
                }
            }
            addMenu
        }
    }

    private func maskHeader(_ maskIndex: Int) -> some View {
        let mask = session.document.masks[maskIndex]
        return HStack(spacing: 14) {
            Picker("Mode", selection: $session.maskPanel) {
                ForEach(MaskPanelMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 170)

            Spacer()

            Button {
                session.showsMaskOverlay.toggle()
            } label: {
                Image(systemName: session.showsMaskOverlay ? "circle.lefthalf.filled" : "circle")
            }
            .disabled(session.maskPanel != .mask)
            .accessibilityLabel(session.showsMaskOverlay ? "Hide mask overlay" : "Show mask overlay")

            Button {
                session.toggleSelectedMaskVisibility()
            } label: {
                Image(systemName: mask.isVisible ? "eye" : "eye.slash")
            }
            .accessibilityLabel(mask.isVisible ? "Turn mask off" : "Turn mask on")

            Menu {
                Button {
                    newName = mask.name
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    session.duplicateSelectedMask()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    session.resetSelectedMaskAdjustments()
                } label: {
                    Label("Reset adjustments", systemImage: "arrow.counterclockwise")
                }
                Divider()
                Button(role: .destructive) {
                    session.deleteSelectedMask()
                } label: {
                    Label("Delete mask", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .font(.system(size: 17))
    }
}

/// Parts of the selected mask and the controls of the selected part.
struct MaskComponentEditor: View {
    @ObservedObject var session: EditorSession
    let maskIndex: Int

    private var mask: Mask { session.document.masks[maskIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            componentStrip
            if let component = session.selectedComponent, let path = session.componentPath {
                HStack {
                    Toggle("Invert", isOn: Binding(
                        get: { component.inverted },
                        set: { value in session.updateComponent(value ? "Invert" : "Don't invert") { $0.inverted = value } }
                    ))
                    .tint(Aura.lavender)
                    .fixedSize()
                    Spacer()
                    Button(role: .destructive) {
                        session.deleteSelectedComponent()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.footnote)
                    }
                }
                controls(component, path: path)
            }
        }
    }

    private var componentStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(mask.components) { component in
                        let selected = component.id == session.selectedComponentID
                        Button {
                            session.selectedComponentID = component.id
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: component.mode.symbol)
                                    .font(.caption2)
                                Image(systemName: component.kind.symbol)
                                Text(component.kind.title)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .auraChip(selected, shape: Capsule())
                        }
                        .buttonStyle(AuraPressStyle())
                    }
                }
            }
            Menu {
                ForEach(MaskMode.allCases) { mode in
                    Menu {
                        ForEach(MaskKind.allCases.filter { $0 != .background }) { kind in
                            Button {
                                session.addComponent(kind, mode: mode)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            } label: {
                Label("Add", systemImage: "plus.circle")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    // MARK: - Per-kind controls

    @ViewBuilder
    private func controls(_ component: MaskComponent, path: WritableKeyPath<EditDocument, MaskComponent>) -> some View {
        switch component.kind {
        case .subject, .background:
            hint("Finds the main subject automatically. Use Invert for the background.")
        case .sky:
            hint("Finds the sky automatically. Subtract a brush to fix any spots.")
        case .people:
            PeopleControls(session: session, component: component)
        case .object:
            hint("Tap objects on the photo to select them.")
            clearButton(component.points.isEmpty)
        case .brush:
            BrushControls(session: session, component: component)
        case .linear:
            hint("Drag the handles on the photo: full effect at the solid line, none past the dashed line.")
        case .radial:
            hint("Drag the center or the edge handles on the photo.")
            SliderList(session: session, specs: [
                SliderSpec(id: "mask.radial.feather", title: "Feather", range: 0...100, defaultValue: 50, style: .integer, keyPath: path.appending(path: \.feather)),
                SliderSpec(id: "mask.radial.angle", title: "Angle", range: -90...90, defaultValue: 0, style: .degrees, keyPath: path.appending(path: \.angle)),
            ])
        case .color:
            hint(component.colors.isEmpty ? "Tap the photo to pick a color (up to 5)." : "Picked \(component.colors.count) of 5 colors. Tap to add more.")
            SliderList(session: session, specs: [
                SliderSpec(id: "mask.color.refine", title: "Range", range: 0...100, defaultValue: 50, style: .integer, keyPath: path.appending(path: \.refine)),
            ])
            clearButton(component.colors.isEmpty)
        case .luminance:
            SliderList(session: session, specs: [
                SliderSpec(id: "mask.luminance.low", title: "From", range: 0...1, defaultValue: 0.65, style: .percent, keyPath: path.appending(path: \.range.x)),
                SliderSpec(id: "mask.luminance.high", title: "To", range: 0...1, defaultValue: 1, style: .percent, keyPath: path.appending(path: \.range.y)),
                SliderSpec(id: "mask.luminance.refine", title: "Smoothness", range: 0...100, defaultValue: 30, style: .integer, keyPath: path.appending(path: \.refine)),
            ])
        case .point:
            hint("Tap the photo to move the point. It spreads to similar colors nearby.")
            SliderList(session: session, specs: [
                SliderSpec(id: "mask.point.size", title: "Size", range: 0.02...0.6, defaultValue: 0.15, style: .percent, keyPath: path.appending(path: \.radius.x)),
                SliderSpec(id: "mask.point.refine", title: "Color range", range: 0...100, defaultValue: 50, style: .integer, keyPath: path.appending(path: \.refine)),
            ])
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Aura.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func clearButton(_ disabled: Bool) -> some View {
        Button {
            session.clearSelectedComponent()
        } label: {
            Label("Clear", systemImage: "xmark.circle")
                .font(.footnote)
        }
        .disabled(disabled)
    }
}

/// People: everyone or one person, and which parts.
private struct PeopleControls: View {
    @ObservedObject var session: EditorSession
    let component: MaskComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Everyone", selected: component.person == nil) {
                        session.updateComponent("Everyone") { $0.person = nil }
                    }
                    if let faces = session.faces {
                        ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                            let center = SIMD2(face.bounds.x + face.bounds.width / 2, face.bounds.y + face.bounds.height / 2)
                            chip("Person \(index + 1)", selected: isChosen(center)) {
                                session.updateComponent("Person \(index + 1)") { $0.person = center }
                            }
                        }
                    }
                }
            }
            Text("Or tap a person on the photo.")
                .font(.caption)
                .foregroundStyle(Aura.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(PersonPart.allCases) { part in
                    let on = component.parts.contains(part)
                    Button {
                        session.togglePart(part)
                    } label: {
                        Text(part.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .auraChip(on, shape: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(AuraPressStyle())
                }
            }
        }
    }

    private func isChosen(_ center: SIMD2<Double>) -> Bool {
        guard let person = component.person else { return false }
        let d: SIMD2<Double> = person - center
        return (d.x * d.x + d.y * d.y).squareRoot() < 0.02
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .auraChip(selected, shape: Capsule())
        }
        .buttonStyle(AuraPressStyle())
    }
}

/// Brush: paint/erase, size, feather, flow, auto edge.
private struct BrushControls: View {
    @ObservedObject var session: EditorSession
    let component: MaskComponent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Brush", selection: $session.brush.erase) {
                    Text("Paint").tag(false)
                    Text("Erase").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                Spacer()
                Toggle(isOn: $session.brushPaints) {
                    Image(systemName: session.brushPaints ? "paintbrush.pointed" : "hand.draw")
                }
                .toggleStyle(.button)
                .accessibilityLabel(session.brushPaints ? "Painting (one finger)" : "Moving (one finger)")
                Button {
                    session.clearSelectedComponent()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(component.strokes.isEmpty)
                .accessibilityLabel("Clear strokes")
            }
            ToolSlider(title: "Size", value: $session.brush.size, range: 0.005...0.25, format: { "\(Int(($0 * 100).rounded()))%" })
            ToolSlider(title: "Feather", value: $session.brush.feather, range: 0...100, format: { "\(Int($0.rounded()))" })
            ToolSlider(title: "Flow", value: $session.brush.flow, range: 5...100, format: { "\(Int($0.rounded()))" })
            Toggle("Auto edge", isOn: Binding(
                get: { component.autoEdge },
                set: { value in session.updateComponent(value ? "Auto edge on" : "Auto edge off") { $0.autoEdge = value } }
            ))
            .tint(Aura.lavender)
            Text(session.brushPaints ? "One finger paints, two fingers move and zoom." : "Painting is paused: one finger moves the photo.")
                .font(.caption)
                .foregroundStyle(Aura.textSecondary)
        }
    }
}

/// A slider for a value that isn't part of the edit document (tool options).
struct ToolSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Aura.textSecondary)
                Spacer()
                Text(format(value))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Aura.gradient)
            }
            LumoraSlider(value: $value, range: range, origin: range.lowerBound)
        }
    }
}
