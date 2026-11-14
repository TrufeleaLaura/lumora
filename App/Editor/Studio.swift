import LumoraCore

/// The editor's map: five categories, each holding a few tools. A tool opens one of the editor's
/// panels (an `EditorTool`), sometimes on one part of it, so people never face all features at once.
enum StudioCategory: String, CaseIterable, Identifiable {
    case looks, adjust, portrait, retouch, create

    var id: String { rawValue }

    var title: String {
        switch self {
        case .looks: return "Looks"
        case .adjust: return "Adjust"
        case .portrait: return "Portrait"
        case .retouch: return "Retouch"
        case .create: return "Create"
        }
    }

    /// Shown once, the first time the category opens.
    var tip: String {
        switch self {
        case .looks: return "Start here. A look sets the mood, and everything after it stays adjustable."
        case .adjust: return "Work from top to bottom: light first, then color, then detail."
        case .portrait: return "Less is more. Small amounts look the most natural."
        case .retouch: return "Paint loosely. Lumora finds the edges for you."
        case .create: return "Finishing touches for your feed and your stories."
        }
    }

    var tools: [StudioTool] { StudioTool.allCases.filter { $0.category == self } }
}

enum StudioTool: String, CaseIterable, Identifiable {
    case presets, auto
    case light, color, curve, grading, detail, masks, crop
    case skin, features, makeup, hair, body, reshape
    case remove, heal, clone, sky, background
    case effects, lightAndDust, frames, text, stickers

    var id: String { rawValue }

    var category: StudioCategory {
        switch self {
        case .presets, .auto: return .looks
        case .light, .color, .curve, .grading, .detail, .masks, .crop: return .adjust
        case .skin, .features, .makeup, .hair, .body, .reshape: return .portrait
        case .remove, .heal, .clone, .sky, .background: return .retouch
        case .effects, .lightAndDust, .frames, .text, .stickers: return .create
        }
    }

    var title: String {
        switch self {
        case .presets: return "Presets"
        case .auto: return "Auto"
        case .light: return "Light"
        case .color: return "Color"
        case .curve: return "Curve"
        case .grading: return "Grading"
        case .detail: return "Detail"
        case .masks: return "Masks"
        case .crop: return "Crop"
        case .skin: return "Skin"
        case .features: return "Features"
        case .makeup: return "Makeup"
        case .hair: return "Hair"
        case .body: return "Body"
        case .reshape: return "Reshape"
        case .remove: return "Remove"
        case .heal: return "Heal"
        case .clone: return "Clone"
        case .sky: return "Sky"
        case .background: return "Background"
        case .effects: return "Effects"
        case .lightAndDust: return "Light and dust"
        case .frames: return "Frames"
        case .text: return "Text"
        case .stickers: return "Stickers"
        }
    }

    /// One line that says what the tool does.
    var summary: String {
        switch self {
        case .presets: return "Film, portrait and airy looks, previewed on your photo."
        case .auto: return "Let Lumora balance light and color for you."
        case .light: return "Exposure, contrast, highlights and shadows."
        case .color: return "White balance, vibrance, saturation and each color on its own."
        case .curve: return "Shape every tone precisely with a tone curve."
        case .grading: return "Tint the shadows, midtones and highlights."
        case .detail: return "Sharpen, reduce noise, add grain, vignette and lens fixes."
        case .masks: return "Edit only the subject, the sky or the background."
        case .crop: return "Straighten, rotate and choose a format."
        case .skin: return "Smooth and even out skin while keeping its texture."
        case .features: return "Brighten eyes and teeth, shape brows, nose, lips and face."
        case .makeup: return "Complete looks, or lipstick, blush and eye makeup one by one."
        case .hair: return "Color, ombré, shine and volume."
        case .body: return "Waist, legs, bust and posture, in natural proportions."
        case .reshape: return "Nudge any outline gently with your finger."
        case .remove: return "Paint over people or objects and they disappear."
        case .heal: return "Tap spots and small marks to blend them away."
        case .clone: return "Copy one area onto another."
        case .sky: return "Replace a dull sky with a sunset or soft clouds."
        case .background: return "Blur it like a portrait lens, recolor it or cut it out."
        case .effects: return "HDR, drama, glamour glow, halation, lens blur and more."
        case .lightAndDust: return "Light leaks, dust, scratches and paper textures."
        case .frames: return "Instant, 35 mm, Super 8, VHS and clean borders."
        case .text: return "Titles and captions in carefully chosen type."
        case .stickers: return "Small marks and shapes for stories."
        }
    }

