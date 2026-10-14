import SwiftUI

/// A short welcome tour shown on first launch.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(symbol: "slider.horizontal.3", title: "Pro-level editing", text: "Light, color, curves, grading and detail like Lightroom, plus masks for the sky, the subject, people and anything you paint."),
        Page(symbol: "face.smiling", title: "Face & body", text: "Smooth skin, brighten eyes and teeth, add makeup, reshape the face, slim the waist, lengthen the legs and sculpt abs — all adjustable."),
        Page(symbol: "wand.and.stars", title: "Looks & styles", text: "Film looks, Snapseed-style effects, light leaks, dust, retro frames, text and stickers. Remove things you don't want with one stroke."),
        Page(symbol: "lock.shield", title: "Private by design", text: "Everything runs on your iPhone. No account, no uploads. Your originals are never changed."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LumoraWordmark(size: 24)
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Aura.textSecondary)
                    .opacity(isLast ? 0 : 1)
                    .animation(Aura.soft, value: isLast)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 26) {
                        Spacer()
                        OnboardingOrb(symbol: item.symbol, isActive: page == index)
                        VStack(spacing: 12) {
                            Text(item.title)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Aura.textPrimary)
                            Text(item.text)
                                .font(.body)
                                .foregroundStyle(Aura.textSecondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 34)
                        }
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page indicator: the current page stretches into a glowing gradient pill.
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AnyShapeStyle(Aura.gradient) : AnyShapeStyle(Aura.textSecondary.opacity(0.3)))
                        .frame(width: index == page ? 26 : 7, height: 7)
                        .shadow(color: index == page ? Aura.lavender.opacity(0.7) : .clear, radius: 6)
                }
            }
            .animation(Aura.bouncy, value: page)
            .padding(.bottom, 26)

            Button {
                if !isLast {
                    withAnimation(Aura.spring) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(isLast ? "Start editing" : "Next")
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
            .buttonStyle(AuraPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AuraBackground())
    }
}

/// A glass orb holding the page's symbol, with a slowly turning aura halo.
private struct OnboardingOrb: View {
    let symbol: String
    let isActive: Bool
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Aura.gradientColors + [Aura.lavender], center: .center))
                .frame(width: 190, height: 190)
                .blur(radius: 36)
                .opacity(0.65)
                .rotationEffect(.degrees(turning ? 360 : 0))
            Circle()
                .strokeBorder(AngularGradient(colors: Aura.gradientColors + [Aura.lavender], center: .center), lineWidth: 1.2)
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(turning ? -360 : 0))
                .opacity(0.8)
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Aura.diagonal)
                .frame(width: 140, height: 140)
                .auraGlass(Circle(), tint: 0.45)
                .shadow(color: Aura.lavender.opacity(0.4), radius: 20)
                .symbolEffect(.bounce, value: isActive)
        }
        .scaleEffect(isActive ? 1 : 0.85)
        .opacity(isActive ? 1 : 0.4)
        .animation(Aura.bouncy, value: isActive)
        .onAppear {
            guard !reduceMotion, !Aura.isUITesting else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { turning = true }
        }
    }
}
