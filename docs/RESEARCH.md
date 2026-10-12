# Research — iOS Photo Editor (Lightroom + Snapseed + Tezza + Facetune/Body editors)

_Researched: 2026-10-12_

This document collects (1) what the leading apps offer, so we can build the most complete feature set,
(2) which Apple frameworks and on-device AI models can deliver those features with top quality, and
(3) the practical constraints of building an iOS app from a Windows-only machine.

---

## 1. Competitor feature survey

### Adobe Lightroom mobile (the "pro" reference)
- **Light:** exposure, contrast, highlights, shadows, whites, blacks, point + parametric tone curve (RGB and per channel).
- **Color:** white balance (temp/tint, eyedropper), vibrance, saturation, color mixer (HSL across 8 hue bands),
  point color, 3-way color grading (shadows/midtones/highlights + global, blending, balance), B&W mixer.
- **Effects:** texture, clarity, dehaze, vignette, grain. **Detail:** sharpening, noise reduction, AI Denoise.
  **Optics:** lens profile, chromatic aberration. **Geometry:** upright/guided upright, perspective, crop, straighten.
- **Masks:** Select Subject (AI model updated July 2026), Sky, Background, People (face skin, body skin, eyebrows,
  sclera, iris, lips, teeth, hair, clothes), Objects, brush, linear/radial gradient, color/luminance/depth range.
- **Remove:** heal, generative remove, "Detect objects" that also catches shadows/reflections (July 2026),
  AI blemish detection inside Retouch (Aug 2026), Generative Expand beyond the borders (Aug 2026).
- **Presets:** Adaptive presets (Portrait/Sky/Subject; 8 new Adaptive: Landscape in July 2026), film-style presets
  (Aug 2026), "Trending" preset discovery, copy/paste edits, versions, batch edit, RAW/HDR, export options.
- Extra 2026 features: AI Photo-to-Video, natural-language photo search.

### Google Snapseed 3.x (the "tools" reference)
- 3.0 (June 2025) redesign: **Looks / Faves / Tools** tabs, pin favourite tools, film looks, built-in film camera
  (Portra, Superia, Polaroid simulations). 3.5 reportedly added object masking.
- **Retouch & Transform:** Selective (control points), Brush, Healing, Portrait (face spotlight, skin smoothing,
  eye clarity), Crop, Perspective, Expand (content-aware), Head Pose.
- **Style:** Film, Glow (Glamour Glow), Retrolux, Vintage, Black & White, HDR Scape, Drama, Noir, Grunge
  (+ classic Tune Image, Details/Structure, Curves, White Balance, Tonal Contrast, Lens Blur, Vignette).
- **Creative:** Double Exposure, Frames, Text. Edit "stacks" that can be re-opened and modified.

### Tezza (the "aesthetic" reference)
- 40+ curated presets (vintage, dark & moody, minimal, bright & colourful).
- **Overlays:** Paper, Dust, Light, Plastic, Shadows. **Retro film frames:** Super 8, VHS, 8mm, Kodak, VCR.
- 14 adjustment tools incl. HSL, Grain, Blur, Fade.
- 150+ templates (film, editorial, magazine, 90s, Y2K, floral, moodboard, minimal, sketch) with text and colours.
- Feed planner (Instagram grid preview), batch editing, video editing.

### Facetune / Meitu / BeautyPlus / YouCam (the "face & beauty" reference)
- Skin smoothing, tone, blemish/heal, teeth whitening, eye whitening/colour, face reshape (slim, jaw, nose, lips, eyes).
- **Eyebrows (Facetune):** Thick (fullness slider), Lift, Shape (arch), Trim; under the Hair menu with thin/thick/full.
- **Makeup:** lip colour, blush, eyeshadow, lashes ("Vivid Makeup"), paint & heal tools.
- Hair colour changer and hairstyle try-on (BeautyPlus, YouCam).
- Common complaint: over-processed "plastic mask" results → our skin tools must preserve texture.