    /// Extra words people might search for.
    var keywords: String {
        switch self {
        case .presets: return "filter film preset look vsco aesthetic mood tone saved"
        case .auto: return "auto enhance fix one tap dark night low light"
        case .light: return "brightness bright brighter dark exposure contrast shadows highlights whites blacks"
        case .color: return "warm warmer cool cooler white balance temperature tint saturation vibrance mixer hsl black white"
        case .curve: return "curve tones rgb fade matte"
        case .grading: return "grading split toning color wheels cinematic"
        case .detail: return "sharpen sharp noise grain vignette clarity texture lens distortion"
        case .masks: return "mask selective local subject sky background brush people"
        case .crop: return "crop rotate straighten level horizon 9:16 4:5 square format flip"
        case .skin: return "smooth skin acne pimple blemish spot pores glow under eye bags"
        case .features: return "eyes teeth white whiten smile lips brows eyebrows nose jaw chin face shape slim"
        case .makeup: return "makeup lipstick blush eyeliner eyeshadow lashes contour highlight glam"
        case .hair: return "hair color dye blonde brunette ombre shine volume"
        case .body: return "body slim thin waist legs tall longer bust chest shoulders abs muscles tan"
        case .reshape: return "reshape liquify push warp nudge enlarge shrink"
        case .remove: return "remove erase delete person people photobomb object wire"
        case .heal: return "heal spot mark scratch dust red eye"
        case .clone: return "clone copy stamp duplicate"
        case .sky: return "sky sunset clouds replace blue"
        case .background: return "background blur bokeh portrait mode cut out transparent color"
        case .effects: return "effects hdr drama glow halation vintage noir grunge lens blur"
        case .lightAndDust: return "light leak dust film burn scratches texture paper prism"
        case .frames: return "frame border polaroid instant film 35mm super 8 vhs date"
        case .text: return "text title caption font type words"
        case .stickers: return "sticker heart star shapes"
        }
    }

    /// The editor panel (and canvas overlay) this tool uses.
    var editorTool: EditorTool {
        switch self {
        case .presets: return .looks
        case .auto, .sky, .background: return .enhance
        case .light, .color, .curve, .grading, .detail: return .adjust
        case .masks: return .masks
        case .crop: return .crop
        case .skin, .features, .makeup, .hair: return .face
        case .body: return .body
        case .reshape: return .reshape
        case .remove, .heal, .clone: return .retouch
        case .effects: return .styles
        case .lightAndDust, .frames: return .overlays
        case .text, .stickers: return .text
        }
    }

    /// Parts of the Adjust panel shown by an Adjust tool.
    var adjustSections: [AdjustSection] {
        switch self {
        case .light: return [.light]
        case .color: return [.color, .mixer]
        case .curve: return [.curve]
        case .grading: return [.grading]
        case .detail: return [.detail, .effects, .optics]
        default: return []
        }
    }

    /// Parts of the Face panel shown by a Portrait tool.
    var faceSections: [FaceCatalog.Section] {
        switch self {
        case .skin: return [.skin]
        case .features: return [.eyes, .teeth, .brows, .noseLips, .shape]
        case .makeup: return [.looks, .lipstick, .cheeks, .eyeMakeup]
        case .hair: return [.hair]
        default: return []
        }
    }

    var retouchTool: RetouchTool? {
        switch self {
        case .remove: return .remove
        case .heal: return .heal
        case .clone: return .clone
        default: return nil
        }
    }

    /// "Portrait › Skin"
    var path: String { "\(category.title) \u{203A} \(title)" }
}

/// Plain-language searches that lead straight to a tool.
struct ToolShortcut: Identifiable {
    let title: String
    let tool: StudioTool
    let keywords: String

    var id: String { title }

