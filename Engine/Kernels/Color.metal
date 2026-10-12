#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// Color work happens in OKLab / OKLCh (perceptually uniform), so hue and saturation
// changes don't shift brightness or produce the muddy results of HSL math.

static inline float lumoraCbrt(float x) { return sign(x) * pow(fabs(x), 1.0f / 3.0f); }

static inline float3 lumoraLinearToOklab(float3 c) {
    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
    float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
    float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;
    l = lumoraCbrt(l);
    m = lumoraCbrt(m);
    s = lumoraCbrt(s);
    return float3(0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s,
                  1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s,
                  0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s);
}

static inline float3 lumoraOklabToLinear(float3 lab) {
    float l = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    l = l * l * l;
    m = m * m * m;
    s = s * s * s;
    return float3(4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
                 -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
                 -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
}

static inline float lumoraPick(float4 a, float4 b, int i) {
    return i < 4 ? a[i] : b[i - 4];
}

// Centers of the 8 mixer bands, as OKLab hue angles in degrees.
static inline float lumoraBandCenter(int i) {
    switch (i) {
        case 0: return 29.0f;   // red
        case 1: return 62.0f;   // orange
        case 2: return 105.0f;  // yellow
        case 3: return 142.0f;  // green
        case 4: return 195.0f;  // aqua
        case 5: return 264.0f;  // blue
        case 6: return 298.0f;  // purple
        default: return 330.0f; // magenta
    }
}

// Returns (band index 0, band index 1, blend t) for a hue; weights are (1 - t, t).
static inline float3 lumoraBandWeights(float h) {
    float hh = h < 29.0f ? h + 360.0f : h;
    float i0 = 7.0f;
    float i1 = 0.0f;
    float c0 = 330.0f;
    float c1 = 389.0f;
    for (int k = 0; k < 7; k++) {
        float a = lumoraBandCenter(k);
        float b = lumoraBandCenter(k + 1);
        if (hh >= a && hh < b) {
            i0 = float(k);
            i1 = float(k + 1);
            c0 = a;
            c1 = b;
        }
    }
    float t = smoothstep(0.0f, 1.0f, (hh - c0) / (c1 - c0));
    return float3(i0, i1, t);
}

extern "C" { namespace coreimage {

// HSL mixer, saturation/vibrance, 3-way color grading and black & white in one pass.
// hue*/sat*/lum*/bw*: per-band values -1...+1 (bands 0-3 in A, 4-7 in B).
// basic: (saturation, vibrance, black & white on/off, 0).
// grade*: (a offset, b offset, L offset, 0). gradeParams: (balance -1...1, blending 0...1, 0, 0).
float4 lumora_color(sample_t s,
                    float4 hueA, float4 hueB, float4 satA, float4 satB, float4 lumA, float4 lumB,
                    float4 basic, float4 bwA, float4 bwB,
                    float4 gradeShadows, float4 gradeMidtones, float4 gradeHighlights, float4 gradeGlobal,
                    float4 gradeParams) {
    float3 lab = lumoraLinearToOklab(max(s.rgb, float3(0.0f)));
    float L = lab.x;
    float chroma = length(lab.yz);
    float originalChroma = chroma;
    float h = atan2(lab.z, lab.y) * 57.2957795f;
    if (h < 0.0f) { h += 360.0f; }

    float3 band = lumoraBandWeights(h);
    int i0 = int(band.x);
    int i1 = int(band.y);
    float w1 = band.z;
    float w0 = 1.0f - w1;
    float chromaWeight = smoothstep(0.0f, 0.06f, chroma);

    // Mixer.
    float dHue = (w0 * lumoraPick(hueA, hueB, i0) + w1 * lumoraPick(hueA, hueB, i1)) * 30.0f * chromaWeight;
    float dSat = w0 * lumoraPick(satA, satB, i0) + w1 * lumoraPick(satA, satB, i1);
    float dLum = (w0 * lumoraPick(lumA, lumB, i0) + w1 * lumoraPick(lumA, lumB, i1)) * chromaWeight * 0.3f;
    h += dHue;
    chroma *= max(0.0f, 1.0f + dSat);
    L = dLum > 0.0f ? L + max(1.0f - L, 0.0f) * dLum : L * (1.0f + dLum);

    // Saturation & vibrance (vibrance favors muted colors and protects skin tones).
    float saturation = basic.x;
    float vibrance = basic.y;
    chroma *= max(0.0f, 1.0f + saturation);
    if (vibrance > 0.0f) {
        float muted = 1.0f - smoothstep(0.02f, 0.22f, chroma);
        float hw = h - 360.0f * floor(h / 360.0f);
        float skin = smoothstep(25.0f, 45.0f, hw) * (1.0f - smoothstep(70.0f, 95.0f, hw));
        chroma *= 1.0f + vibrance * (0.25f + 0.95f * muted) * (1.0f - 0.65f * skin);
    } else {
        chroma *= max(0.0f, 1.0f + vibrance * 0.85f);
    }

    float hueRadians = h / 57.2957795f;
    float2 ab = float2(cos(hueRadians), sin(hueRadians)) * chroma;

    // Black & white with per-band luminance mix (before grading, so toning still works).
    if (basic.z > 0.5f) {
        float bwMix = w0 * lumoraPick(bwA, bwB, i0) + w1 * lumoraPick(bwA, bwB, i1);
        L *= 1.0f + bwMix * 0.6f * smoothstep(0.0f, 0.12f, originalChroma);
        ab = float2(0.0f);
    }

    // Color grading.
    float balance = gradeParams.x;
    float blending = gradeParams.y;
    float x = pow(clamp(L, 0.0f, 1.0f), exp2(-balance));
    float sharpness = mix(3.0f, 1.0f, blending);
    float wShadows = pow(1.0f - x, sharpness);
    float wHighlights = pow(x, sharpness);
    float wMidtones = pow(clamp(4.0f * x * (1.0f - x), 0.0f, 1.0f), sharpness * 0.5f);
    ab += gradeShadows.xy * wShadows + gradeMidtones.xy * wMidtones + gradeHighlights.xy * wHighlights + gradeGlobal.xy;
    L += gradeShadows.z * wShadows + gradeMidtones.z * wMidtones + gradeHighlights.z * wHighlights + gradeGlobal.z;

    float3 rgb = lumoraOklabToLinear(float3(max(L, 0.0f), ab));
    return float4(max(rgb, float3(0.0f)), s.a);
}

// OKLab (L, a, b) image, used for chroma noise reduction.
float4 lumora_toOklab(sample_t s) {
    float3 lab = lumoraLinearToOklab(max(s.rgb, float3(0.0f)));
    return float4(lab, 1.0f);
}

// Replaces chroma with a smoothed version (color noise reduction). Near luminance edges
// (where blurred luma differs from the pixel) the smoothing backs off so colors don't bleed.
float4 lumora_chromaMerge(sample_t s, sample_t smoothedLab, sample_t blurredLuma, float amount) {
    float3 c = max(s.rgb, float3(0.0f));
    float3 lab = lumoraLinearToOklab(c);
    float p = pow(max(dot(c, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f), 1.0f / 2.2f);
    float edge = smoothstep(0.015f, 0.06f, fabs(p - blurredLuma.r));
    lab.yz = mix(lab.yz, smoothedLab.yz, amount * (1.0f - edge));
    return float4(max(lumoraOklabToLinear(lab), float3(0.0f)), s.a);
}

// Removes purple/green fringes near high-contrast edges.
float4 lumora_defringe(sample_t s, sample_t blurredLuma, float amount) {
    float3 c = max(s.rgb, float3(0.0f));
    float3 lab = lumoraLinearToOklab(c);
    float p = pow(max(dot(c, float3(0.2126f, 0.7152f, 0.0722f)), 0.0f), 1.0f / 2.2f);
    float edge = smoothstep(0.03f, 0.15f, fabs(p - blurredLuma.r));
    float h = atan2(lab.z, lab.y) * 57.2957795f;
    if (h < 0.0f) { h += 360.0f; }
    float purple = smoothstep(270.0f, 295.0f, h) * (1.0f - smoothstep(335.0f, 350.0f, h));
    float green = smoothstep(115.0f, 130.0f, h) * (1.0f - smoothstep(160.0f, 175.0f, h));
    float k = 1.0f - amount * edge * max(purple, green);
    lab.yz *= k;
    return float4(max(lumoraOklabToLinear(lab), float3(0.0f)), s.a);
}

}}
