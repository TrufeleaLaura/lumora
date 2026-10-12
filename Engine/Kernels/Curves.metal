#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

static inline float lumoraSRGBEncode(float x) {
    return x <= 0.0031308f ? 12.92f * x : 1.055f * pow(x, 1.0f / 2.4f) - 0.055f;
}

static inline float lumoraSRGBDecode(float x) {
    return x <= 0.04045f ? x / 12.92f : pow((x + 0.055f) / 1.055f, 2.4f);
}

extern "C" { namespace coreimage {

// Tone curve through a lookup table (one row, `lutSize` texels; r/g/b = final channel curves).
// Curves act on sRGB-encoded values like Lightroom's; values above 1 pass through shifted.
float4 lumora_curves(sampler src, sampler lut, float lutSize) {
    float4 s = src.sample(src.coord());
    float3 c = max(s.rgb, float3(0.0f));
    float3 e = float3(lumoraSRGBEncode(c.r), lumoraSRGBEncode(c.g), lumoraSRGBEncode(c.b));
    float3 x = clamp(e, 0.0f, 1.0f) * (lutSize - 1.0f) + 0.5f;
    float r = lut.sample(lut.transform(float2(x.r, 0.5f))).r;
    float g = lut.sample(lut.transform(float2(x.g, 0.5f))).g;
    float b = lut.sample(lut.transform(float2(x.b, 0.5f))).b;
    float3 o = float3(r, g, b) + max(e - 1.0f, float3(0.0f));
    return float4(lumoraSRGBDecode(o.r), lumoraSRGBDecode(o.g), lumoraSRGBDecode(o.b), s.a);
}

}}
