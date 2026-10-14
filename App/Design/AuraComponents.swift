import SwiftUI

// MARK: - Surfaces

extension View {
    /// Frosted glass with a faint plum tint and a luminous gradient rim.
    func auraGlass<S: InsettableShape>(_ shape: S, tint: Double = 0.55, rim: Double = 1) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Aura.surface.opacity(tint))
            }
        }
        .overlay {
            shape.strokeBorder(Aura.rim, lineWidth: 0.8).opacity(rim)
        }
    }

    func auraGlass(cornerRadius: CGFloat, tint: Double = 0.55) -> some View {
        auraGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }

    /// A chip: soft glass when idle, a glowing aura gradient when selected.
    func auraChip<S: InsettableShape>(_ selected: Bool, shape: S) -> some View {
        foregroundStyle(selected ? Aura.ink : Aura.textPrimary)
            .background {
                if selected {
                    shape.fill(Aura.gradient)
                        .shadow(color: Aura.lavender.opacity(0.55), radius: 10)
                } else {
                    shape.fill(Aura.surfaceRaised.opacity(0.75))
                        .overlay(shape.strokeBorder(Aura.hairline, lineWidth: 0.7))
                }
            }
            .animation(Aura.spring, value: selected)
    }

    /// Background-only version of `auraChip` (content keeps its own colors).
    func auraChipBackground<S: InsettableShape>(_ selected: Bool, shape: S) -> some View {
        background {
            if selected {
                shape.fill(Aura.gradient)
                    .shadow(color: Aura.lavender.opacity(0.5), radius: 8)
            } else {
                shape.fill(Aura.surfaceRaised.opacity(0.75))
                    .overlay(shape.strokeBorder(Aura.hairline, lineWidth: 0.7))
            }
        }
    }

    /// A raised tile for grids of options.
    func auraTile<S: InsettableShape>(_ shape: S) -> some View {
        background {
            shape.fill(
                LinearGradient(colors: [Aura.surfaceRaised, Aura.surfaceRaised.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(shape.strokeBorder(Aura.hairline, lineWidth: 0.7))
        }
    }

    /// Form and list screens on a calm aura background.
    func auraFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(AuraBackground(intensity: 0.5))
    }

    /// Glassy row background for forms and lists.
    func auraRow() -> some View {
        listRowBackground(Aura.surface.opacity(0.78))
    }

    /// Fills text or symbols with the aura gradient.
    func auraGradientForeground() -> some View {
        foregroundStyle(Aura.gradient)
    }
}

// MARK: - Buttons

/// Gentle squash on press, with a spring back.
struct AuraPressStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(Aura.bouncy, value: configuration.isPressed)
    }
}

/// The main call to action: a glowing aura-gradient capsule.
struct AuraPrimaryButtonStyle: ButtonStyle {
    /// Smaller version for bars.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.bold) : .headline)
            .foregroundStyle(Aura.ink)
            .padding(.horizontal, compact ? 18 : 22)
            .padding(.vertical, compact ? 9 : 14)
            .background(Capsule().fill(Aura.gradient))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: Aura.rose.opacity(configuration.isPressed ? 0.25 : 0.45), radius: configuration.isPressed ? 6 : (compact ? 10 : 16), y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Aura.bouncy, value: configuration.isPressed)
    }
}

/// Round glass icon button for bars.
struct AuraIconButton: View {
    let symbol: String
    var size: CGFloat = 38
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Aura.gradient) : AnyShapeStyle(Aura.textPrimary))
                .frame(width: size, height: size)
                .auraGlass(Circle(), tint: 0.4, rim: active ? 1 : 0.5)
        }
        .buttonStyle(AuraPressStyle(scale: 0.9))
    }
}

// MARK: - Aura background

