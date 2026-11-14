import LumoraCore
import SwiftUI

/// Face retouch, makeup and hair. A Portrait tool opens it on a few of its sections
/// (Features shows eyes, teeth, brows, nose and lips, and shape).
struct FacePanel: View {
    @ObservedObject var session: EditorSession
    var sections: [FaceCatalog.Section] = FaceCatalog.Section.allCases
    @State private var chosen: FaceCatalog.Section?
    @State private var lastLook: String?

    private var section: FaceCatalog.Section { chosen ?? sections.first ?? .skin }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let faces = session.faces {
                if faces.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "face.dashed")
                            .font(.system(size: 30))
                            .foregroundStyle(Darkroom.stone)
                        Text("No faces found in this photo.")
                            .font(Typeface.jost(15))
                            .foregroundStyle(Darkroom.stone)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if faces.count > 1 || sections.count > 1 {
                        header(faceCount: faces.count)
                    }
                    ScrollView {
                        if section == .looks {
                            makeupLooks
                                .padding(.bottom, 8)
                        }
                        if let palette = section.palette {
                            paletteRow(palette.colors, keyPath: palette.keyPath)
                            if section == .hair {
                                Text("Ombré color")
                                    .font(Typeface.jost(12))
                                    .foregroundStyle(Darkroom.stone)
                                paletteRow(MakeupPalette.hair, keyPath: \.hairOmbreColor)
                            }
                        }
                        if section == .lipstick {
                            Picker("Finish", selection: Binding(
                                get: { session.document[keyPath: session.faceTarget].makeup.lipFinish },
                                set: { session.setLipFinish($0) }
                            )) {
                                ForEach(LipFinish.allCases) { finish in
                                    Text(finish.title).tag(finish)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, 6)
                        }
                        if section == .hair {
                            Text("Works best on portraits where the hair is clearly visible.")
                                .font(Typeface.jost(11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        SliderList(
                            session: session,
                            specs: FaceCatalog.sliders(section, target: session.faceTarget),
                            gradients: ["face.irisHue": .hueSpectrum]
                        )
                        .padding(.bottom, 8)
                    }
                }
            } else {
                ProgressView("Finding faces…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(faceCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if faceCount > 1 {
                HScroll {
                    HStack(spacing: 6) {
                        chip("All faces", selected: session.selectedFaceIndex == nil) { session.selectFace(nil) }
                        ForEach(0..<faceCount, id: \.self) { index in
                            chip("Face \(index + 1)", selected: session.selectedFaceIndex == index) { session.selectFace(index) }
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 8) {
                if sections.count > 1 {
                    SectionTabs(items: sections, selection: Binding(get: { section }, set: { chosen = $0 }), title: { $0.title })
                } else {
                    Spacer()
                }
                Button {
                    session.resetFace()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Darkroom.stone)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Reset face")
            }
        }
    }

    /// Complete makeup looks as palette cards: the lip, cheek and eye colors each look uses.
    private var makeupLooks: some View {
        HScroll {
            HStack(spacing: 10) {
                ForEach(MakeupLook.all) { look in
                    let colors = Self.swatches(for: look)
                    let selected = lastLook == look.id
                    Button {
                        let target = session.faceTarget
                        session.perform(look.title) { look.apply(to: &$0[keyPath: target]) }
                        lastLook = look.id
                        if look.id != "none" { session.celebrate() }
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: -5) {
                                if colors.isEmpty {
                                    Circle()
                                        .strokeBorder(Darkroom.stone, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .frame(width: 22, height: 22)
                                } else {
                                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                                        Circle()
                                            .fill(color)
                                            .frame(width: 22, height: 22)
                                            .overlay(Circle().stroke(Darkroom.raised, lineWidth: 2))
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(look.title)
                                    .font(Typeface.cormorant(17, weight: 500, italic: true))
                                    .foregroundStyle(Darkroom.cream)
                                    .lineLimit(1)
                                Text(colors.isEmpty ? "BARE" : "LIP \u{00B7} CHEEK \u{00B7} EYE")
                                    .filmCode(8.5)
                                    .foregroundStyle(Darkroom.stone)
                                    .lineLimit(1)
                            }
                        }
                        .padding(12)
                        .frame(width: 104, alignment: .leading)
                        .background(Darkroom.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Darkroom.cream, lineWidth: 1.25)
                            }
                        }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(look.title)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// The colors a look puts on lips, cheeks and eyes (only the ones it uses).
    private static func swatches(for look: MakeupLook) -> [Color] {
        var settings = FaceRetouchSettings()
        look.apply(to: &settings)
        let makeup = settings.makeup
        var colors: [Color] = []
        let swatch = { (c: MakeupColor) in Color(red: c.red, green: c.green, blue: c.blue) }
        if makeup.lipstickAmount > 0 { colors.append(swatch(makeup.lipstickColor)) }
        if makeup.blushAmount > 0 { colors.append(swatch(makeup.blushColor)) }
        if makeup.eyeshadowAmount > 0 { colors.append(swatch(makeup.eyeshadowColor)) }
        return colors
    }

    private func paletteRow(_ colors: [(String, MakeupColor)], keyPath: WritableKeyPath<MakeupSettings, MakeupColor>) -> some View {
        let current = session.document[keyPath: session.faceTarget].makeup[keyPath: keyPath]
        return HScroll {
            HStack(spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, item in
                    let name = item.0
                    let color = item.1
                    Button {
                        session.setMakeupColor(color, name: name, at: keyPath)
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(current == color ? Darkroom.safelight : Color.white.opacity(0.2), lineWidth: current == color ? 2.5 : 1))
                            Text(name)
                                .font(Typeface.jost(10))
                                .foregroundStyle(current == color ? Darkroom.safelight : Darkroom.stone)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(name)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typeface.jost(13, weight: 500))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .drChip(selected, shape: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// Numbered circles over detected faces; tap one to edit it on its own.
struct FaceMarkersOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession

    var body: some View {
        let frame = renderer.imageFrame
        ZStack(alignment: .topLeading) {
            if let faces = session.faces, faces.count > 1 {
                ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                    let rect = CGRect(
                        x: frame.minX + CGFloat(face.bounds.x) * frame.width,
                        y: frame.minY + CGFloat(1 - face.bounds.y - face.bounds.height) * frame.height,
                        width: CGFloat(face.bounds.width) * frame.width,
                        height: CGFloat(face.bounds.height) * frame.height
                    )
                    let selected = session.selectedFaceIndex == index
                    Ellipse()
                        .stroke(selected ? Darkroom.safelight : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, dash: selected ? [] : [5, 4]))
                        .frame(width: rect.width * 1.1, height: rect.height * 1.25)
                        .overlay(alignment: .top) {
                            Text("\(index + 1)")
                                .font(Typeface.jost(11, weight: 640))
                                .foregroundStyle(Darkroom.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(selected ? Darkroom.safelight : Color.white, in: Capsule())
                                .offset(y: -12)
                        }
                        .contentShape(Ellipse())
                        .onTapGesture { session.selectFace(selected ? nil : index) }
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