### Peachy / Body Tune / Facetune body (the "body" reference)
- Waist slimmer, hip enhancement, butt enlarge/lift, thigh thinning, leg lengthening, height increase,
  posture correction, auto body reshape ("AI Body Edit").
- **Muscles:** "AI Muscle" (Peachy) for abs, V-line, chest, bust, arms; Body Tune ships preset six-pack designs.
- Tattoo stickers, skin smoothing, background cutout.

---

## 2. Unified feature catalogue (what our app will include)

Priority: **P0** = core/MVP, **P1** = important, **P2** = nice to have. The plan document maps each to a phase.

| Area | Features | Inspired by | Priority |
|---|---|---|---|
| Library & workflow | Photos import (full res, HEIC, RAW/ProRAW/DNG), projects with non-destructive history, undo/redo, before/after (hold + split), versions, copy/paste edits, batch apply, favourite tools | LR, Snapseed | P0 |
| Light | Auto, exposure, contrast, highlights, shadows, whites, blacks, brightness, point & parametric curves (RGB/R/G/B), histogram + clipping | LR | P0 |
| Color | WB temp/tint + eyedropper, vibrance, saturation, HSL mixer (8 bands), 3-way color grading, B&W mixer, point color, calibration | LR | P0/P1 |
| Effects | Texture, clarity, dehaze, vignette, grain (amount/size/roughness), fade, glow/bloom, halation, blur, RGB split | LR, Tezza | P0 |
| Detail & optics | Sharpen (amount/radius/detail/masking), noise reduction (luma/chroma), AI denoise, lens distortion, CA removal | LR | P1 |
| Geometry | Crop with aspect presets, straighten + auto-horizon, rotate/flip, perspective (vertical/horizontal), auto upright, expand canvas with content fill | LR, Snapseed | P0/P1 |
| Presets & looks | 80+ built-in looks (film, moody, vintage, bright, B&W, Tezza-style), strength slider, LUT (.cube) engine + import, user presets, adaptive (subject/sky-aware) presets | LR, Tezza, Snapseed | P0 |
| Masking | Subject, background, sky, people + parts (face skin, body skin, brows, eyes, lips, teeth, hair, clothes), tap-to-select object, brush (auto-edge), linear/radial gradients, color/luminance/depth range, add/subtract/intersect/invert, control points | LR, Snapseed | P1 |
| Retouch & remove | Heal, clone, AI object removal, auto blemish detection, people/distraction removal, red-eye | LR, Snapseed, Facetune | P1 |
| Face beauty | Auto beauty; skin smooth (texture-preserving), even tone, blemishes, shine, wrinkles, dark circles; face shape (slim, jaw, chin, forehead, cheekbones, length); eyes (size, distance, brighten, whiten, iris color); nose (width, length, tip); lips (fullness, width, smile) | Facetune, Meitu | P0/P1 |
| Eyebrows | Thicken/fill, lift, arch/shape, tilt, distance, darken/tint, trim/erase, brow style templates | Facetune | P1 |
| Makeup | Lipstick (matte/satin/gloss), blush, contour, highlight, eyeshadow, eyeliner, lashes, foundation | Facetune, YouCam | P1 |
| Teeth & hair | Teeth whitening, hair recolor/highlights | Facetune, BeautyPlus | P1 |
| Body | Auto slim; waist, hips, butt (enlarge/lift), bust/chest, thighs, legs lengthen, height, arms, shoulders, neck, belly flatten; manual push/bloat/pinch/restore + protect mask; background protection | Peachy, Body Tune, Facetune | P0/P1 |
| Muscles & body skin | Abs (6-pack, 8-pack, "11 line"), V-line, pecs, arms definition; body skin smooth, tan, cellulite smoothing, tattoo stickers | Peachy, Body Tune | P1 |
| Creative styles | HDR Scape, Drama, Glamour Glow, Tonal Contrast, Grunge, Retrolux, Vintage, Noir, Grainy Film, Lens Blur (depth bokeh), Tilt-shift, Double Exposure | Snapseed | P1 |
| Aesthetic | Overlays (dust, scratches, light leaks, paper, plastic, shadows, prism), retro frames (VHS, Super 8, 8mm, Kodak, Polaroid), date stamp, text + fonts, stickers, templates (story/collage/moodboard), feed planner | Tezza | P1/P2 |
| AI enhance | One-tap enhance, upscale ×2/×4, low-light, face restoration, colorize old photos, background remove/replace/blur, sky replacement | various | P2 |
| Export | JPEG/HEIC/PNG/TIFF-16, size, quality, metadata on/off, watermark, share sheet, batch export | LR | P0 |
| Out of scope v1 | Video editing, cloud sync, generative (diffusion) fill — possible later phases | Tezza, LR | — |

