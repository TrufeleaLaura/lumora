import SwiftUI

/// A short guide to one tool: what it is for, how to use it step by step, and a few things worth
/// knowing. Harder tools also have one tip shown the first time they open.
struct ToolGuide {
    let intro: String
    let steps: [String]
    let tips: [String]
    /// Shown once, the first time a harder tool opens.
    var firstTip: String?

    static func of(_ tool: StudioTool) -> ToolGuide {
        switch tool {
        case .presets:
            return ToolGuide(
                intro: "Presets are complete looks built from Lumora's own adjustments. They set the mood before you fine-tune.",
                steps: [
                    "Pick a pack at the top: Trending, Film, Portrait and more.",
                    "Tap a look to try it on your photo. Tap another to compare.",
                    "Keep editing in other tools. Your own changes stay on top of the look.",
                    "Like the result? Tap Save as preset to reuse it on other photos.",
                ],
                tips: [
                    "Portrait looks are tuned to keep skin tones natural.",
                    "Tap None to remove the look without losing your other edits.",
                ])
        case .auto:
            return ToolGuide(
                intro: "Auto studies your photo and sets light and color for you. It is a good first step, not the last.",
                steps: [
                    "Tap Apply next to Auto enhance for everyday photos.",
                    "Use Low light for photos taken indoors or at night.",
                    "Fine-tune afterwards in Adjust \u{203A} Light if you want it brighter or darker.",
                ],
                tips: [
                    "Auto is an ordinary edit: undo it, or change any slider it moved.",
                    "When there are faces in the photo, Auto exposes for them first.",
                ])
        case .light:
            return ToolGuide(
                intro: "Light controls how bright the photo is and how much contrast it has.",
                steps: [
                    "Start with Exposure to set the overall brightness.",
                    "Use Highlights to bring back a bright sky, and Shadows to open up dark areas.",
                    "Add Contrast last, until the photo has depth without harsh edges.",
                    "Whites and Blacks set the brightest and darkest points. Small moves are enough.",
                ],
                tips: [
                    "Double-tap a slider's name to reset it.",
                    "Watch the histogram at the top right: a wall at either edge means lost detail.",
                ])
        case .color:
            return ToolGuide(
                intro: "Color sets the mood, warm or cool, rich or soft. The mixer changes one color at a time.",
                steps: [
                    "Fix white balance first: tap the picker, then something white or grey in the photo.",
                    "Adjust Temperature (blue to yellow) and Tint (green to magenta) by eye.",
                    "Add Vibrance before Saturation. Vibrance protects skin tones.",
                    "In the mixer, pick a color and change its hue, saturation or brightness.",
                ],
                tips: [
                    "If skin looks too red, lower the orange saturation a little in the mixer.",
                    "Black and white keeps the mixer working: use it to lighten or darken areas by their color.",
                ],
                firstTip: "Fix white balance first: tap the picker, then something white or grey.")
        case .curve:
            return ToolGuide(
                intro: "The tone curve maps every brightness level in the photo. It is precise, so small moves go a long way.",
                steps: [
                    "Pick RGB to change brightness, or Red, Green or Blue to tint.",
                    "Drag a point on the line. Up makes that tone brighter, down makes it darker.",
                    "For gentle contrast, lift the upper part slightly and lower the lower part slightly.",
                    "For a faded film look, raise the very first point.",
                ],
                tips: [
                    "The left of the curve is shadows, the middle is midtones, the right is highlights.",
                    "If the photo looks harsh, flatten the curve a little.",
                ],
                firstTip: "Left is shadows, right is highlights. Drag up to brighten, down to darken.")
        case .grading:
            return ToolGuide(
                intro: "Grading adds a color to the shadows, midtones and highlights separately. It is how films get their look.",
                steps: [
                    "Drag the dot in the Shadows wheel toward a color, such as teal or blue.",
                    "Drag Highlights toward a warmer color, such as orange or gold.",
                    "Keep the dots close to the center. Small moves look cinematic, big ones look artificial.",
                    "Use Balance to shift the grade toward the shadows or the highlights.",
                ],
                tips: [
                    "Opposite colors in shadows and highlights, like teal and orange, give a classic film look.",
                    "Check the skin: if it turns grey or green, pull the midtones back.",
                ],
                firstTip: "Keep the dots near the center. Small moves look cinematic.")
        case .detail:
            return ToolGuide(
                intro: "Detail sharpens edges, cleans up noise and adds finishing texture.",
                steps: [
                    "Add sharpening last, while zoomed in on an eye or an edge.",
                    "Use noise reduction for grainy photos taken in low light.",
                    "Grain adds a film texture. Vignette darkens or brightens the corners.",
                    "Lens corrections fix distortion and dark corners caused by the camera lens.",
                ],
                tips: [
                    "Zoom in with two fingers to judge sharpening and noise.",
                    "Too much noise reduction makes skin look plastic.",
                ])
        case .masks:
            return ToolGuide(
                intro: "Masks let you edit one part of the photo: the person, the sky, the background, or anything you paint.",
                steps: [
                    "Start with One-tap presets: pick a category, then a preset such as Pop or Soft.",
                    "To build your own, open Make a mask and add Subject, Sky, Background or Brush.",
                    "Move the sliders. They change only the highlighted area.",
                    "Add or subtract more areas to refine the mask.",
                ],
                tips: [
                    "Lumora finds people, the subject and the sky on its own, so you rarely need to paint.",
                    "Each mask is separate. Tap one in the list to edit it again later.",
                ],
                firstTip: "Try One-tap presets first. Each edits only the person, the sky or the background.")
        case .crop:
            return ToolGuide(
                intro: "Crop frames the photo, straightens it and sets the format for where you will post it.",
                steps: [
                    "Pick a format: 4:5 for the Instagram feed, 9:16 for stories, 1:1 for a square.",
                    "Drag the corners on the photo to choose what stays in.",
                    "Use Straighten to level a tilted horizon.",
                    "Vertical and Horizontal fix buildings that lean when photographed from below.",
                ],
                tips: [
                    "The rotate and flip buttons give a quick turn or a mirror image.",
                    "Reset brings back the whole photo at any time.",
                ])
        case .skin:
            return ToolGuide(
                intro: "Skin retouching smooths and evens out skin while keeping it real.",
                steps: [
                    "Start with Remove blemishes to clear spots automatically.",
                    "Add Smooth slowly. Around 30 is enough for most faces.",
                    "Keep texture holds pores and fine detail, so skin never looks plastic.",
                    "With several faces, tap a number on the photo to edit one face only.",
                ],
                tips: [
                    "Zoom in to check that pores are still visible.",
                    "Auto, at the right of the description, applies gentle skin, eye and teeth retouching in one tap.",
                ],
                firstTip: "Around 30 smoothing is enough. Keep texture stops skin looking plastic.")
        case .features:
            return ToolGuide(
                intro: "Features brightens eyes and teeth and gently reshapes the brows, nose, lips and face.",
                steps: [
                    "Pick an area: Eyes, Teeth, Brows, Nose and lips, or Shape.",
                    "Move one slider at a time.",
                    "Compare often with the before and after button in the top bar.",
                ],
                tips: [
                    "Teeth whitening looks natural around 15 to 25.",
                    "Keep reshaping small: a few points read as natural, more starts to show.",
                ],
                firstTip: "Small amounts look the most natural. Compare often with before and after.")
        case .makeup:
            return ToolGuide(
                intro: "Makeup adds complete looks in one tap, or lipstick, blush and eye makeup one by one.",
                steps: [
                    "Start with a look in Makeup looks, such as Natural or Soft glam.",
                    "Fine-tune each product in Lipstick, Blush and contour, or Eye makeup.",
                    "Pick a color, then set the amount. Lower amounts look more natural.",
                    "For lipstick, choose a finish: matte, satin or gloss.",
                ],
                tips: [
                    "A look replaces the makeup but keeps your skin, face and hair settings.",
                    "Makeup follows the face, so it stays in place even when the head is tilted.",
                ],
                firstTip: "Start with a complete look, then adjust lips, blush or eyes on their own.")
        case .hair:
            return ToolGuide(
                intro: "Hair changes the color, adds an ombré, and boosts shine and volume.",
                steps: [
                    "Tap a color to tint the hair.",
                    "Pick an ombré color to fade into toward the ends.",
                    "Set the amount, then add shine and volume to taste.",
                ],
                tips: [
                    "Works best when the hair stands out clearly from the background.",
                    "Natural shades blend most convincingly. Bold colors need a lower amount.",
                ],
                firstTip: "Works best when the hair stands out clearly from the background.")
        case .body:
            return ToolGuide(
                intro: "Body reshapes the waist, legs, bust, shoulders and more, keeping proportions natural.",
                steps: [
                    "Pick a part: Shape, Bust, Length, Upper body, Muscles or Skin.",
                    "Move sliders a little at a time and watch straight lines in the background.",
                    "With several people, tap a marker on the photo to edit one person only.",
                ],
                tips: [
                    "Staying under 25 on most sliders keeps the result natural.",
                    "If a door frame or a wall starts to bend, go back a little, or fix it with Reshape and Restore.",
                ],
                firstTip: "Watch straight lines behind the person. If they bend, go back a little.")
        case .reshape:
            return ToolGuide(
                intro: "Reshape lets you nudge any outline with your finger: a waist, a jaw, a strand of hair.",
                steps: [
                    "Choose Push to move an outline, or Enlarge and Shrink to scale an area.",
                    "Set the size so the brush covers a bit more than the area you want to change.",
                    "Drag in short, gentle strokes.",
                    "Use Restore to paint the original back in any spot.",
                ],
                tips: [
                    "A large brush with low strength gives the smoothest result.",
                    "Last undoes your last stroke. Reset starts over.",
                ],
                firstTip: "Use a large brush and short, gentle strokes. Restore paints back the original.")
        case .remove:
            return ToolGuide(
                intro: "Remove erases people and objects and fills in what was behind them.",
                steps: [
                    "Turn on Tap objects or people, then tap what you want gone.",
                    "For anything else, paint over it with the brush. Cover it completely, including its shadow.",
                    "Let go and wait a moment while Lumora fills it in.",
                    "Leftover marks? Paint over them again, or use Heal.",
                ],
                tips: [
                    "Simple backgrounds such as sky, walls or grass give the cleanest results.",
                    "Remove large things in a few smaller strokes rather than one big one.",
                ],
                firstTip: "Paint over the whole thing, including its shadow, then let go.")
        case .heal:
            return ToolGuide(
                intro: "Heal blends small spots, marks and dust into the surface around them.",
                steps: [
                    "Tap a spot, or paint a short stroke over a mark.",
                    "Keep the brush just a little larger than the spot.",
                    "Use Red eye if eyes look red from the flash.",
                ],
                tips: [
                    "For larger objects, use Remove instead.",
                    "Last undoes the last stroke.",
                ])
        case .clone:
            return ToolGuide(
                intro: "Clone copies one area onto another, for repeating a pattern or covering something exactly.",
                steps: [
                    "First, tap the area you want to copy from.",
                    "Then paint where it should appear.",
                    "Tap New source to copy from somewhere else.",
                ],
                tips: [
                    "Pick a source with the same light and texture as the place you paint.",
                    "Use Heal or Remove when you don't need an exact copy.",
                ],
                firstTip: "First tap what to copy, then paint where it should go.")
        case .sky:
            return ToolGuide(
                intro: "Sky replaces a dull or washed-out sky and relights the photo to match.",
                steps: [
                    "Pick a sky: Clear, Sunset, Golden or Dramatic.",
                    "Set Amount to blend it in.",
                    "Relight warms or cools the rest of the photo to match the new sky.",
                    "Clouds changes the cloud pattern.",
                ],
                tips: [
                    "Works best outdoors, when the sky is clearly visible.",
                    "Original brings your own sky back.",
                ])
        case .background:
            return ToolGuide(
                intro: "Background blurs, recolors or removes everything behind the person.",
                steps: [
                    "Tap Apply on Blur the background for a portrait-lens look.",
                    "Choose Color to place the person on a plain color.",
                    "Choose Remove to cut the background out.",
                ],
                tips: [
                    "Export as PNG to keep a removed background transparent.",
                    "Change the blur strength later in Create \u{203A} Effects \u{203A} Lens blur.",
                ])
        case .effects:
            return ToolGuide(
                intro: "Effects are bold, one-step styles: HDR, drama, glamour glow, halation, lens blur and more.",
                steps: [
                    "Tap an effect to preview it on your photo.",
                    "Set Strength. Most effects look best at a lower strength.",
                    "For Lens blur, move the focus area on the photo to choose what stays sharp.",
                ],
                tips: [
                    "Glamour glow softens skin and adds a gentle bloom, lovely for portraits.",
                    "One effect on top of a preset usually looks better than several effects together.",
                ])
        case .lightAndDust:
            return ToolGuide(
                intro: "Light and dust adds film textures: light leaks, dust, scratches, paper and more.",
                steps: [
                    "Pick a texture.",
                    "Keep Strength low at first. Textures are best felt rather than seen.",
                    "Use Variation to try another version of the same texture.",
                ],
                tips: [
                    "A faint light leak at the edge adds warmth to film looks.",
                    "Pair it with a frame for the feel of a print.",
                ])
        case .frames:
            return ToolGuide(
                intro: "Frames finish the photo with a border, an instant print, a film strip or a VHS look.",
                steps: [
                    "Tap a frame style.",
                    "Pick a frame color where there is one.",
                    "The frame is part of the photo when you export.",
                ],
                tips: [
                    "Instant suits soft, warm looks beautifully.",
                    "Crop first: frames follow the final format.",
                ])
        case .text:
            return ToolGuide(
                intro: "Text adds titles and captions in carefully chosen styles.",
                steps: [
                    "Tap Text and type your words.",
                    "Pick a style, then drag the text on the photo to place it.",
                    "Change the font, color, size and rotation below the styles.",
                ],
                tips: [
                    "One short line reads best on a story.",
                    "Light text on dark areas, dark text on light areas.",
                ])
        case .stickers:
            return ToolGuide(
                intro: "Stickers are small shapes and marks for stories.",
                steps: [
                    "Tap a sticker to add it.",
                    "Drag it on the photo to place it.",
                    "Select it to change its color, size, rotation or opacity.",
                ],
                tips: [
                    "Small stickers near the edges look more refined than big ones in the middle.",
                    "Duplicate a sticker to make a pattern.",
                ])
        }
    }
}

