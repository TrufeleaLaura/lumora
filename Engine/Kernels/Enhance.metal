#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraEHash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

static inline float lumoraENoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);
    return mix(mix(lumoraEHash(i), lumoraEHash(i + float2(1.0f, 0.0f)), u.x),
               mix(lumoraEHash(i + float2(0.0f, 1.0f)), lumoraEHash(i + float2(1.0f, 1.0f)), u.x), u.y);
}

static inline float lumoraEFbm(float2 p) {
    float value = 0.0f, amplitude = 0.5f;
    for (int i = 0; i < 5; i++) {
        value += amplitude * lumoraENoise(p);
        p = p * 2.03f + float2(17.3f, 9.1f);
        amplitude *= 0.5f;
    }
    return value;
}

extern "C" { namespace coreimage {

// Procedural sky (linear colors). params = (horizon y, top y, cloud cover, seed) in px;
// params2 = (cloud scale px, sun x, sun y, stars).
float4 lumora_skyLayer(float4 zenith, float4 horizon, float4 cloudLight, float4 cloudShade, float4 params, float4 params2, destination dest) {
    float2 p = dest.coord();
    float t = clamp((p.y - params.x) / max(params.y - params.x, 1.0f), 0.0f, 1.0f);
    float3 color = mix(horizon.rgb, zenith.rgb, pow(t, 0.7f));

    float cover = params.z;
    if (cover > 0.0f) {
        float scale = max(params2.x, 1.0f);
        // Clouds get flatter and smaller toward the horizon (perspective).
        float squash = mix(3.2f, 1.6f, t);
        float2 q = float2(p.x / (scale * squash), p.y / scale) + params.w;
        float n = lumoraEFbm(q);
        float above = lumoraEFbm(q + float2(0.0f, 0.08f));
        float density = smoothstep(1.0f - cover - 0.08f, 1.0f - cover + 0.22f, n);
        float lit = clamp(0.55f + (n - above) * 6.0f, 0.0f, 1.0f);
        float3 cloud = mix(cloudShade.rgb, cloudLight.rgb, lit);
        color = mix(color, cloud, density * (0.55f + 0.45f * t));
    }
    if (params2.y > 0.0f) {
        float d = length(p - params2.yz) / max(params2.x * 1.4f, 1.0f);
        float glow = exp(-d * d) * 0.7f + exp(-d * d * 40.0f) * 1.5f;
        color += float3(1.0f, 0.75f, 0.45f) * glow;
    }
    if (params2.w > 0.5f) {
        float2 cell = floor(p / 3.0f);
        float star = step(0.9965f, lumoraEHash(cell)) * lumoraEHash(cell + 3.1f);
        color += float3(star) * t * 0.9f;
    }
    return float4(color, 1.0f);
}

// Puts the new sky in, and tints the landscape toward the sky's light.
// params = (amount, relight, 0, 0); tint = sky light relative to neutral (linear rgb).
float4 lumora_skyBlend(sample_t s, sample_t sky, sample_t mask, float4 params, float4 tint) {
    // A firmer edge than the soft selection mask: no halo of the old sky along the horizon.
    float m = smoothstep(0.2f, 0.72f, mask.r) * params.x;
    float3 relit = s.rgb * mix(float3(1.0f), tint.rgb, params.y * (1.0f - m) * 0.35f);
    return float4(mix(relit, sky.rgb, m), s.a);
}

// Clipping warning: blown highlights red, crushed shadows blue.
float4 lumora_clipping(sample_t s) {
    float top = max(s.r, max(s.g, s.b));
    if (top >= 0.999f) { return float4(1.0f, 0.05f, 0.05f, s.a); }
    if (top <= 0.0015f) { return float4(0.05f, 0.35f, 1.0f, s.a); }
    return s;
}

// Background behind the subject: mode 1 = solid color (linear), 2 = transparent.
float4 lumora_backgroundReplace(sample_t s, sample_t subject, float4 color, float mode) {
    float m = clamp(subject.r, 0.0f, 1.0f);
    if (mode > 1.5f) {
        return float4(s.rgb * m, m);
    }
    return float4(mix(color.rgb, s.rgb, m), 1.0f);
}

} }