---

## 3. Technology findings

### Apple frameworks (all on-device, free, no API costs)
- **Core Image**: 200+ built-in filters, lazy GPU graph with tiling (handles 48 MP), `CIRAWFilter` for RAW/ProRAW,
  custom kernels written in Metal (color, warp and general kernels). This is the right engine for a
  Lightroom-quality non-destructive pipeline in 16-bit float linear colour.
- **Vision** (requests usable on iOS 17+):
  - Face rectangles + **76-point face landmarks** (brows, eyes, pupils, nose, lips, face contour), face capture quality.
  - **Person segmentation** (accurate mode), **person instance masks** (separate people), **foreground/subject instance mask**.
  - **2D body pose (19 joints)** and 3D body pose; hand pose.
  - Horizon detection (auto-straighten), saliency (auto-crop), rectangles (perspective), image aesthetics score (iOS 18).
  - iOS 18/26 add a Swift-native async API next to the classic `VN…` classes.
- **Core ML** runs converted models on the Neural Engine. Apple announced **Core AI** at WWDC26 (iOS 27) as the
  successor; Core ML keeps working, so we use Core ML (supports our iOS 17+ target).
- **Metal / MetalKit** for the live preview canvas; **PhotoKit** for library access and saving.

### On-device AI models (pre-converted to Core ML)
| Model | Use in app | Size | License | Notes |
|---|---|---|---|---|
| Face Parsing (BiSeNet, 19 classes) | Face skin, brows, eyes, lips, mouth, hair, neck, clothes masks | 47 MB zip | MIT | iOS 17+, 512×512, ~300 MB peak RAM |
| LaMa | Object removal, blemish fill, background fill behind reshaped body, expand | ~187 MB | Apache-2.0 | iOS 17+, 800×800, ~600 MB peak RAM |
| Real-ESRGAN ×4 | AI upscale / enhance | 59 MB zip | BSD-3 | 512→2048 tiles, ~500 MB peak RAM |
| Depth Anything V2 Small (Apple) | Lens blur / bokeh, depth-range masks | ~50 MB (F16) | Apache-2.0 | Official Apple HF repo |
| MobileSAM | Tap-to-select any object (mask) | 23 MB | Apache-2.0 | |
| Clothes segmentation | Clothes mask | 50 MB | MIT | |
| U²-Net-p | Saliency / subject fallback | 4.6 MB | Apache-2.0 | |
| GFPGAN | Face restoration (old/blurry photos) | 337 MB | Apache-2.0 | Heavy → optional download |
| EasyPortrait | Teeth / lips / brows masks (separates teeth from mouth) | 7.6 MB | CC (verify) | Licence to confirm |
| Zero-DCE / DDColor-tiny | Low-light / colorize | <20 MB | verify | Optional |

Licences to **avoid** if the app may ever be sold: RMBG-1.4 (non-commercial), CodeFormer (non-commercial),
NVIDIA SegFormer weights (non-commercial), UltraSharp (CC-BY-NC). Apple's Vision subject mask covers background removal.

**No good ready-made sky model was found** → sky mask via Vision horizon + colour/position/depth heuristics first;
revisit with a dedicated model later.

**MediaPipe** (478-point face mesh, multiclass selfie segmentation) is only distributed via CocoaPods for iOS,
and CocoaPods' central repo becomes read-only in Dec 2026 → we avoid it and use Vision + Core ML.