/// The guide sheet opened from a tool's info button.
struct ToolGuideView: View {
    let tool: StudioTool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let guide = ToolGuide.of(tool)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.path.uppercased())
                    .filmCode(10)
                    .foregroundStyle(Darkroom.safelight)
                    .padding(.top, 24)
                Text(tool.title)
                    .font(Typeface.cormorant(40, weight: 500))
                    .foregroundStyle(Darkroom.cream)
                    .padding(.top, 6)
                Text(guide.intro)
                    .font(Typeface.jost(15))
                    .foregroundStyle(Darkroom.stone)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                section("Step by step")
                VStack(spacing: 0) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .filmCode(11)
                                .foregroundStyle(Darkroom.safelight)
                                .padding(.top, 2)
                            Text(step)
                                .font(Typeface.jost(15))
                                .foregroundStyle(Darkroom.cream)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(Darkroom.line).frame(height: 0.5).padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(Darkroom.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                section("Good to know")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(guide.tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Darkroom.safelight)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(tip)
                                .font(Typeface.jost(14))
                                .foregroundStyle(Darkroom.stone)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 4)

                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("guide.close")
                .padding(.top, 28)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Darkroom.ink.ignoresSafeArea())
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Typeface.jost(15, weight: 560))
            .foregroundStyle(Darkroom.stone)
            .padding(.leading, 4)
            .padding(.top, 26)
            .padding(.bottom, 8)
    }
}
