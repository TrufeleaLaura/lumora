import LumoraCore
import SwiftUI

/// Body reshaping: pick all people or one person, then Shape / Length / Upper body.
struct BodyPanel: View {
    @ObservedObject var session: EditorSession
    @State private var section: BodyCatalog.Section = .shape

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bodies = session.bodies {
                if bodies.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 30))
                            .foregroundStyle(Darkroom.stone)
                        Text("No person found. Body tools work best on full or half-body photos.")
                            .font(Typeface.jost(15))
                            .foregroundStyle(Darkroom.stone)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    header(count: bodies.count)
                    ScrollView {
                        if section == .muscles {
                            Picker("Abs style", selection: Binding(
                                get: { session.document[keyPath: session.bodyTarget].absStyle },
                                set: { style in
                                    let target = session.bodyTarget
                                    session.perform("Abs \(style.title)") { $0[keyPath: target].absStyle = style }
                                }
                            )) {
                                ForEach(AbsStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.bottom, 6)
                        }
                        SliderList(session: session, specs: BodyCatalog.sliders(section, target: session.bodyTarget))
                            .padding(.bottom, 8)
                    }
                }
            } else {
                ProgressView("Finding people…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if count > 1 {
                HScroll {
                    HStack(spacing: 6) {
                        chip("Everyone", selected: session.selectedBodyIndex == nil) { session.selectBody(nil) }
                        ForEach(0..<count, id: \.self) { index in
                            chip("Person \(index + 1)", selected: session.selectedBodyIndex == index) { session.selectBody(index) }
                        }
                    }
                }
            }
            HStack(alignment: .center, spacing: 8) {
                SectionTabs(items: BodyCatalog.Section.allCases, selection: $section, title: { $0.title })
                    .clipped()
                Button {
                    session.resetBody()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Darkroom.stone)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Reset body")
            }
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

/// Numbered markers at each person's hips when there are several people; tap to edit one.
struct BodyMarkersOverlay: View {
    @ObservedObject var renderer: CanvasRenderer
    @ObservedObject var session: EditorSession

    var body: some View {
        let frame = renderer.imageFrame
        ZStack(alignment: .topLeading) {
            if let bodies = session.bodies, bodies.count > 1 {
                ForEach(Array(bodies.enumerated()), id: \.offset) { index, shape in
                    if let hips = shape.pose.hipCenter {
                        let selected = session.selectedBodyIndex == index
                        Text("\(index + 1)")
                            .font(Typeface.jost(12, weight: 640))
                            .foregroundStyle(Darkroom.ink)
                            .frame(width: 26, height: 26)
                            .background(selected ? Darkroom.safelight : Color.white, in: Circle())
                            .shadow(radius: 2)
                            .onTapGesture { session.selectBody(selected ? nil : index) }
                            .position(
                                x: frame.minX + CGFloat(hips.x) * frame.width,
                                y: frame.minY + CGFloat(1 - hips.y) * frame.height
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
