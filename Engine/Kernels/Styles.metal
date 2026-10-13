#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraSLuma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static inline float lumoraSToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraSToLinear(float x) { return pow(max(x, 0.0f), 2.2f); }
static inline float3 lumoraSToPerceptual3(float3 c) { return pow(max(c, float3(0.0f)), float3(1.0f / 2.2f)); }
static inline float3 lumoraSToLinear3(float3 c) { return pow(max(c, float3(0.0f)), float3(2.2f)); }
static inline float lumoraSCbrt(float x) { return sign(x) * pow(fabs(x), 1.0f / 3.0f); }

static inline float3 lumoraSToOklab(float3 c) {
    float l = lumoraSCbrt(0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b);
    float m = lumoraSCbrt(0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b);
    float s = lumoraSCbrt(0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b);
    return float3(0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s,
                  1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s,
                  0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s);
}

static inline float3 lumoraSFromOklab(float3 lab) {
    float l = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    return float3(4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
                 -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
                 -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
}

// Soft limit so boosted detail can't overshoot into halos.
static inline float lumoraSSoft(float x, float k) { return x / (1.0f + fabs(x) * k); }

static inline float3 lumoraSSaturate(float3 c, float factor) {
    float3 lab = lumoraSToOklab(max(c, float3(0.0f)));
    lab.yz *= max(factor, 0.0f);
    return max(lumoraSFromOklab(lab), float3(0.0f));
}

extern "C" { namespace coreimage {

// HDR Scape and Drama. toneBase / clarityBase: guided coefficients (a, b) of log2 luminance
// at large and mid scale; fineLog: slightly blurred log2 luminance.
// params = (hdr, drama, drama saturation -1...1, 0), 0...1.
float4 lumora_hdrDrama(sample_t s, sample_t toneBase, sample_t clarityBase, sample_t fineLog, float4 params) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraSLuma(c);
    if (y < 1.0e-5f) { return s; }
    float hdr = params.x, drama = params.y;
    float logY = clamp(log2(y), -10.0f, 4.0f);
    float base = toneBase.r * logY + toneBase.g;
    float mid = clarityBase.r * logY + clarityBase.g;
    const float grey = -2.47f;
    // Large-scale tones pulled toward mid grey (HDR compresses, Drama adds punch).
    float baseOut = grey + (base - grey) * (1.0f - 0.5f * hdr + 0.15f * drama);
    float midDetail = lumoraSSoft(mid - base, 0.6f) * (1.0f + 0.9f * hdr + 0.6f * drama);
    float structure = lumoraSSoft(fineLog.r - mid, 1.0f) * (1.0f + 0.7f * hdr + 2.2f * drama);
    float fine = (logY - fineLog.r) * (1.0f + 0.4f * hdr + 0.6f * drama);
    float result = baseOut + midDetail + structure + fine;
    float3 out = c * exp2(result - logY);
    float saturation = 1.0f + 0.3f * hdr + drama * (params.z * 0.8f - 0.15f);
    return float4(lumoraSSaturate(out, saturation), s.a);
}

// Tonal Contrast: fine-scale detail boosted separately in shadows, midtones and highlights.
// bands = (high, mid, low, 0) 0...1.
float4 lumora_tonalContrast(sample_t s, sample_t blurredLog, float4 bands) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraSLuma(c);
    if (y < 1.0e-5f) { return s; }
    float logY = clamp(log2(y), -10.0f, 4.0f);
    float p = lumoraSToPerceptual(y);
    float low = 1.0f - smoothstep(0.18f, 0.45f, p);
    float high = smoothstep(0.55f, 0.82f, p);
    float midW = max(1.0f - low - high, 0.0f);
    float gain = 2.4f * (bands.z * low + bands.y * midW + bands.x * high);
    float detail = lumoraSSoft(logY - blurredLog.r, 0.8f);
    float result = logY + detail * gain;
    return float4(c * exp2(result - logY), s.a);
}

// Glamour Glow: screen blend with a blurred copy (perceptual space), a touch less saturated,
// warmed or cooled. params = (amount, warmth -1...1, 0, 0).
float4 lumora_glow(sample_t s, sample_t blurred, float4 params) {
    float amount = params.x;
    float3 a = lumoraSToPerceptual3(s.rgb);
    float3 tint = float3(1.0f + 0.12f * params.y, 1.0f, 1.0f - 0.12f * params.y);
    float3 b = lumoraSToPerceptual3(blurred.rgb * tint) * (0.75f * amount);
    float3 screen = 1.0f - (1.0f - a) * (1.0f - b);
    float3 out = lumoraSToLinear3(mix(a, screen, clamp(amount * 1.2f, 0.0f, 1.0f)));
    return float4(lumoraSSaturate(out, 1.0f - 0.2f * amount), s.a);
}

// Bright parts only (for halation and bokeh): how far luminance is above `threshold`.
float4 lumora_brightParts(sample_t s, float threshold) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraSLuma(c);
    float w = smoothstep(threshold, threshold + 0.35f, y);
    return float4(c * w, 1.0f);
}

// Halation: blurred highlights added back as a red-orange halo.
float4 lumora_halation(sample_t s, sample_t halo, float amount) {
    float glow = lumoraSLuma(halo.rgb);
    float3 color = float3(1.0f, 0.32f, 0.12f) * glow * amount * 1.6f;
    return float4(s.rgb + color, s.a);
}

