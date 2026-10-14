import LumoraCore
import SwiftUI

/// Crop & rotate controls: aspect presets, straighten (with auto), perspective, rotate and flip.
struct CropPanel: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AspectRatioPreset.allCases) { preset in
                        Button {
                            session.setAspect(preset)
                        } label: {
                            Text(preset.title)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .auraChip(session.document.geometry.aspect == preset, shape: Capsule())
                        }
                        .buttonStyle(AuraPressStyle())
                    }
                }
            }

            HStack(spacing: 22) {
                iconButton("rotate.right", label: "Rotate") { session.rotateClockwise() }
                iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontal") { session.flip(horizontal: true) }
                iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", label: "Flip vertical") { session.flip(horizontal: false) }
                iconButton("level", label: "Auto straighten") { session.autoStraighten() }
                Spacer()
                Button("Reset") { session.resetGeometry() }
                    .font(.footnote.weight(.semibold))
                    .disabled(session.document.geometry.isIdentity && session.document.geometry.aspect == .free)
            }
            .font(.system(size: 18))

            ScrollView {
                SliderList(session: session, specs: AdjustmentCatalog.geometry.sliders)
            }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .accessibilityLabel(label)
    }
}
