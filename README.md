# Lumora

A complete iOS photo editor combining pro adjustments (Lightroom), creative tools (Snapseed),
aesthetic looks (Tezza) and face & body retouching (Facetune / Peachy) — 100 % on-device.

- **Research:** [docs/RESEARCH.md](docs/RESEARCH.md)
- **Plan & phases:** [docs/PLAN.md](docs/PLAN.md)
- **Install on iPhone (one-time setup):** [docs/SETUP.md](docs/SETUP.md)

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
