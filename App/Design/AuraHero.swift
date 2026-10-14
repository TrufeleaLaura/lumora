import SwiftUI

/// The "Lumora" wordmark: rounded, aura-filled, with a twinkling spark.
struct LumoraWordmark: View {
    var size: CGFloat = 42
    @State private var twinkle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Lumora")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(Aura.gradient)
            .shadow(color: Aura.lavender.opacity(0.45), radius: 18)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Aura.peach)
                    .shadow(color: Aura.peach.opacity(0.9), radius: 6)
                    .scaleEffect(twinkle ? 1 : 0.55)
                    .opacity(twinkle ? 1 : 0.45)
                    .rotationEffect(.degrees(twinkle ? 20 : -10))
                    .offset(x: size * 0.36, y: -size * 0.05)
            }
            .onAppear {
                guard !reduceMotion, !Aura.isUITesting else {
                    twinkle = true
                    return
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { twinkle = true }
            }
            .accessibilityLabel("Lumora")
    }
}

/// A large card filled with living aura light, a slow shimmer and a glass "plus" orb.
struct AuraHeroCard: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isStill: Bool { paused || reduceMotion || Aura.isUITesting }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isStill)) { timeline in
            let t = CGFloat(isStill ? 1.5 : timeline.date.timeIntervalSinceReferenceDate)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Aura.diagonal
                    // Three lights drifting inside the card.
                    light(Aura.lavender, size: size, scale: 1.4, at: drift(t, base: CGPoint(x: 0.12, y: 0.15), amount: CGPoint(x: 0.08, y: 0.12), speed: 0.5, phase: 0))
                    light(Aura.rose, size: size, scale: 1.1, at: drift(t, base: CGPoint(x: 0.62, y: 0.75), amount: CGPoint(x: 0.10, y: 0.10), speed: 0.42, phase: 1))
                    light(Aura.peach, size: size, scale: 1.2, at: drift(t, base: CGPoint(x: 0.95, y: 0.2), amount: CGPoint(x: 0.06, y: 0.12), speed: 0.6, phase: 2))
                    // Shimmer: a soft band of light crossing every few seconds.
                    LinearGradient(colors: [.clear, Color.white.opacity(0.38), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: size.width * 0.35, height: size.height * 2)
                        .rotationEffect(.degrees(22))
                        .position(x: shimmerX(t, width: size.width), y: size.height / 2)
                        .blendMode(.plusLighter)
                        .opacity(isStill ? 0 : 1)
                }
            }
        }
        .overlay(alignment: .leading) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(2.4)
                        .opacity(0.6)
                    Text(title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.footnote.weight(.medium))
                        .opacity(0.72)
                }
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.white.opacity(0.35)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                    .shadow(color: Color.white.opacity(0.5), radius: 10)
            }
            .foregroundStyle(Aura.ink)
            .padding(.horizontal, 24)
        }
        .frame(height: 172)
        .clipShape(shape)
        // The drifting lights reach outside the card; only the card itself takes taps.
        .contentShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8))
        .shadow(color: Aura.rose.opacity(0.35), radius: 26, y: 12)
        .shadow(color: Aura.lavender.opacity(0.25), radius: 12, y: 2)
    }

    /// A point (in unit coordinates) wandering around `base`.
    private func drift(_ t: CGFloat, base: CGPoint, amount: CGPoint, speed: CGFloat, phase: CGFloat) -> CGPoint {
        let dx: CGFloat = amount.x * sin(t * speed + phase)
        let dy: CGFloat = amount.y * cos(t * speed * 0.8 + phase * 1.3)
        return CGPoint(x: base.x + dx, y: base.y + dy)
    }

    /// The shimmer sweeps across during the first third of each cycle, then rests off-card.
    private func shimmerX(_ t: CGFloat, width: CGFloat) -> CGFloat {
        let cycle: CGFloat = 5.5
        let phase: CGFloat = t.truncatingRemainder(dividingBy: cycle) / cycle
        let progress: CGFloat = min(phase / 0.35, 1)
        return -width * 0.3 + progress * width * 1.6
    }

    private func light(_ color: Color, size: CGSize, scale: CGFloat, at unit: CGPoint) -> some View {
        let diameter = size.height * scale * 1.5
        let falloff = Gradient(stops: [
            .init(color: color, location: 0),
            .init(color: color.opacity(0.5), location: 0.45),
            .init(color: color.opacity(0), location: 1),
        ])
        return Circle()
            .fill(RadialGradient(gradient: falloff, center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .position(x: unit.x * size.width, y: unit.y * size.height)
    }
}

/// A smaller glass card with a glowing gradient icon.
struct AuraFeatureCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Aura.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Aura.diagonal))
                .shadow(color: Aura.lavender.opacity(0.55), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Aura.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Aura.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .auraGlass(cornerRadius: 24, tint: 0.5)
    }
}
