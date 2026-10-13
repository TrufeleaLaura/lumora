import LumoraCore
import SwiftUI

/// Face retouch & reshape: pick all faces or one face, then Skin / Eyes / Shape / Nose & lips / Teeth.
struct FacePanel: View {
    @ObservedObject var session: EditorSession
    @State private var section: FaceCatalog.Section = .looks

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let faces = session.faces {
                if faces.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "face.dashed")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("No faces found in this photo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    header(faceCount: faces.count)
                    sectionChips
                    ScrollView {
                        if section == .looks {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                                ForEach(MakeupLook.all) { look in
                                    Button {
                                        let target = session.faceTarget
                                        session.perform(look.title) { look.apply(to: &$0[keyPath: target]) }
                                    } label: {
                                        Text(look.title)
                                            .font(.caption.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        if let palette = section.palette {
                            paletteRow(palette.colors, keyPath: palette.keyPath)
                            if section == .hair {
                                Text("Ombré color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                .font(.caption2)
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
        HStack(spacing: 8) {
            if faceCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All faces", selected: session.selectedFaceIndex == nil) { session.selectFace(nil) }
                        ForEach(0..<faceCount, id: \.self) { index in
                            chip("Face \(index + 1)", selected: session.selectedFaceIndex == index) { session.selectFace(index) }
                        }
                    }
                }
            } else {
                Text("Face")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Button {
                session.autoBeauty()
            } label: {
                Label("Auto", systemImage: "wand.and.stars")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(.black)
                    .background(Theme.gradient, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                session.resetFace()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.footnote)
            }
            .accessibilityLabel("Reset face")
        }
    }

    private var sectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FaceCatalog.Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(section == item ? Color.black : Color.primary)
                            .background(section == item ? Theme.accent : Theme.panelRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func paletteRow(_ colors: [(String, MakeupColor)], keyPath: WritableKeyPath<MakeupSettings, MakeupColor>) -> some View {
        let current = session.document[keyPath: session.faceTarget].makeup[keyPath: keyPath]
        return ScrollView(.horizontal, showsIndicators: false) {
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
                                .overlay(Circle().stroke(current == color ? Theme.accent : Color.white.opacity(0.2), lineWidth: current == color ? 2.5 : 1))
                            Text(name)
                                .font(.system(size: 9))
                                .foregroundStyle(current == color ? Theme.accent : Color.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.black : Color.primary)
                .background(selected ? Theme.accent : Theme.panelRaised, in: Capsule())
        }
        .buttonStyle(.plain)
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
                        .stroke(selected ? Theme.accent : Color.white.opacity(0.7), style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, dash: selected ? [] : [5, 4]))
                        .frame(width: rect.width * 1.1, height: rect.height * 1.25)
                        .overlay(alignment: .top) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(selected ? Theme.accent : Color.white, in: Capsule())
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
