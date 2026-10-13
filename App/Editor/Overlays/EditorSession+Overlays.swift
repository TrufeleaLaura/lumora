import Foundation
import LumoraCore
import LumoraEngine
import SwiftUI

extension EditorSession {
    // MARK: - Frame & date stamp

    /// The photo's capture date from its metadata, if any.
    var photoDate: Date? {
        let exif = source.properties["{Exif}"] as? [String: Any]
        let tiff = source.properties["{TIFF}"] as? [String: Any]
        guard let text = (exif?["DateTimeOriginal"] as? String) ?? (tiff?["DateTime"] as? String) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    func setFrameStyle(_ style: FrameStyle) {
        perform("Frame \(style.title)") { $0.frame.style = style }
    }

    func setFrameColor(_ color: RGBColor) {
        perform("Frame color") { $0.frame.color = color }
    }

    func setDateStamp(_ on: Bool) {
        let text = RenderPipeline.stampText(for: photoDate ?? Date())
        perform(on ? "Date stamp" : "No date stamp") { document in
            document.frame.dateStamp = on
            if on && document.frame.dateText.isEmpty {
                document.frame.dateText = text
            }
        }
    }

    // MARK: - Text & stickers

    var selectedTextIndex: Int? {
        guard let selectedTextID else { return nil }
        return document.texts.firstIndex { $0.id == selectedTextID }
    }

    func addText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var layer = TextLayer(text: trimmed)
        layer.position = SIMD2(0.5, 0.5 - 0.08 * Double(document.texts.count % 4))
        perform("Add text") { $0.texts.append(layer) }
        selectedTextID = layer.id
    }

    func addSticker(_ symbol: String) {
        var layer = TextLayer(text: "", symbol: symbol)
        layer.size = 0.1
        layer.position = SIMD2(0.5 + 0.06 * Double(document.texts.count % 3), 0.5)
        perform("Add sticker") { $0.texts.append(layer) }
        selectedTextID = layer.id
    }

    func updateSelectedText(_ label: String, _ change: (inout TextLayer) -> Void) {
        guard let index = selectedTextIndex else { return }
        perform(label) { change(&$0.texts[index]) }
    }

    func deleteSelectedText() {
        guard let index = selectedTextIndex else { return }
        perform("Delete layer") { $0.texts.remove(at: index) }
        selectedTextID = document.texts.last?.id
    }

    func duplicateSelectedText() {
        guard let index = selectedTextIndex else { return }
        var copy = document.texts[index]
        copy.id = UUID()
        copy.position += SIMD2(0.04, -0.04)
        perform("Duplicate layer") { $0.texts.append(copy) }
        selectedTextID = copy.id
    }

    /// Where the cropped photo sits inside the framed output (fractions of the output, y up),
    /// so canvas handles can find text positions.
    var contentRectInOutput: CGRect {
        let size = outputPixelSize
        let layout = FrameLayout.layout(document.frame, contentWidth: Double(size.width), contentHeight: Double(size.height))
        guard layout.width > 0, layout.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(
            x: layout.content.x / layout.width,
            y: layout.content.y / layout.height,
            width: layout.content.width / layout.width,
            height: layout.content.height / layout.height
        )
    }
}
