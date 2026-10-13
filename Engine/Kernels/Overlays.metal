#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float3 lumoraOToPerceptual3(float3 c) { return pow(max(c, float3(0.0f)), float3(1.0f / 2.2f)); }
static inline float3 lumoraOToLinear3(float3 c) { return pow(max(c, float3(0.0f)), float3(2.2f)); }

// Hue (0...1) to a soft rainbow color.
static inline float3 lumoraORainbow(float h) {
    float3 k = float3(0.0f, 2.0f / 3.0f, 1.0f / 3.0f);
    return clamp(abs(fract(h + k) * 6.0f - 3.0f) - 1.0f, 0.0f, 1.0f);
}

static inline float lumoraOHash(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

extern "C" { namespace coreimage {

// Screen blend in perceptual space: light layers (leaks, glows) brighten without clipping.
float4 lumora_screenBlend(sample_t s, sample_t layer, float amount) {
    float3 a = lumoraOToPerceptual3(s.rgb);
    float3 b = lumoraOToPerceptual3(layer.rgb) * amount;
    return float4(lumoraOToLinear3(1.0f - (1.0f - a) * (1.0f - b)), s.a);
}

// Multiply blend: dark layers (paper, shadows) darken. layer is 1 = no change.
float4 lumora_multiplyBlend(sample_t s, sample_t layer, float amount) {
    float3 m = mix(float3(1.0f), max(layer.rgb, float3(0.0f)), amount);
    return float4(s.rgb * m, s.a);
}

// Window light and shadows. params = (style, angle radians, period px, softness px); size = (w, h).
// Returns a multiplier: 1 in light, darker in shadow.
float4 lumora_shadowLayer(float4 params, float2 size, destination dest) {
    float2 p = dest.coord();
    float style = params.x;
    float c = cos(params.y), s = sin(params.y);
    float2 r = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    float period = max(params.z, 4.0f);
    float soft = max(params.w, 0.5f);
    float light;
    if (style < 2.5f) {
        // Blinds: thin slats of shadow.
        float t = fract(r.y / period);
        float slat = smoothstep(0.0f, soft / period, t) * (1.0f - smoothstep(0.55f - soft / period, 0.55f, t));
        light = slat;
        if (style > 1.5f) {
            // Window panes: add vertical bars.
            float u = fract(r.x / (period * 3.0f));
            light *= 1.0f - (smoothstep(0.0f, soft / (period * 3.0f), u) * (1.0f - smoothstep(0.08f, 0.08f + soft / (period * 3.0f), u)));
        }
        // Light falls off toward one side, like a window patch.
        float2 uv = p / size;
        light = mix(1.0f, light, smoothstep(0.0f, 0.35f, uv.x + uv.y * 0.3f) * (1.0f - smoothstep(0.85f, 1.3f, uv.x + uv.y * 0.3f)));
    } else {
        // Leaves / dappled light: warped, elongated cells (leaf-like blobs, not dots).
        float2 q = r / (period * 2.2f);
        q += 0.45f * float2(sin(q.y * 1.7f + 0.6f * sin(q.x * 2.3f)), sin(q.x * 1.3f + 0.8f * sin(q.y * 1.9f)));
        float2 cell = floor(q);
        float best = 2.0f;
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                float2 g = cell + float2(i, j);
                float2 o = float2(lumoraOHash(g), lumoraOHash(g + 17.0f));
                float angle = lumoraOHash(g + 41.0f) * 3.14159f;
                float2 d = q - g - o;
                float2 local = float2(d.x * cos(angle) + d.y * sin(angle), -d.x * sin(angle) + d.y * cos(angle));
                best = min(best, length(local * float2(1.0f, 2.2f)));
            }
        }
        light = style < 3.5f ? smoothstep(0.3f, 0.7f, best) : 1.0f - smoothstep(0.25f, 0.6f, best);
    }
    float m = mix(0.35f, 1.0f, light);
    return float4(m, m, m, 1.0f);
}

// Cellophane / plastic: crinkled rainbow sheen. params = (seed, scale px, 0, 0).
float4 lumora_plasticLayer(float4 params, destination dest) {
    float2 p = dest.coord() / max(params.y, 1.0f) + params.x;
    float fold = sin(p.x * 1.7f + 2.5f * sin(p.y * 0.9f + p.x * 0.3f)) * sin(p.y * 1.3f - 1.8f * sin(p.x * 0.7f));
    float streak = pow(smoothstep(0.55f, 1.0f, fold), 2.0f);
    float hue = fract(p.x * 0.11f + p.y * 0.07f + fold * 0.3f);
    float3 color = mix(float3(0.85f), lumoraORainbow(hue), 0.6f) * (0.15f + streak);
    return float4(color, 1.0f);
}

// Prism: a soft rainbow band across the frame. params = (center x, center y, angle, width) in px.
float4 lumora_prismLayer(float4 params, destination dest) {
    float2 d = dest.coord() - params.xy;
    float2 n = float2(-sin(params.z), cos(params.z));
    float t = dot(d, n) / max(params.w, 1.0f);
    float band = exp(-t * t * 2.0f);
    float3 color = lumoraORainbow(fract(t * 0.35f + 0.5f)) * band * 0.9f;
    return float4(color, 1.0f);
}

// VHS: scanlines, a noisy tracking band near the bottom and softened chroma.
// params = (strength, line period px, band position y px, band height px); chroma = horizontally blurred copy.
float4 lumora_vhs(sampler src, sampler chromaSrc, float4 params, destination dest) {
    float2 p = dest.coord();
    float4 s = src.sample(src.transform(p));
    float4 chroma = chromaSrc.sample(chromaSrc.transform(p));
    float strength = params.x;
    float3 c = s.rgb;
    // Keep luminance sharp, take color from the smeared copy.
    float y = dot(c, float3(0.2126f, 0.7152f, 0.0722f));
    float yc = dot(chroma.rgb, float3(0.2126f, 0.7152f, 0.0722f));
    float3 smeared = yc > 1.0e-5f ? chroma.rgb * (y / yc) : c;
    c = mix(c, smeared, 0.8f * strength);
    float line = 0.5f + 0.5f * sin(p.y / max(params.y, 1.0f) * 6.2831853f);
    c *= 1.0f - 0.12f * strength * line;
    float band = exp(-pow((p.y - params.z) / max(params.w, 1.0f), 2.0f));
    float noise = lumoraOHash(floor(p / float2(3.0f, 1.0f)));
    c = mix(c, float3(noise), band * 0.35f * strength);
    // Slightly lifted, cooler blacks.
    c = c * (1.0f - 0.06f * strength) + float3(0.012f, 0.014f, 0.02f) * strength;
    return float4(c, s.a);
}

// Rounded-rectangle mask (Super 8 gate): rect = (x, y, w, h), radius px, soft px.
float4 lumora_roundedMask(float4 rect, float radius, float soft, destination dest) {
    float2 p = dest.coord();
    float2 center = rect.xy + rect.zw * 0.5f;
    float2 q = abs(p - center) - (rect.zw * 0.5f - radius);
    float d = length(max(q, float2(0.0f))) + min(max(q.x, q.y), 0.0f) - radius;
    float w = 1.0f - smoothstep(-soft, soft, d);
    return float4(w, w, w, w);
}

} }