### How the best apps get "natural" results (techniques we'll use)
- **Pipeline:** decode → linear wide-gamut float16 → retouch → geometry warps → beauty → tone/color → local masks →
  detail → effects/looks → crop → frames/text. Preview renders a screen-sized proxy; export re-renders at full resolution.
- **Tone:** highlights/shadows with edge-aware (guided filter) local tone mapping, not a plain curve → no halos.
  Clarity/texture = multi-scale local contrast. Dehaze = dark-channel prior + guided refinement.
- **Skin:** frequency separation with an edge-preserving low-pass, applied only inside the skin mask, keeping
  high-frequency pore texture (slider) and matching grain → avoids the "plastic" look users complain about.
- **Masks:** ML masks are computed at ~1–1.5 MP and refined to full resolution with a guided filter (crisp hair edges).
- **Face & body reshape:** landmark/pose-driven **Moving Least Squares** (rigid) warps (Schaefer et al. 2006) baked
  into one displacement field; warps are limited to the person (mask + feather) and the background revealed by
  slimming is filled with LaMa ("background protection"), so walls and door frames don't bend.
- **Muscles/abs:** procedural dodge & burn shading templates (six-pack, eight-pack, 11-line, pecs, arms) placed by
  body-pose keypoints, adjustable handles, modulated by skin mask and local skin tone (Peachy/Body Tune approach).
- **Eyebrows:** brow mask (face parsing ∩ landmarks) → tint/darken; fill/thicken by dilating the mask and drawing
  hair strands along the brow direction in the sampled brow colour; lift/arch/shape via MLS on brow landmarks;
  trim/erase via inpaint.
- **Makeup:** colours blended in Lab/luminance-preserving modes so texture stays; gloss = specular boost on lips.
- **Looks/presets:** parametric presets (our own adjustment values) + 3D LUTs (65³, .cube) with strength slider.

---

## 4. Build & distribution constraints (Windows-only, no Mac)

- iOS apps must be compiled with Xcode on macOS → we use **cloud Macs (GitHub Actions)**. The Xcode project is
  generated from a text file (**XcodeGen**, `project.yml`), so no Mac is ever needed locally.
- GitHub-hosted runners: `macos-26` image with Xcode 26.6 default (Aug 2026), Xcode 27 preview image available.
- **Cost (private repo):** Free plan = 2,000 included minutes, but macOS minutes count **×10** → ≈ **200 macOS
  minutes/month** (~20–30 builds). Extra macOS minutes cost **$0.062/min** (after the Jan 2026 price cut).
  Public repos are free and unlimited.
- **Codemagic** (second free option): 500 free macOS M2 minutes/month for personal accounts; then $0.095/min.
- **Installing on iPhone without paid membership:** CI produces an unsigned `.ipa`; **Sideloadly** (Windows) signs it
  with a free Apple ID. Limits: app expires after **7 days** (re-sign), **3 sideloaded apps** at once,
  ~**10 App IDs per week** (keep bundle ID stable), iPhone needs **Developer Mode** (iOS 16+).
  Free Apple IDs cannot use iCloud/push entitlements → the app is designed to need none.
- Upgrading to the $99/yr Apple Developer Program later unlocks TestFlight, no expiry, App Store release.

---

