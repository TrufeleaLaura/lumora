#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraMLuma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static inline float lumoraMToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraMCbrt(float x) { return sign(x) * pow(fabs(x), 1.0f / 3.0f); }

static inline float3 lumoraMToOklab(float3 c) {
    float l = lumoraMCbrt(0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b);
    float m = lumoraMCbrt(0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b);
    float s = lumoraMCbrt(0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b);
    return float3(0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s,
                  1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s,
                  0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s);
}

static inline float4 lumoraMGray(float v) {
    float w = clamp(v, 0.0f, 1.0f);
    return float4(w, w, w, 1.0f);
}

// Weight of a pixel's color against one sampled OKLab color (sample.w > 0.5 = in use).
static inline float lumoraMColorWeight(float3 lab, float4 sample, float tolerance) {
    if (sample.w < 0.5f) { return 0.0f; }
    float3 d = lab - sample.xyz;
    float distance = length(float3(d.x * 0.6f, d.yz));
    return 1.0f - smoothstep(tolerance, tolerance * 1.8f + 0.01f, distance);
}

extern "C" { namespace coreimage {

// Linear gradient (pixel coordinates): 1 on the start side, smoothly 0 past the end.
float4 lumora_linearMask(float2 start, float2 end, destination dest) {
    float2 axis = end - start;
    float t = clamp(dot(dest.coord() - start, axis) / max(dot(axis, axis), 1.0e-6f), 0.0f, 1.0f);
    float s = 1.0f - t;
    return lumoraMGray(s * s * (3.0f - 2.0f * s));
}

// Radial gradient: shape = (center x, center y, radius x, radius y) in pixels,
// params = (cos angle, sin angle, feather 0...1, 0). 1 inside, 0 outside.
float4 lumora_radialMask(float4 shape, float4 params, destination dest) {
    float2 p = dest.coord() - shape.xy;
    float2 local = float2(p.x * params.x + p.y * params.y, -p.x * params.y + p.y * params.x);
    float2 r = max(shape.zw, float2(1.0e-3f));
    float d = length(local / r);
    float inner = 1.0f - clamp(params.z, 0.0f, 1.0f);
    if (d <= inner) { return lumoraMGray(1.0f); }
    float t = clamp((d - inner) / max(1.0f - inner, 1.0e-4f), 0.0f, 1.0f);
    float u = 1.0f - t;
    return lumoraMGray(u * u * (3.0f - 2.0f * u));
}

// Colors close to up to five sampled colors (OKLab, w = 1 when used); tolerance in OKLab units.
float4 lumora_colorRangeMask(sample_t s, float4 c0, float4 c1, float4 c2, float4 c3, float4 c4, float tolerance) {
    float3 lab = lumoraMToOklab(max(s.rgb, float3(0.0f)));
    float w = lumoraMColorWeight(lab, c0, tolerance);
    w = max(w, lumoraMColorWeight(lab, c1, tolerance));
    w = max(w, lumoraMColorWeight(lab, c2, tolerance));
    w = max(w, lumoraMColorWeight(lab, c3, tolerance));
    w = max(w, lumoraMColorWeight(lab, c4, tolerance));
    return lumoraMGray(w);
}

// Brightness range on perceptual luminance: params = (low, high, feather, 0).
float4 lumora_luminanceMask(sample_t s, float4 params) {
    float p = lumoraMToPerceptual(lumoraMLuma(max(s.rgb, float3(0.0f))));
    float f = max(params.z, 1.0e-3f);
    float w = smoothstep(params.x - f, params.x, p) * (1.0f - smoothstep(params.y, params.y + f, p));
    return lumoraMGray(w);
}

// Combines a component into the running mask. mode: (0 add / 1 subtract / 2 intersect, invert, 0, 0).
float4 lumora_maskCombine(sample_t current, sample_t component, float4 mode) {
    float a = current.r;
    float b = mode.y > 0.5f ? 1.0f - component.r : component.r;
    float result;
    if (mode.x < 0.5f) {
        result = max(a, b);
    } else if (mode.x < 1.5f) {
        result = a * (1.0f - b);
    } else {
        result = a * b;
    }
    return lumoraMGray(result);
}

// 1 - mask.
float4 lumora_maskInvert(sample_t mask) {
    return lumoraMGray(1.0f - mask.r);
}

// Product of two masks.
float4 lumora_maskMultiply(sample_t a, sample_t b) {
    return lumoraMGray(a.r * b.r);
}

// Edge-aware mask from guided-filter coefficients (a, b) and the image's perceptual luminance.
float4 lumora_guidedMask(sample_t s, sample_t coefficients) {
    float p = lumoraMToPerceptual(lumoraMLuma(max(s.rgb, float3(0.0f))));
    return lumoraMGray(coefficients.r * p + coefficients.g);
}

// Blends the adjusted image over the original where the mask is set.
float4 lumora_maskBlend(sample_t original, sample_t adjusted, sample_t mask, float amount) {
    float w = clamp(mask.r * amount, 0.0f, 1.0f);
    return mix(original, adjusted, w);
}

// Mask preview: tints the photo where the mask is set. color = (r, g, b, opacity).
float4 lumora_maskOverlay(sample_t image, sample_t mask, float4 color) {
    float w = clamp(mask.r, 0.0f, 1.0f) * color.a;
    return float4(mix(image.rgb, color.rgb, w), image.a);
}

// People: whole-body parts. person: person mask; faceArea: solid face areas; head: head areas.
// parts = (entire person, body skin, clothes, 0); tone = skin color (L, a, b).
float4 lumora_peopleBody(sample_t s, sample_t person, sample_t faceArea, sample_t head, float4 parts, float4 tone) {
    float3 lab = lumoraMToOklab(max(s.rgb, float3(0.0f)));
    float skinLike = (1.0f - smoothstep(0.05f, 0.11f, length(lab.yz - tone.yz)))
        * smoothstep(tone.x - 0.34f, tone.x - 0.2f, lab.x)
        * (1.0f - smoothstep(tone.x + 0.25f, tone.x + 0.4f, lab.x));
    float p = person.r;
    float w = parts.x * p;
    w = max(w, parts.y * p * skinLike * (1.0f - faceArea.r));
    w = max(w, parts.z * p * (1.0f - skinLike) * (1.0f - head.r) * (1.0f - faceArea.r));
    return lumoraMGray(w);
}

// People: face parts for one face (inputs aligned over the face's head region).
// masksA = (skin, lips, mouth), masksB = (eyes, iris, under-eye), d = (eyeshadow, brow field, face area),
// e = (liner, lashes, brow core). partsA = (face skin, eye whites, iris, brows), partsB = (lips, teeth, hair, 0).
float4 lumora_peopleFace(sample_t s, sample_t person, sample_t masksA, sample_t masksB, sample_t d, sample_t e, sample_t head,
                         float4 partsA, float4 partsB, float4 tone, float4 hairTone) {
    float3 lab = lumoraMToOklab(max(s.rgb, float3(0.0f)));
    float skinLike = (1.0f - smoothstep(0.05f, 0.11f, length(lab.yz - tone.yz)))
        * smoothstep(tone.x - 0.34f, tone.x - 0.2f, lab.x);
    float w = partsA.x * masksA.r * smoothstep(0.0f, 0.5f, skinLike);
    w = max(w, partsA.y * masksB.r * (1.0f - masksB.g));
    w = max(w, partsA.z * masksB.g);
    // Brows: the brow stroke plus darker-than-skin pixels inside the brow field.
    float browField = smoothstep(0.45f, 0.8f, d.g);
    float darker = smoothstep(0.02f, 0.1f, tone.x - lab.x);
    w = max(w, partsA.w * max(e.b, browField * darker) * (1.0f - masksB.r));
    w = max(w, partsB.x * masksA.g);
    float teeth = masksA.b * smoothstep(tone.x - 0.15f, tone.x + 0.02f, lab.x) * (1.0f - smoothstep(0.06f, 0.11f, length(lab.yz)));
    w = max(w, partsB.y * teeth);
    float3 hairDiff = lab - hairTone.xyz;
    float hairLike = 1.0f - smoothstep(0.1f, 0.2f, length(float3(hairDiff.x * 0.5f, hairDiff.yz)));
    float hair = person.r * head.r * hairLike * (1.0f - skinLike * 0.9f) * (1.0f - d.b);
    w = max(w, partsB.z * hair);
    return lumoraMGray(w);
}

} }