/// Plum night with slowly drifting lavender, rose and peach light.
struct AuraBackground: View {
    var intensity: Double = 1
    /// Freezes the drift (e.g. while another screen covers this one).
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation(minimumInterval: 1 / 30, paused: isStill)) { timeline in
                let t = isStill ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Aura.plum
                    blob(Aura.lavender, size: size, scale: 0.95, t: t, speed: 0.07, phase: 0, anchor: CGPoint(x: 0.15, y: 0.18))
                    blob(Aura.rose, size: size, scale: 0.8, t: t, speed: 0.05, phase: 2.1, anchor: CGPoint(x: 0.9, y: 0.35))
                    blob(Aura.peach, size: size, scale: 0.75, t: t, speed: 0.06, phase: 4.2, anchor: CGPoint(x: 0.35, y: 0.95))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var isStill: Bool { paused || reduceMotion || Aura.isUITesting }

    /// A soft light: a radial gradient (cheap to move every frame, unlike a large blur).
    private func blob(_ color: Color, size: CGSize, scale: CGFloat, t: Double, speed: Double, phase: Double, anchor: CGPoint) -> some View {
        let diameter = max(size.width, size.height) * 0.95 * scale
        let dx = CGFloat(sin(t * speed * 2 * .pi + phase)) * size.width * 0.12
        let dy = CGFloat(cos(t * speed * 1.6 * .pi + phase * 0.7)) * size.height * 0.08
        let falloff = Gradient(stops: [
            .init(color: color.opacity(0.85), location: 0),
            .init(color: color.opacity(0.35), location: 0.4),
            .init(color: color.opacity(0), location: 1),
        ])
        return Circle()
            .fill(RadialGradient(gradient: falloff, center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .opacity(0.42 * intensity)
            .position(x: anchor.x * size.width + dx, y: anchor.y * size.height + dy)
    }
}

// MARK: - Loader

/// A spinning aura ring, with an optional caption.
struct AuraLoader: View {
    var caption: String?
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(
                    AngularGradient(colors: Aura.gradientColors + [Aura.lavender.opacity(0)], center: .center),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .shadow(color: Aura.lavender.opacity(0.6), radius: 6)
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinning = true }
                }
            if let caption {
                Text(caption)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Aura.textSecondary)
            }
        }
    }
}

// MARK: - Sparkle burst

/// A small burst of sparkles, played every time `trigger` changes (applying a look, a preset…).
struct SparkleBurst: View {
    let trigger: Int
    @State private var particles: [SparkleParticle.Model] = []

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                SparkleParticle(model: particle)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        let colors = Aura.gradientColors + [Color.white]
        let fresh = (0..<12).map { index in
            SparkleParticle.Model(
                angle: CGFloat(index) / 12 * 2 * .pi + CGFloat.random(in: -0.2...0.2),
                distance: CGFloat.random(in: 60...130),
                size: CGFloat.random(in: 10...20),
                color: colors[index % colors.count]
            )
        }
        particles = fresh
        let ids = Set(fresh.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            particles.removeAll { ids.contains($0.id) }
        }
    }
}

/// One sparkle: appears at the center, then flies out, shrinks and fades.
struct SparkleParticle: View {
    struct Model: Identifiable {
        let id = UUID()
        let angle: CGFloat
        let distance: CGFloat
        let size: CGFloat
        let color: Color
    }

    let model: Model
    @State private var flown = false

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: model.size, weight: .bold))
            .foregroundStyle(model.color)
            .shadow(color: model.color.opacity(0.8), radius: 4)
            .offset(
                x: flown ? cos(model.angle) * model.distance : 0,
                y: flown ? sin(model.angle) * model.distance : 0
            )
            .scaleEffect(flown ? 0.4 : 1.2)
            .rotationEffect(.degrees(flown ? 90 : 0))
            .opacity(flown ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.9)) { flown = true }
            }
    }
}

// MARK: - Segmented control

/// Two to four options with a gliding aura-gradient highlight.
struct AuraSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Aura.spring) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Aura.ink : Aura.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Aura.gradient)
                                    .shadow(color: Aura.lavender.opacity(0.45), radius: 8)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .auraGlass(Capsule(), tint: 0.6, rim: 0.6)
    }
}

// MARK: - Chip bar

/// A scrolling row of labelled chips with a gliding highlight (sections of a tool).
struct AuraChipBar<Item: Hashable & Identifiable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var symbol: ((Item) -> String)?
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        let selected = item == selection
                        Button {
                            withAnimation(Aura.spring) {
                                selection = item
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if let symbol {
                                    Image(systemName: symbol(item))
                                        .font(.caption.weight(.semibold))
                                }
                                Text(title(item))
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? Aura.ink : Aura.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(Aura.gradient)
                                        .shadow(color: Aura.lavender.opacity(0.5), radius: 9)
                                        .matchedGeometryEffect(id: "chip", in: namespace)
                                } else {
                                    Capsule()
                                        .fill(Aura.surfaceRaised.opacity(0.7))
                                        .overlay(Capsule().strokeBorder(Aura.hairline, lineWidth: 0.7))
                                }
                            }
                        }
                        .buttonStyle(AuraPressStyle(scale: 0.94))
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
            }
        }
    }
}
