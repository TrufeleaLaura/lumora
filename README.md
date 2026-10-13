# Lumora

A complete iOS photo editor combining pro adjustments (Lightroom), creative tools (Snapseed),
aesthetic looks (Tezza) and face & body retouching (Facetune / Peachy) — 100 % on-device.

- **Research:** [docs/RESEARCH.md](docs/RESEARCH.md)
- **Plan & phases:** [docs/PLAN.md](docs/PLAN.md)
- **Install on iPhone (one-time setup):** [docs/SETUP.md](docs/SETUP.md)

## Features
| Tool | What it does |
|---|---|
| **Looks** | 56 built-in looks in 8 packs, strength, your own presets, `.cube` LUT import, copy/paste and batch paste |
| **Enhance** | One-tap auto enhance, low light, sky replacement (6 generated skies), background color / cut-out, background blur |
| **Adjust** | Light, color (with white-balance eyedropper), HSL mixer, color grading, curves, texture/clarity/dehaze, vignette, grain, sharpening, noise reduction, lens corrections; live histogram with clipping view |
| **Masks** | Subject, background, sky, tapped objects, people parts (skin, eyes, brows, lips, teeth, hair, clothes), brush with auto edge, linear/radial, color & luminance ranges, control points — each with its own adjustments |
| **Retouch** | Heal, clone, remove (content-aware fill, tap to remove objects or people), red eye |
| **Styles** | HDR Scape, Drama, Tonal Contrast, Glamour Glow, Halation, Vintage, Noir, Grunge, RGB split, lens blur & tilt-shift |
| **Overlays** | Dust, scratches, light leaks, paper, plastic, window/leaf shadows, prism; frames (border, instant, 35 mm, Super 8, VHS) and date stamp |
| **Text** | Text in 14 fonts and stickers, placed and styled on the photo |
| **Face** | Blemish removal, skin smoothing, even tone, shine, dark circles, eyes, teeth, iris color, face reshape, brows, lipstick, blush, contour, eye makeup, hair color — all faces or one |
| **Body** | Waist, hips, butt, bust, thighs, legs, height, arms, shoulders, neck, head; abs, chest, arm definition, V-line; body skin smoothing, tan, cellulite |
| **Reshape** | Push, enlarge, shrink and restore brushes for manual reshaping |
| **Crop** | Aspect presets, straighten (auto horizon), rotate, flip, perspective |
| **Library** | Projects, collage / story / moodboard maker, Instagram feed planner, export (HEIC/JPEG/PNG, enlarge 2×, metadata options) |

## Stack
Swift · SwiftUI · Core Image + Metal kernels · Vision · Core ML. The Xcode project is generated from
[`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and built on
GitHub Actions macOS runners (no local Mac required).

## Layout
| Folder | Contents |
|---|---|
| `Core/` | `LumoraCore` framework — edit document, undo history, adjustment catalog (pure Swift) |
| `Engine/` | `LumoraEngine` framework — Core Image pipeline, Metal kernels, export, analysis, ML |
| `App/` | SwiftUI app — library, editor, tools |
| `Tests/` | Unit tests and render tests (render tests write PNG contact sheets) |
| `scripts/` | CI helpers: unsigned IPA packaging, simulator selection, icon generator |

## CI
Every push to `main` runs [`.github/workflows/ios.yml`](.github/workflows/ios.yml):
1. **Build & test** on an iOS simulator → uploads `render-output` (visual contact sheets).
2. **Unsigned IPA** → uploads `Lumora-ipa`, which is installed with Sideloadly.
