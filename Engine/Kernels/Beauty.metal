#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraBLuma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static inline float lumoraBToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraBToLinear(float x) { return pow(max(x, 0.0f), 2.2f); }
static inline float lumoraBCbrt(float x) { return sign(x) * pow(fabs(x), 1.0f / 3.0f); }

static inline float3 lumoraBToOklab(float3 c) {
    float l = lumoraBCbrt(0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b);
    float m = lumoraBCbrt(0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b);
    float s = lumoraBCbrt(0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b);
    return float3(0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s,
                  1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s,
                  0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s);
}

static inline float3 lumoraBFromOklab(float3 lab) {
    float l = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3(4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
                 -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
                 -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
}

extern "C" { namespace coreimage {

// Face retouch for one face. Inputs are pixel-aligned over the face region:
// base: guided coefficients (a, b) of perceptual luma (edge-aware local mean, coarse scale)
// fine: Gaussian of perceptual luma (fine scale); chroma: blurred OKLab (for even tone)
// masksA: (skin, lips, mouth interior); masksB: (eyes, iris, under-eye)
// skinParams: (smooth, keep texture, even tone, shine) 0...1
// featureParams: (dark circles, teeth, eye brighten, eye whiten) 0...1
// iris: (amount 0...1, target a direction, target b direction, 0)
// tone: average skin (L, a, b) in OKLab
float4 lumora_faceRetouch(sample_t s, sample_t base, sample_t fine, sample_t chroma, sample_t masksA, sample_t masksB,
                          float4 skinParams, float4 featureParams, float4 iris, float4 tone) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraBLuma(c);
    float p = lumoraBToPerceptual(y);
    float3 lab = lumoraBToOklab(c);

    // Skin probability: inside the face mask and close to the measured skin tone. Uses the
    // smoothed color so film grain / sensor noise doesn't break the match pixel by pixel.
    // The face mask does the main work; color only refines it (strong side light can make one
    // cheek much warmer than the face's average, so the match is a soft weight, not a gate).
    float chromaDistance = length(chroma.yz - tone.yz);
    float colorMatch = 1.0f - smoothstep(0.08f, 0.2f, chromaDistance);
    float lightMatch = smoothstep(tone.x - 0.4f, tone.x - 0.22f, chroma.x);
    float skin = masksA.r * mix(0.45f, 1.0f, colorMatch * lightMatch) * smoothstep(0.1f, 0.3f, lightMatch + colorMatch);

    // Frequency separation: low (edge-aware, guided by the slightly blurred luma so it holds no
    // grain) + mid (blotches) + high (pores).
    float low = base.r * fine.r + base.g;
    float mid = fine.r - low;
    float high = p - fine.r;
    float smooth = skinParams.x * skin;
    float p2 = p - smooth * mid * 0.95f - smooth * (1.0f - skinParams.y) * high;

    // Shine: bright, low-chroma spots on skin pulled toward the local mean.
    float shiny = smoothstep(0.02f, 0.12f, p - low) * (1.0f - smoothstep(0.05f, 0.12f, length(lab.yz)));
    p2 -= skinParams.w * skin * shiny * (p2 - low) * 0.85f;

    float y2 = lumoraBToLinear(max(p2, 0.0f));
    c = y > 1.0e-6f ? c * (y2 / y) : float3(y2);
    lab = lumoraBToOklab(c);

    // Even tone: blend skin chroma toward its smoothed version (redness, blotches).
    lab.yz = mix(lab.yz, chroma.yz, skinParams.z * skin * 0.9f);

    // Dark circles: lift and neutralize the under-eye area toward the cheek tone.
    float circles = featureParams.x * masksB.b * (1.0f - masksB.r);
    lab.x = mix(lab.x, max(lab.x, tone.x * 0.97f), circles * 0.75f);
    lab.yz = mix(lab.yz, tone.yz, circles * 0.45f);

    // Teeth: inside the mouth, bright pixels lose yellow and gain a little light.
    float teeth = masksA.b * smoothstep(tone.x - 0.12f, tone.x + 0.06f, lab.x) * featureParams.y;
    lab.z -= max(lab.z, 0.0f) * teeth * 0.85f;
    lab.y *= 1.0f - teeth * 0.5f;
    lab.x += teeth * 0.07f * max(1.0f - lab.x, 0.0f);

    // Eyes: brighten + a touch of local contrast; whiten the sclera (bright, outside the iris).
    float eye = masksB.r;
    lab.x += featureParams.z * eye * (0.07f * max(1.0f - lab.x, 0.0f) + 0.35f * (p - fine.r));
    float sclera = eye * (1.0f - masksB.g) * smoothstep(0.45f, 0.7f, lab.x);
    lab.yz *= 1.0f - featureParams.w * sclera * 0.8f;
    lab.x += featureParams.w * sclera * 0.05f * max(1.0f - lab.x, 0.0f);

    // Iris color: keep lightness and texture, rotate chroma toward the target hue.
    float irisWeight = iris.x * masksB.g * eye * smoothstep(0.12f, 0.25f, lab.x) * (1.0f - smoothstep(0.7f, 0.85f, lab.x));
    float irisChroma = max(length(lab.yz), 0.07f);
    lab.yz = mix(lab.yz, iris.yz * irisChroma * 1.15f, irisWeight);

    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Eyebrows and makeup for one face. Masks are pixel-aligned over the face region:
// masksA (skin, lips, mouth), masksB (eyes, iris, under-eye), masksC (blush, contour, highlight),
// masksD (eyeshadow, brow distance field, -), masksE (eyeliner, lashes, brow core).
// lip: (amount, L, a, b) target; lipFinish: (gloss, shimmer, matte, 0); lipTone: average lip (L, a, b)
// blush: (amount, L, a, b); sculpt: (contour, highlight, 0, 0); shadow: (amount, L, a, b)
// liner: (eyeliner, lashes, 0, 0); brow: (thickness, color amount, 0, 0); browColor/browTone: (L, a, b)
// tone: average skin (L, a, b). All amounts 0...1.
float4 lumora_makeup(sample_t s, sample_t masksA, sample_t masksB, sample_t masksC, sample_t masksD, sample_t masksE,
                     float4 lip, float4 lipFinish, float4 lipTone, float4 blush, float4 sculpt, float4 shadow,
                     float4 liner, float4 brow, float4 browColor, float4 browTone, float4 tone) {
    float3 c = max(s.rgb, float3(0.0f));
    float3 lab = lumoraBToOklab(c);
    float originalL = lab.x;
    float skin = masksA.r;

    // Lipstick: lightness follows the photo's lighting (shift relative to the lips' average),
    // chroma follows the local shading, and the lips' own texture is kept.
    float lips = masksA.g * lip.x;
    if (lips > 0.0f) {
        float shade = clamp(originalL / max(lipTone.x, 0.05f), 0.55f, 1.35f);
        float paintedL = originalL + (lip.y - lipTone.x) * 0.6f;
        paintedL = mix(paintedL, lipTone.x + (lip.y - lipTone.x) * 0.6f, lipFinish.z * 0.3f);
        float2 paintedAB = lip.zw * 0.85f * shade + (lab.yz - lipTone.yz) * 0.3f;
        lab = mix(lab, float3(paintedL, paintedAB), lips * 0.8f);
        float shine = smoothstep(lipTone.x + 0.04f, lipTone.x + 0.16f, originalL);
        float gloss = (lipFinish.x + lipFinish.y * 0.6f) * lips * shine;
        lab.x += gloss * 0.12f * max(1.0f - lab.x, 0.0f);
        lab.yz *= 1.0f - gloss * 0.25f;
    }

    // Blush: tint the cheek apples toward the blush color.
    float blushWeight = masksC.r * blush.x * skin;
    lab.yz = mix(lab.yz, blush.zw, blushWeight * 0.32f);
    lab.x = mix(lab.x, blush.y, blushWeight * 0.08f);

    // Contour (cool-neutral shadow) and highlight (soft sheen).
    float contourWeight = masksC.g * sculpt.x * skin;
    lab.x *= 1.0f - contourWeight * 0.14f;
    lab.yz = mix(lab.yz, tone.yz * 0.85f, contourWeight * 0.2f);
    float highlightWeight = masksC.b * sculpt.y * skin;
    lab.x += highlightWeight * 0.09f * max(1.0f - lab.x, 0.0f);
    lab.yz *= 1.0f - highlightWeight * 0.12f;

    // Eyeshadow on the lids (never on the eye itself).
    float shadowWeight = masksD.r * shadow.x * (1.0f - masksB.r);
    float3 shaded = float3(shadow.y + (lab.x - tone.x) * 0.6f, shadow.zw);
    lab = mix(lab, shaded, shadowWeight * 0.6f);

    // Eyeliner and lashes: deep near-black lines.
    float lineWeight = max(masksE.r * liner.x, masksE.g * liner.y) * (1.0f - masksB.r * 0.4f);
    lab.x = mix(lab.x, 0.1f, lineWeight * 0.9f);
    lab.yz *= 1.0f - lineWeight * 0.85f;

    // Brows: thicken by darkening a thin band around the brow toward the brow's color, keeping
    // the skin's own fine variation as texture; then tint only the darker (hair) pixels.
    float field = masksD.g;
    float threshold = 1.0f - brow.x * 0.4f;
    float fill = smoothstep(threshold, threshold + 0.15f, field) * (1.0f - masksE.b) * step(0.001f, brow.x);
    float3 filled = float3(browTone.x + (originalL - tone.x) * 0.5f, browTone.yz);
    lab = mix(lab, filled, fill * 0.5f);
    float hairness = smoothstep(tone.x - 0.04f, tone.x - 0.22f, lab.x);
    float browArea = clamp(masksE.b * hairness + fill * 0.6f, 0.0f, 1.0f) * brow.y;
    float3 tinted = float3(lab.x + (browColor.x - browTone.x) * 0.7f, browColor.yz + (lab.yz - browTone.yz) * 0.4f);
    lab = mix(lab, tinted, browArea * 0.65f);

    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Hair recolor around one head. person: person segmentation (r); head: head area (r);
// faceArea: solid face mask (r) to keep the face, eyes and lips untouched.
// target: (amount, L, a, b); hairTone/tone: average hair and skin (L, a, b).
// trust = 1: `person` is already a hair mask (photo matte or grown mask); use it as is.
float4 lumora_hairColor(sample_t s, sample_t person, sample_t head, sample_t faceArea, float4 target, float4 hairTone, float4 tone, float trust) {
    float3 c = max(s.rgb, float3(0.0f));
    float3 lab = lumoraBToOklab(c);
    float skinLike = (1.0f - smoothstep(0.04f, 0.09f, length(lab.yz - tone.yz))) * smoothstep(tone.x - 0.3f, tone.x - 0.15f, lab.x);
    // Similar to the sampled hair color (lightness counts half, so highlights/shadows still match).
    float3 diff = lab - hairTone.xyz;
    float hairDistance = length(float3(diff.x * 0.5f, diff.yz));
    float hairLike = 1.0f - smoothstep(0.1f, 0.2f, hairDistance);
    float hair = trust > 0.5f
        ? person.r * (1.0f - faceArea.r)
        : person.r * head.r * hairLike * (1.0f - skinLike * 0.9f) * (1.0f - faceArea.r);
    float weight = hair * target.x;
    if (weight <= 0.0f) { return s; }
    // Shift lightness toward the target, keep strand-level variation.
    float newL = lab.x + (target.y - hairTone.x) * 0.75f;
    float targetChroma = length(target.zw);
    float2 direction = targetChroma > 1.0e-4f ? target.zw / targetChroma : float2(0.0f);
    float relative = clamp(lab.x / max(target.y, 0.05f), 0.3f, 1.6f);
    float3 recolored = float3(max(newL, 0.0f), direction * targetChroma * (0.55f + 0.45f * relative));
    lab = mix(lab, recolored, weight);
    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Body skin and muscle definition for one person (inputs pixel-aligned over the person's region).
// person: person mask (r); shading: muscle lighting (r = highlight, g = shadow, already scaled);
// base/fine/chroma: as in face retouch; lowerBody: 1 below the hips (cellulite area).
// skinParams: (smooth, tan, cellulite, 0) 0...1; tone: torso skin (L, a, b).
float4 lumora_bodySkin(sample_t s, sample_t person, sample_t shading, sample_t base, sample_t fine, sample_t chroma, sample_t lowerBody,
                       float4 skinParams, float4 tone) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraBLuma(c);
    float p = lumoraBToPerceptual(y);
    float colorMatch = 1.0f - smoothstep(0.06f, 0.14f, length(chroma.yz - tone.yz));
    float lightMatch = smoothstep(tone.x - 0.4f, tone.x - 0.22f, chroma.x) * (1.0f - smoothstep(tone.x + 0.22f, tone.x + 0.38f, chroma.x));
    float skin = person.r * colorMatch * lightMatch;
    if (skin <= 0.0f) { return s; }

    float low = base.r * fine.r + base.g;
    float mid = fine.r - low;
    float high = p - fine.r;
    float smooth = skin * clamp(skinParams.x + skinParams.z * lowerBody.r, 0.0f, 1.0f);
    float p2 = p - smooth * mid * 0.9f - skinParams.x * skin * high * 0.3f;

    // Muscle relief: lift the lit edges, deepen the grooves (multiplicative, keeps skin texture).
    // Shadows on skin turn a little warmer and redder rather than grey, like real skin.
    float shade = shading.g * skin;
    float light = shading.r * skin;
    p2 *= 1.0f + light * 0.08f - shade * 0.26f;

    float y2 = lumoraBToLinear(max(p2, 0.0f));
    c = y > 1.0e-6f ? c * (y2 / y) : float3(y2);

    float3 lab = lumoraBToOklab(c);
    lab.y += shade * 0.012f;
    lab.z += shade * 0.006f;
    lab.yz *= 1.0f - light * 0.08f;
    float tan = skinParams.y * skin;
    lab.x *= 1.0f - tan * 0.16f;
    lab.yz += float2(0.02f, 0.045f) * tan;
    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Hair ombré and shine on a hair mask. ramp: 0 at the top of the hair, 1 at the bottom.
// params = (shine, ombré, 0, 0); ombre = (0, L, a, b) of the ombré color; hairTone = hair (L, a, b).
float4 lumora_hairStyle(sample_t s, sample_t mask, sample_t faceArea, sample_t blurred, sample_t ramp, float4 params, float4 ombre, float4 hairTone) {
    float m = clamp(mask.r, 0.0f, 1.0f) * (1.0f - clamp(faceArea.r, 0.0f, 1.0f));
    if (m <= 0.0f) { return s; }
    float3 lab = lumoraBToOklab(max(s.rgb, float3(0.0f)));
    // Ombré: the lengths take the second color; lightness follows the hair's own strands.
    float t = smoothstep(0.3f, 0.85f, ramp.r) * params.y * m;
    if (t > 0.0f) {
        float relative = clamp(lab.x / max(hairTone.x, 0.05f), 0.4f, 1.8f);
        float targetChroma = length(ombre.zw);
        float2 direction = targetChroma > 1.0e-4f ? ombre.zw / targetChroma : float2(0.0f);
        float3 target = float3(ombre.y * mix(1.0f, relative, 0.7f), direction * targetChroma * (0.55f + 0.45f * relative));
        lab = mix(lab, target, t);
    }
    // Shine: stronger strand detail and a lift of the hair's own highlights.
    float3 soft = lumoraBToOklab(max(blurred.rgb, float3(0.0f)));
    float detail = lab.x - soft.x;
    lab.x += params.x * m * (detail * 1.1f + 0.07f * smoothstep(0.0f, 0.06f, detail));
    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Red-eye: inside the iris/pupil mask (masksB.g), strongly red pixels become dark and neutral.
float4 lumora_redEye(sample_t s, sample_t masksB, float amount) {
    float m = masksB.g;
    if (m <= 0.0f) { return s; }
    float3 lab = lumoraBToOklab(max(s.rgb, float3(0.0f)));
    float redness = smoothstep(0.05f, 0.12f, lab.y) * smoothstep(0.0f, 0.04f, lab.y - fabs(lab.z) * 0.5f);
    float w = clamp(m * redness * amount, 0.0f, 1.0f);
    float3 fixedLab = float3(lab.x * 0.45f, lab.yz * 0.1f);
    lab = mix(lab, fixedLab, w);
    return float4(max(lumoraBFromOklab(lab), float3(0.0f)), s.a);
}

// Backward warp: each output pixel samples the input at its position plus the displacement
// field (normalized offsets in .rg, multiplied by the image size).
float4 lumora_displace(sampler src, sampler field, float2 imageSize, destination dest) {
    float2 position = dest.coord();
    float2 offset = field.sample(field.transform(position)).rg * imageSize;
    return src.sample(src.transform(position + offset));
}

}}
