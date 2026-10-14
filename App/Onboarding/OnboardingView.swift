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
        Page(symbol: "face.smiling", title: "Face and body", text: "Smooth skin, brighten eyes and teeth, add makeup, reshape the face, slim the waist, lengthen the legs and sculpt abs. All adjustable."),
        Page(symbol: "camera.filters", title: "Looks and styles", text: "Film looks, Snapseed-style effects, light leaks, dust, retro frames, text and stickers. Remove things you don't want with one stroke."),
        Page(symbol: "lock", title: "Private by design", text: "Everything runs on your iPhone. No account, no uploads. Your originals are never changed."),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark(size: 16)
                Spacer()
                Button("Skip", action: onFinish)
                    .caps(11)
                    .foregroundStyle(Darkroom.stone)
                    .opacity(isLast ? 0 : 1)
                    .animation(Darkroom.ease, value: isLast)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer()
                        ZStack(alignment: .bottomLeading) {
                            ViewfinderFrame(length: 18)
                                .stroke(Darkroom.cream.opacity(0.7), lineWidth: 1)
                            Image(systemName: item.symbol)
                                .font(.system(size: 44, weight: .ultraLight))
                                .foregroundStyle(Darkroom.cream)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text(Darkroom.frameCode(index * 2))
                                .filmCode(10)
                                .foregroundStyle(Darkroom.safelight)
                                .padding(10)
                        }
                        .frame(width: 168, height: 210)
                        .frame(maxWidth: .infinity)
                        Spacer()
                        Text(String(format: "%02d / %02d", index + 1, pages.count))
                            .filmCode(11)
                            .foregroundStyle(Darkroom.safelight)
                        Text(item.title)
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Darkroom.cream)
                            .padding(.top, 10)
                        Text(item.text)
                            .font(.system(size: 15))
                            .foregroundStyle(Darkroom.stone)
                            .lineSpacing(4)
                            .padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Progress: a hairline that fills in safelight, page by page.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Darkroom.line)
                    Rectangle()
                        .fill(Darkroom.safelight)
                        .frame(width: geometry.size.width * CGFloat(page + 1) / CGFloat(pages.count))
                }
            }
            .frame(height: 1)
            .padding(.horizontal, 28)
            .animation(Darkroom.spring, value: page)

            Button {
                if !isLast {
                    withAnimation(Darkroom.spring) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(isLast ? "Start editing" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .background(Darkroom.ink.ignoresSafeArea())
    }
}
