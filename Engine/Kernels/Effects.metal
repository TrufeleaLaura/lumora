#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraFxLuma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static inline float lumoraFxToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraFxToLinear(float x) { return pow(max(x, 0.0f), 2.2f); }

extern "C" { namespace coreimage {

// Vignette, fade and film grain, applied after cropping.
// vignette: (amount -1...1, midpoint 0...1, roundness -1...1, feather 0...1)
// vignetteExtra: (highlight protection 0...1, 0, 0, 0)
// frame: (minX, minY, width, height) of the visible image
// grain: (amount 0...1, 0, 0, 0); noise: monochrome noise in .r centered on 0.5
float4 lumora_finish(sample_t s, sample_t noise, float4 vignette, float4 vignetteExtra, float4 frame, float4 grain, float fade, destination dest) {
    float3 c = max(s.rgb, float3(0.0f));
    float3 p = float3(lumoraFxToPerceptual(c.r), lumoraFxToPerceptual(c.g), lumoraFxToPerceptual(c.b));

    if (fabs(vignette.x) > 1.0e-4f) {
        float2 halfSize = frame.zw * 0.5f;
        float2 center = frame.xy + halfSize;
        float2 offset = dest.coord() - center;
        float2 d = offset / halfSize;
        float ellipse = length(d);
        float circle = length(offset) / min(halfSize.x, halfSize.y) * 0.85f;
        float rectangle = max(fabs(d.x), fabs(d.y));
        float dist = vignette.z >= 0.0f ? mix(ellipse, circle, vignette.z) : mix(ellipse, rectangle, -vignette.z);
        float midpoint = mix(0.35f, 1.3f, vignette.y);
        float feather = mix(0.05f, 0.95f, vignette.w);
        float f = smoothstep(midpoint - feather * 0.5f, midpoint + feather * 0.5f, dist);
        if (vignette.x < 0.0f) {
            float protect = vignetteExtra.x * smoothstep(0.55f, 0.95f, lumoraFxLuma(p));
            p *= 1.0f + vignette.x * f * (1.0f - protect);
        } else {
            p = mix(p, float3(1.0f), vignette.x * f * 0.85f);
        }
    }

    if (fade > 0.0f) {
        p = mix(p, 0.07f + p * 0.88f, fade);
    }

    if (grain.x > 0.0f) {
        float n = noise.r - 0.5f;
        float l = clamp(lumoraFxLuma(p), 0.0f, 1.0f);
        float weight = 0.35f + 2.6f * l * (1.0f - l);
        p += grain.x * 0.24f * n * weight;
    }

    c = float3(lumoraFxToLinear(p.r), lumoraFxToLinear(p.g), lumoraFxToLinear(p.b));
    return float4(c, s.a);
}

// Unsharp-mask sharpening on perceptual luminance.
// blurred: Gaussian of perceptual luma at the sharpening radius; blurredWide: wider blur (edge mask).
// amount 0...1.5, detail 0...1 (less halo suppression), masking 0...1 (skip flat areas).
float4 lumora_sharpen(sample_t s, sample_t blurred, sample_t blurredWide, float amount, float detail, float masking) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraFxLuma(c);
    float p = lumoraFxToPerceptual(y);
    float d = p - blurred.r;
    float damping = mix(18.0f, 0.5f, detail);
    d = d / (1.0f + fabs(d) * damping);
    float edge = fabs(p - blurredWide.r);
    float m = masking > 0.0f ? smoothstep(masking * 0.06f, masking * 0.06f + 0.03f, edge) : 1.0f;
    float p2 = max(p + amount * 1.6f * d * m, 0.0f);
    float y2 = lumoraFxToLinear(p2);
    c = y > 1.0e-6f ? c * (y2 / y) : float3(y2);
    return float4(c, s.a);
}

// Luminance noise reduction: blends toward a self-guided (edge-preserving) smoothing.
// coeff: guided coefficients (a, b) of perceptual luminance. strength 0...1, detail 0...1.
float4 lumora_lumaDenoise(sample_t s, sample_t coeff, float strength, float detail) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraFxLuma(c);
    float p = lumoraFxToPerceptual(y);
    float smoothed = coeff.r * p + coeff.g;
    float p2 = mix(p, smoothed, strength * (1.0f - 0.6f * detail));
    float y2 = lumoraFxToLinear(p2);
    c = y > 1.0e-6f ? c * (y2 / y) : float3(y2);
    return float4(c, s.a);
}

// Lens vignetting correction. frame: (centerX, centerY, half diagonal, amount -1...1).
float4 lumora_lensVignette(sample_t s, float4 frame, destination dest) {
    float2 d = (dest.coord() - frame.xy) / frame.z;
    float r2 = dot(d, d);
    float gain = max(1.0f + frame.w * r2 * 0.9f, 0.0f);
    return float4(s.rgb * gain, s.a);
}

// Radial lens distortion. frame: (centerX, centerY, half diagonal, k). Returns the source position.
float2 lumora_lensDistortion(float4 frame, destination dest) {
    float2 d = (dest.coord() - frame.xy) / frame.z;
    float r2 = dot(d, d);
    float k = frame.w;
    float fill = k > 0.0f ? 1.0f / (1.0f + k) : 1.0f;
    return frame.xy + d * (1.0f + k * r2) * fill * frame.z;
}

}}