## Sources
- [Adobe Lightroom mobile release notes](https://helpx.adobe.com/ro/lightroom/mobile/whats-new/adobe-lightroom-on-mobile-release-notes.html)
- [9to5Google — Snapseed 3.0 for iPhone](https://9to5google.com/2025/06/12/snapseed-3-0-update-iphone/) · [AlternativeTo — Snapseed 3.0](https://www.alternativeto.net/news/2025/6/snapseed-3-0-for-ios-launches-with-new-interface-and-vintage-filters/) · [Wikipedia — Snapseed](https://en.wikipedia.org/wiki/Snapseed)
- [Tezza on the App Store](https://apps.apple.com/app/id1393061654)
- [Facetune — eyebrow editor](https://www.facetuneapp.com/blog/eyebrow-editor-app-how-to-edit-eyebrows-in-photo) · [Facetune — lash & brow guide](https://facetuneapp.com/blog/mastering-lash-brow-styling-techniques-trends) · [Facetune — best body editing apps](https://website.facetuneapp.com/blog/best-body-editing-app)
- [Body Tune on the App Store](https://apps.apple.com/app/1222515036) · [Peachy on the App Store](https://apps.apple.com/us/app/peachy-ai-face-body-editor/id1390423469) · [Peachy on Google Play](https://play.google.com/store/apps/eventdetails/4830922711856896111)
- [BeautyPlus — apps like FaceApp](https://beautyplus.com/academy/apps-like-faceapp) · [YouCam Makeup on the App Store](https://apps.apple.com/us/app/%E7%8E%A9%E7%BE%8E%E5%BD%A9%E5%A6%9D-ai-%E7%BE%8E%E9%A1%8F%E7%9B%B8%E6%A9%9F-%E9%AB%AE%E5%9E%8B%E6%A8%A1%E6%93%AC%E7%A5%9E%E5%99%A8/id863844475?l=vi)
- [Vision framework overview (Blake Crosley)](https://blakecrosley.com/blog/vision-framework-built-in) · [Kodeco — Vision framework](https://www.kodeco.com/ios/programs/apple-intelligence/apple-ai-models/49307523-vision-framework/01-diving-into-the-vision-framework/02) · [WWDC22 — Vision](https://developer.apple.com/videos/play/wwdc2022/10024/)
- [9to5Mac — Core AI replacing Core ML](https://9to5mac.com/2026/03/01/apple-replacing-core-ml-with-modernized-core-ai-framework-for-ios-27-at-wwdc/) · [Adjust — WWDC26](https://www.adjust.com/blog/WWDC-26/)
- [MediaPipe Face Landmarker for iOS](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios) · [MediaPipe Image Segmenter for iOS](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter/ios)
- [Face Parsing Core ML](https://huggingface.co/mlboydaisuke/Face-Parsing-CoreML) · [LaMa Core ML](https://huggingface.co/mlboydaisuke/LaMa-CoreML) · [Real-ESRGAN ×4 Core ML](https://huggingface.co/mlboydaisuke/Real-ESRGAN-x4-CoreML) · [Apple Depth Anything V2 Core ML](https://huggingface.co/apple/coreml-depth-anything-v2-small/tree/4a62b07ef101515b5f5b399ba2c281cf36a9d301) · [john-rocky/CoreML-Models](https://github.com/john-rocky/CoreML-Models) · [LaMa (official)](https://github.com/advimman/lama)
- [EasyPortrait paper](https://arxiv.org/abs/2304.13509v3)
- [Schaefer et al. — Image deformation using Moving Least Squares](https://history.siggraph.org/?p=113538) · [Parametric reshaping of human bodies in images](https://history.siggraph.org/?p=106004) · [Structure-aware body reshaping](https://arxiv.org/pdf/2404.13983)
- [GitHub Actions runner pricing](https://docs.github.com/en/enterprise-server@3.17/billing/reference/actions-runner-pricing) · [cicdcalculator — GitHub Actions](https://cicdcalculator.com/github-actions) · [Bitrise — runner pricing traps 2026](https://bitrise.io/blog/post/best-github-actions-runners-in-2026-and-hidden-pricing-traps-to-avoid) · [macos-26 runner image notes](https://newreleases.io/project/github/actions/runner-images/release/macos-26%2F20260805.0449)
- [Codemagic pricing docs](https://docs.codemagic.io/billing/pricing/)
- [Corellium — Sideloadly](https://support.corellium.com/features/apps/sideloadly) · [OWASP MASTG — Sideloadly](https://mas.owasp.org/MASTG/tools/ios/MASTG-TOOL-0118/) · [dev.to — IPA builds on GitHub Actions](https://dev.to/samay15jan/breaking-into-apples-walled-garden-almost-4a8m)
