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

    // Skin probability: inside the face mask and close to the measured skin tone.
    float chromaDistance = length(lab.yz - tone.yz);
    float colorMatch = 1.0f - smoothstep(0.035f, 0.085f, chromaDistance);
    float lightMatch = smoothstep(tone.x - 0.38f, tone.x - 0.2f, lab.x);
    float skin = masksA.r * colorMatch * lightMatch;

    // Frequency separation: low (edge-aware) + mid (blotches) + high (pores).
    float low = base.r * p + base.g;
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

// Backward warp: each output pixel samples the input at its position plus the displacement
// field (normalized offsets in .rg, multiplied by the image size).
float4 lumora_displace(sampler src, sampler field, float2 imageSize, destination dest) {
    float2 position = dest.coord();
    float2 offset = field.sample(field.transform(position)).rg * imageSize;
    return src.sample(src.transform(position + offset));
}

}}
