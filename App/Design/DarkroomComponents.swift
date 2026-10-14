import SwiftUI
import UIKit

// MARK: - Surfaces

extension View {
    /// A quiet surface: a raised fill with a hairline edge.
    func drSurface<S: InsettableShape>(_ shape: S, opacity: Double = 0.94) -> some View {
        background(shape.fill(Darkroom.raised.opacity(opacity)))
            .overlay(shape.strokeBorder(Darkroom.line, lineWidth: 0.5))
    }

    func drSurface(cornerRadius: CGFloat) -> some View {
        drSurface(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A chip: hairline-outlined when idle; cream with ink type when selected.
    func drChip<S: InsettableShape>(_ selected: Bool, shape: S) -> some View {
        foregroundStyle(selected ? Darkroom.ink : Darkroom.cream)
            .drChipBackground(selected, shape: shape)
    }

    /// Background-only version of `drChip` (content keeps its own colors).
    func drChipBackground<S: InsettableShape>(_ selected: Bool, shape: S) -> some View {
        background {
            if selected {
                shape.fill(Darkroom.cream)
            } else {
                shape.fill(Darkroom.raised.opacity(0.55))
                    .overlay(shape.strokeBorder(Darkroom.line, lineWidth: 0.5))
            }
        }
        .animation(Darkroom.ease, value: selected)
    }

    /// A tile for grids of options.
    func drTile<S: InsettableShape>(_ shape: S) -> some View {
        background {
            shape.fill(Darkroom.raised.opacity(0.7))
                .overlay(shape.strokeBorder(Darkroom.line, lineWidth: 0.5))
        }
    }

    /// Form and list screens on the darkroom background.
    func drFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Darkroom.ink.ignoresSafeArea())
    }

    /// Row background for forms and lists.
    func drRow() -> some View {
        listRowBackground(Darkroom.surface)
    }
}

// MARK: - Buttons

/// A small, quiet press: slightly smaller and dimmer while held.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Darkroom.ease, value: configuration.isPressed)
    }
}

/// The main action: cream paper with ink capitals.
struct PrimaryButtonStyle: ButtonStyle {
    /// Smaller version for bars.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .caps(compact ? 11 : 12, weight: .semibold)
            .foregroundStyle(Darkroom.ink)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 9 : 16)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Darkroom.cream))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Darkroom.ease, value: configuration.isPressed)
    }
}

/// A secondary action: a hairline outline with cream capitals.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .caps(12, weight: .semibold)
            .foregroundStyle(Darkroom.cream)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Darkroom.cream.opacity(0.35), lineWidth: 0.75))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Darkroom.ease, value: configuration.isPressed)
    }
}

/// A plain glyph button for bars.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 40
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(active ? Darkroom.safelight : Darkroom.cream)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

// MARK: - Progress

/// A softly pulsing safelight with a caption: "developing".
struct DevelopingIndicator: View {
    var caption: String?
    @State private var lit = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Darkroom.safelight)
                .frame(width: 6, height: 6)
                .opacity(lit ? 1 : 0.25)
            if let caption {
                Text(caption)
                    .caps(11)
                    .foregroundStyle(Darkroom.cream)
            }
        }
        .onAppear {
            guard !Darkroom.isUITesting else {
                lit = true
                return
            }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) { lit = true }
        }
    }
}

// MARK: - Shutter

/// A brief exposure flash and a shutter-like tap, every time `trigger` changes
/// (a look, preset, mask preset, makeup look or auto enhance lands).
struct ShutterFlash: View {
    let trigger: Int
    @State private var exposure = 0.0

    var body: some View {
        Color.white
            .opacity(exposure)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
                exposure = 0.16
                // Fade on the next turn so the flash is drawn before it decays.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.45)) { exposure = 0 }
                }
            }
    }
}

// MARK: - Segmented control

/// Two to four options in a hairline frame; the selection slides as a cream block.
struct SegmentedTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Darkroom.spring) { selection = option }
                } label: {
                    Text(title(option))
                        .caps(11)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Darkroom.ink : Darkroom.stone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Darkroom.cream)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Darkroom.line, lineWidth: 0.5))
    }
}

// MARK: - Horizontal scroller

/// A horizontal row that scrolls without clipping at its edges (rows read edge to edge).
struct HScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollClipDisabled()
    }
}

// MARK: - Section tabs

/// Text tabs in tracked capitals; a short safelight rule slides under the current one.
struct SectionTabs<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { proxy in
            HScroll {
                HStack(spacing: 22) {
                    ForEach(items) { item in
                        let selected = item == selection
                        Button {
                            withAnimation(Darkroom.spring) {
                                selection = item
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        } label: {
                            Text(title(item))
                                .caps(11)
                                .foregroundStyle(selected ? Darkroom.cream : Darkroom.stone)
                                .padding(.vertical, 8)
                                .overlay(alignment: .bottom) {
                                    if selected {
                                        Rectangle()
                                            .fill(Darkroom.safelight)
                                            .frame(height: 1.5)
                                            .matchedGeometryEffect(id: "tab", in: namespace)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Film details

/// The wordmark: light, widely tracked capitals.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        Text("LUMORA")
            .font(.system(size: size, weight: .light))
            .tracking(size * 0.42)
            .foregroundStyle(Darkroom.cream)
            .accessibilityLabel("Lumora")
    }
}

/// A row of film sprocket holes.
struct Sprockets: View {
    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 13
            let hole = CGSize(width: 7, height: size.height)
            let count = max(Int((size.width + pitch - hole.width) / pitch), 1)
            let used = CGFloat(count - 1) * pitch + hole.width
            var x = (size.width - used) / 2
            for _ in 0..<count {
                let rect = CGRect(origin: CGPoint(x: x, y: 0), size: hole)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(Darkroom.ink))
                x += pitch
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Viewfinder corner marks around a rectangle.
struct ViewfinderFrame: Shape {
    var length: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(length, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

/// A thin full-width hairline.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Darkroom.line)
            .frame(height: 0.5)
    }
}