    static let all: [ToolShortcut] = [
        ToolShortcut(title: "Whiten teeth", tool: .features, keywords: "teeth white smile"),
        ToolShortcut(title: "Brighten eyes", tool: .features, keywords: "eyes bright"),
        ToolShortcut(title: "Acne and blemishes", tool: .skin, keywords: "acne pimple blemish spot"),
        ToolShortcut(title: "Slim waist", tool: .body, keywords: "slim thin waist"),
        ToolShortcut(title: "Longer legs", tool: .body, keywords: "legs tall longer"),
        ToolShortcut(title: "Lipstick", tool: .makeup, keywords: "lipstick lips"),
        ToolShortcut(title: "Hair color", tool: .hair, keywords: "hair color dye"),
        ToolShortcut(title: "Remove a person", tool: .remove, keywords: "person people photobomb erase remove"),
        ToolShortcut(title: "Blur the background", tool: .background, keywords: "blur bokeh background portrait"),
        ToolShortcut(title: "Change the sky", tool: .sky, keywords: "sky sunset clouds"),
        ToolShortcut(title: "Make it brighter", tool: .light, keywords: "brighter brighten bright dark"),
        ToolShortcut(title: "Warmer or cooler", tool: .color, keywords: "warm warmer cool cooler temperature"),
        ToolShortcut(title: "Black and white", tool: .color, keywords: "black white bw monochrome"),
        ToolShortcut(title: "Film grain", tool: .detail, keywords: "grain film noise"),
        ToolShortcut(title: "Straighten", tool: .crop, keywords: "straighten level horizon rotate"),
        ToolShortcut(title: "Instant frame", tool: .frames, keywords: "polaroid instant frame"),
    ]
}

/// A short guided sequence of tools for a common goal.
struct Recipe: Identifiable, Equatable {
    struct Step: Equatable {
        let tool: StudioTool
        let title: String
        let tip: String
    }

    let id: String
    let title: String
    let subtitle: String
    let summary: String
    let steps: [Step]

    static func == (lhs: Recipe, rhs: Recipe) -> Bool { lhs.id == rhs.id }

    static let all: [Recipe] = [
        Recipe(id: "portrait", title: "Natural portrait", subtitle: "Skin, eyes and teeth, gently",
               summary: "Three gentle steps for skin that still looks like skin.", steps: [
            Step(tool: .presets, title: "Pick a soft look", tip: "A warm or pink portrait look flatters most skin tones."),
            Step(tool: .skin, title: "Smooth skin to about 30", tip: "Lower amounts keep pores and texture visible."),
            Step(tool: .features, title: "Whiten teeth a little", tip: "Around 15 looks natural. Higher starts to glow."),
        ]),
        Recipe(id: "dark", title: "Brighten a dark photo", subtitle: "Lift shadows, clean up noise",
               summary: "For photos taken indoors or at night.", steps: [
            Step(tool: .auto, title: "Tap Low light", tip: "It brightens and removes color noise in one go."),
            Step(tool: .light, title: "Lift the shadows", tip: "Stop when faces are clear. The sky can stay darker."),
            Step(tool: .detail, title: "Add noise reduction", tip: "Only if the photo still looks grainy."),
        ]),
        Recipe(id: "remove", title: "Remove something", subtitle: "People, wires and spots",
               summary: "Paint over it and Lumora fills in what was behind.", steps: [
            Step(tool: .remove, title: "Paint over it in one stroke", tip: "Cover it fully, including its shadow."),
            Step(tool: .heal, title: "Tap any leftover marks", tip: "Small taps work better than long strokes."),
        ]),
        Recipe(id: "film", title: "Film look", subtitle: "Warm tones, light leaks and a frame",
               summary: "The feel of a film camera, made for your feed.", steps: [
            Step(tool: .presets, title: "Choose a film look", tip: "Warm tones and soft contrast keep skin natural."),
            Step(tool: .lightAndDust, title: "Add a faint light leak", tip: "Keep the amount under 40."),
            Step(tool: .frames, title: "Finish with a frame", tip: "35 mm for film, Instant for the feel of a print."),
        ]),
        Recipe(id: "shape", title: "Slim and shape", subtitle: "Waist, legs and posture",
               summary: "Small changes read as real. Big ones show.", steps: [
            Step(tool: .body, title: "Adjust waist and legs", tip: "Stay under 25 for natural proportions."),
            Step(tool: .reshape, title: "Fine-tune the outlines", tip: "Use a large brush and gentle pushes."),
        ]),
        Recipe(id: "story", title: "Story with text", subtitle: "A 9:16 crop and a title",
               summary: "Ready to post as an Instagram story.", steps: [
            Step(tool: .crop, title: "Crop to 9:16", tip: "Keep the face in the upper third."),
            Step(tool: .text, title: "Add a title", tip: "One short line reads best on a story."),
        ]),
    ]
}

/// Where someone is in a recipe.
struct GuideProgress: Equatable {
    let recipe: Recipe
    var step: Int

    var current: Recipe.Step { recipe.steps[step] }
    var isLast: Bool { step == recipe.steps.count - 1 }
}
