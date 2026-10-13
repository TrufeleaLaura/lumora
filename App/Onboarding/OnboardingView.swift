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

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: item.symbol)
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(Theme.gradient)
                        Text(item.title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Start editing")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Button("Skip", action: onFinish)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
                .opacity(page < pages.count - 1 ? 1 : 0)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