// Vintage: lifted blacks, softened whites, warm fade, less saturation.
float4 lumora_vintage(sample_t s, float amount) {
    float3 p = lumoraSToPerceptual3(s.rgb);
    float3 faded = 0.07f + p * 0.86f;
    // Warm highlights, slightly teal-green shadows.
    float luma = dot(faded, float3(0.2126f, 0.7152f, 0.0722f));
    float3 warm = faded + float3(0.045f, 0.015f, -0.05f) * luma + float3(-0.01f, 0.012f, 0.02f) * (1.0f - luma);
    float3 out = lumoraSToLinear3(mix(p, warm, amount));
    return float4(lumoraSSaturate(out, 1.0f - 0.35f * amount), s.a);
}

// Noir: black & white with a punchy S-curve and a light wash in the highlights.
float4 lumora_noir(sample_t s, float amount) {
    float3 c = max(s.rgb, float3(0.0f));
    // Mostly red/green channels, like a yellow filter on B&W film.
    float y = dot(c, float3(0.35f, 0.55f, 0.10f));
    float p = lumoraSToPerceptual(y);
    float k = 7.0f;
    float lo = 1.0f / (1.0f + exp(0.5f * k));
    float hi = 1.0f / (1.0f + exp(-0.5f * k));
    float curve = (1.0f / (1.0f + exp(-k * (p - 0.5f))) - lo) / (hi - lo);
    float washed = curve + (1.0f - curve) * 0.12f * smoothstep(0.5f, 1.0f, curve);
    float3 mono = float3(lumoraSToLinear(washed));
    float3 grey = float3(lumoraSToLinear(p));
    // A little of the effect gives neutral B&W; more adds the contrast.
    float3 out = mix(c, grey, clamp(amount * 4.0f, 0.0f, 1.0f));
    out = mix(out, mono, amount);
    return float4(out, s.a);
}

// Grunge: soft-light texture, desaturation, darker edges and a color cast.
// params = (amount, tint a, tint b, 0); texture is gray around 0.5.
float4 lumora_grunge(sample_t s, sample_t texture, float4 params) {
    float amount = params.x;
    float3 p = lumoraSToPerceptual3(s.rgb);
    float t = texture.r;
    // Soft light.
    float3 lit = t < 0.5f ? p - (1.0f - 2.0f * t) * p * (1.0f - p) : p + (2.0f * t - 1.0f) * (sqrt(max(p, float3(0.0f))) - p);
    float3 out = lumoraSToLinear3(mix(p, lit, amount));
    float3 lab = lumoraSToOklab(max(out, float3(0.0f)));
    lab.yz = lab.yz * (1.0f - 0.45f * amount) + params.yz * amount;
    lab.x *= 1.0f - 0.08f * amount;
    return float4(max(lumoraSFromOklab(lab), float3(0.0f)), s.a);
}

// RGB split: red and blue sampled from opposite offsets (pixels).
float4 lumora_rgbSplit(sampler src, float2 offset, destination dest) {
    float2 position = dest.coord();
    float4 center = src.sample(src.transform(position));
    float r = src.sample(src.transform(position + offset)).r;
    float b = src.sample(src.transform(position - offset)).b;
    return float4(r, center.g, b, center.a);
}

// Tilt-shift band: 1 within `halfWidth` of the line through `center` (normal = unit vector
// across the band), fading to 0 over `fade` pixels.
float4 lumora_bandMask(float2 center, float2 normal, float halfWidth, float fade, destination dest) {
    float d = fabs(dot(dest.coord() - center, normal));
    float w = 1.0f - smoothstep(halfWidth, halfWidth + max(fade, 1.0f), d);
    return float4(w, w, w, 1.0f);
}

// Bright spots boosted before the bokeh blur so they bloom into discs.
float4 lumora_bokehBoost(sample_t s, float amount) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraSLuma(c);
    float boost = 1.0f + amount * 4.0f * smoothstep(0.55f, 1.1f, y);
    return float4(c * boost, s.a);
}

// Premultiplies by a weight (for normalized-convolution background fill).
float4 lumora_weighted(sample_t s, sample_t weight) {
    float w = clamp(weight.r, 0.0f, 1.0f);
    return float4(s.rgb * w, w);
}

// Divides a blurred premultiplied image by its blurred weight; keeps `original` where weight is high.
float4 lumora_unweight(sample_t blurred, sample_t original, sample_t weight) {
    float3 filled = blurred.a > 1.0e-4f ? blurred.rgb / blurred.a : original.rgb;
    return float4(mix(filled, original.rgb, clamp(weight.r, 0.0f, 1.0f)), original.a);
}

// Sharp → medium blur → full blur following the focus mask (1 = sharp).
// params = (miniature amount, 0, 0, 0).
float4 lumora_focusBlend(sample_t sharp, sample_t blurA, sample_t blurB, sample_t focus, float4 params) {
    float w = 1.0f - clamp(focus.r, 0.0f, 1.0f);
    float3 c = w < 0.5f ? mix(sharp.rgb, blurA.rgb, w * 2.0f) : mix(blurA.rgb, blurB.rgb, w * 2.0f - 1.0f);
    float mini = params.x;
    if (mini > 0.0f) {
        float3 p = lumoraSToPerceptual3(c);
        p = mix(p, smoothstep(0.0f, 1.0f, p), mini * 0.6f);
        c = lumoraSSaturate(lumoraSToLinear3(p), 1.0f + 0.6f * mini);
    }
    return float4(c, sharp.a);
}

} }
