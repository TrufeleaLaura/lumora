#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// Approximate perceptual encoding used to shape tone curves. Pixels arrive in
// scene-linear light (Core Image working space) and leave in scene-linear light.
static inline float lumoraToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraToLinear(float x) { return pow(max(x, 0.0f), 2.2f); }

extern "C" { namespace coreimage {

// exposure: EV stops. contrast, whites, blacks, saturation: -1...+1.
float4 lumora_basicTone(sample_t s, float exposure, float contrast, float whites, float blacks, float saturation) {
    const float3 lumaWeights = float3(0.2126f, 0.7152f, 0.0722f);

    float3 c = max(s.rgb, float3(0.0f)) * exp2(exposure);
    float y = dot(c, lumaWeights);
    float p = lumoraToPerceptual(y);

    // Whites lift/compress the bright end, blacks the dark end.
    p += whites * 0.25f * smoothstep(0.35f, 1.0f, p);
    p += blacks * 0.20f * (1.0f - smoothstep(0.0f, 0.6f, p));

    // Contrast pivots around perceptual mid grey.
    float k = contrast >= 0.0f ? 1.0f + contrast : 1.0f + contrast * 0.75f;
    p = max((p - 0.5f) * k + 0.5f, 0.0f);

    // Apply the luminance change as a ratio so hues are preserved.
    float yNew = lumoraToLinear(p);
    c = y > 1.0e-5f ? c * (yNew / y) : float3(yNew);

    float y2 = dot(c, lumaWeights);
    c = mix(float3(y2), c, 1.0f + saturation);

    return float4(max(c, float3(0.0f)), s.a);
}

}}
