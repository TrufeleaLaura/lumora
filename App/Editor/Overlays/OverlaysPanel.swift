import LumoraCore
import SwiftUI

/// Texture overlays, frames and the date stamp.
struct OverlaysPanel: View {
    @ObservedObject var session: EditorSession
    @State private var page: Page = .overlays
    @State private var overlay: Overlay = .lightLeak

    enum Page: String, CaseIterable, Identifiable {
        case overlays, frame
        var id: String { rawValue }
        var title: String { self == .overlays ? "Overlays" : "Frame" }
    }

    enum Overlay: String, CaseIterable, Identifiable {
        case dust, scratches, lightLeak, paper, plastic, shadows, prism

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dust: return "Dust"
            case .scratches: return "Scratches"
            case .lightLeak: return "Light leak"
            case .paper: return "Paper"
            case .plastic: return "Plastic"
            case .shadows: return "Shadows"
            case .prism: return "Prism"
            }
        }

        var symbol: String {
            switch self {
            case .dust: return "aqi.medium"
            case .scratches: return "line.3.horizontal.decrease"
            case .lightLeak: return "flame"
            case .paper: return "doc.plaintext"
            case .plastic: return "rainbow"
            case .shadows: return "blinds.horizontal.closed"
            case .prism: return "triangle"
            }
        }

        var amount: WritableKeyPath<OverlaySettings, Double> {
            switch self {
            case .dust: return \.dust
            case .scratches: return \.scratches
            case .lightLeak: return \.lightLeak
            case .paper: return \.paper
            case .plastic: return \.plastic
            case .shadows: return \.shadows
            case .prism: return \.prism
            }
        }

        var style: WritableKeyPath<OverlaySettings, Double>? {
            switch self {
            case .dust, .scratches: return \.dustStyle
            case .lightLeak: return \.lightLeakStyle
            case .shadows: return \.shadowStyle
            case .prism: return \.prismStyle
            case .paper, .plastic: return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Page", selection: $page) {
                ForEach(Page.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            if page == .overlays {
                overlayChips
                ScrollView {
                    SliderList(session: session, specs: specs(overlay))
                        .padding(.bottom, 8)
                }
            } else {
                ScrollView {
                    framePage
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var overlayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Overlay.allCases) { item in
                    let active = session.document.overlays[keyPath: item.amount] > 0
                    Button {
                        overlay = item
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                            Text(item.title)
                            if active {
                                Circle()
                                    .fill(overlay == item ? Color.black : Theme.accent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(overlay == item ? Color.black : Color.primary)
                        .background(overlay == item ? Theme.accent : Theme.panelRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func specs(_ item: Overlay) -> [SliderSpec] {
        var specs = [SliderSpec(id: "overlay.\(item.rawValue)", title: "Strength", range: 0...100, style: .integer, keyPath: (\EditDocument.overlays).appending(path: item.amount))]
        if let style = item.style {
            specs.append(SliderSpec(id: "overlay.\(item.rawValue).style", title: "Variation", range: 0...5, style: .integer, keyPath: (\EditDocument.overlays).appending(path: style)))
        }
        return specs
    }

    private var framePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(FrameStyle.allCases) { style in
                    let selected = session.document.frame.style == style
                    Button {
                        session.setFrameStyle(style)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: style.symbol)
                                .font(.system(size: 18))
                            Text(style.title)
                                .font(.caption2.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? Color.black : Color.primary)
                        .background(selected ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            if session.document.frame.style == .border || session.document.frame.style == .polaroid {
                if session.document.frame.style == .border {
                    SliderList(session: session, specs: [
                        SliderSpec(id: "frame.width", title: "Width", range: 5...100, defaultValue: 40, style: .integer, keyPath: \EditDocument.frame.width),
                    ])
                }
                ColorRow(selected: session.document.frame.color) { session.setFrameColor($0) }
            }
            Toggle("Date stamp", isOn: Binding(
                get: { session.document.frame.dateStamp },
                set: { session.setDateStamp($0) }
            ))
            .tint(Theme.accent)
            if session.document.frame.dateStamp {
                HStack {
                    Text("Date")
                        .font(.subheadline)
                    TextField("'26 10 13", text: Binding(
                        get: { session.document.frame.dateText },
                        set: { value in session.perform("Date text") { $0.frame.dateText = value } }
                    ))
                    .font(.subheadline.monospaced())
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

/// A row of color swatches.
struct ColorRow: View {
    let selected: RGBColor
    let action: (RGBColor) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(RGBColor.palette, id: \.self) { color in
                    Button {
                        action(color)
                    } label: {
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(color == selected ? Theme.accent : Color.white.opacity(0.25), lineWidth: color == selected ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 3)
        }
    }
}
