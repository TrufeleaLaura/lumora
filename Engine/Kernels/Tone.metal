#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

// Pixels arrive in scene-linear light (Core Image working space, linear sRGB primaries)
// and leave in scene-linear light. Tone shaping happens in an approximate perceptual space.

static inline float lumoraLuma(float3 c) { return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); }
static inline float lumoraToPerceptual(float x) { return pow(max(x, 0.0f), 1.0f / 2.2f); }
static inline float lumoraToLinear(float x) { return pow(max(x, 0.0f), 2.2f); }
static inline float lumoraSigmoid(float x) { return 1.0f / (1.0f + exp(-x)); }

// Smooth S-curve (c > 0) or its inverse (c < 0) on perceptual 0...1, end points fixed.
static inline float lumoraContrast(float p, float c) {
    if (fabs(c) < 1.0e-4f) { return p; }
    float x = clamp(p, 0.0f, 1.0f);
    float over = max(p - 1.0f, 0.0f);
    if (c > 0.0f) {
        float k = c * 7.0f;
        float lo = lumoraSigmoid(-0.5f * k);
        float hi = lumoraSigmoid(0.5f * k);
        float y = (lumoraSigmoid(k * (x - 0.5f)) - lo) / (hi - lo);
        float endSlope = k * hi * (1.0f - hi) / (hi - lo);
        return y + over * endSlope;
    } else {
        float k = -c * 5.0f;
        float lo = lumoraSigmoid(-0.5f * k);
        float hi = lumoraSigmoid(0.5f * k);
        float t = clamp(lo + x * (hi - lo), 1.0e-6f, 1.0f - 1.0e-6f);
        float y = 0.5f + log(t / (1.0f - t)) / k;
        float endSlope = (hi - lo) / (k * hi * (1.0f - hi));
        return y + over * endSlope;
    }
}

// Contrast around a pivot (the photo's typical brightness) so the overall brightness stays put:
// 0, pivot and 1 are fixed, the S-curve acts on either side.
static inline float lumoraPivotContrast(float p, float c, float pivot) {
    if (fabs(c) < 1.0e-4f) { return p; }
    float over = max(p - 1.0f, 0.0f);
    float x = clamp(p, 0.0f, 1.0f);
    float pv = clamp(pivot, 0.25f, 0.75f);
    float t = x < pv ? 0.5f * x / pv : 0.5f + 0.5f * (x - pv) / (1.0f - pv);
    float t2 = clamp(lumoraContrast(t, c), 0.0f, 1.0f);
    float y = t2 < 0.5f ? t2 * 2.0f * pv : pv + (t2 - 0.5f) * 2.0f * (1.0f - pv);
    return y + over;
}

// Whites move the bright end, blacks the dark end (perceptual space).
static inline float lumoraWhitesBlacks(float p, float whites, float blacks) {
    float pw = min(p, 1.2f);
    p += whites * 0.35f * pw * pw * pw;
    float q = clamp(1.0f - p, 0.0f, 1.0f);
    p += blacks * 0.22f * q * q * q;
    return max(p, 0.0f);
}

// Gentle shoulder so pushed highlights roll off instead of clipping abruptly.
static inline float lumoraRolloff(float p) {
    const float knee = 0.97f;
    return p <= knee ? p : knee + (1.0f - knee) * tanh((p - knee) / (1.0f - knee));
}

extern "C" { namespace coreimage {

// --- Guided-filter helpers (edge-aware smoothing used for local tone mapping) ---

// (log2 luminance, its square, 0). Values clamped to a sane range.
float4 lumora_logLumaPair(sample_t s) {
    float l = clamp(log2(max(lumoraLuma(max(s.rgb, float3(0.0f))), 1.0e-4f)), -10.0f, 2.0f);
    return float4(l, l * l, 0.0f, 1.0f);
}

// (log2 luminance) in all channels.
float4 lumora_logLuma(sample_t s) {
    float l = clamp(log2(max(lumoraLuma(max(s.rgb, float3(0.0f))), 1.0e-4f)), -10.0f, 2.0f);
    return float4(l, l, l, 1.0f);
}

// (perceptual luminance) in all channels.
float4 lumora_perceptualLuma(sample_t s) {
    float p = lumoraToPerceptual(lumoraLuma(max(s.rgb, float3(0.0f))));
    return float4(p, p, p, 1.0f);
}

// (perceptual luminance, its square, 0).
float4 lumora_perceptualLumaPair(sample_t s) {
    float p = lumoraToPerceptual(lumoraLuma(max(s.rgb, float3(0.0f))));
    return float4(p, p * p, 0.0f, 1.0f);
}

// Returns its input (stand-in if a kernel can't be loaded).
float4 lumora_passthrough(sample_t s) {
    return s;
}

float4 lumora_passthroughSampler(sampler src, destination dest) {
    return src.sample(src.transform(dest.coord()));
}

// (value, its square, 0) of a single-channel image (in .r).
float4 lumora_lumaPair(sample_t s) {
    return float4(s.r, s.r * s.r, 0.0f, 1.0f);
}

// Self-guided filter coefficients from box-filtered (mean I, mean I²).
float4 lumora_guidedSelfCoefficients(sample_t means, float eps) {
    float meanI = means.r;
    float variance = max(means.g - meanI * meanI, 0.0f);
    float a = variance / (variance + eps);
    float b = meanI - a * meanI;
    return float4(a, b, 0.0f, 1.0f);
}

// Packs guide I and target p for a general guided filter: (I, p, I*p) and (I*I).
float4 lumora_guidedPack(sample_t guide, sample_t target) {
    float i = guide.r;
    float p = target.r;
    return float4(i, p, i * p, 1.0f);
}

float4 lumora_guidedPackSquare(sample_t guide) {
    float i = guide.r;
    return float4(i * i, 0.0f, 0.0f, 1.0f);
}

// General guided filter coefficients from box-filtered packs.
float4 lumora_guidedCoefficients(sample_t means, sample_t meanSquares, float eps) {
    float meanI = means.r;
    float meanP = means.g;
    float covariance = means.b - meanI * meanP;
    float variance = max(meanSquares.r - meanI * meanI, 0.0f);
    float a = covariance / (variance + eps);
    float b = meanP - a * meanI;
    return float4(a, b, 0.0f, 1.0f);
}

// --- Light panel ---

// base: upsampled guided-filter coefficients (a, b) of log luminance (local average brightness).
// exposure in EV; the rest -1...+1.
float4 lumora_tone(sample_t s, sample_t base, float exposure, float contrast, float highlights, float shadows, float whites, float blacks, float pivot) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraLuma(c);
    float logY = clamp(log2(max(y, 1.0e-4f)), -10.0f, 4.0f);

    // Local tone mapping: move the smooth base layer, keep the detail layer.
    float baseLog = base.r * logY + base.g;
    float detail = logY - baseLog;
    float baseP = lumoraToPerceptual(exp2(min(baseLog, 0.5f)));
    float wShadows = 1.0f - smoothstep(0.05f, 0.62f, baseP);
    float wHighlights = smoothstep(0.38f, 0.92f, baseP);
    // Keep the brightest specular points (sun, reflections) from turning grey.
    float pixelP = lumoraToPerceptual(y);
    wHighlights *= highlights < 0.0f ? (1.0f - 0.55f * smoothstep(0.9f, 1.0f, pixelP)) : 1.0f;
    float shift = shadows * 2.1f * wShadows + highlights * (highlights < 0.0f ? 1.25f : 0.8f) * wHighlights;

    float y2 = exp2(baseLog + detail + shift + exposure);
    if (y < 1.0e-4f) { y2 = y * exp2(shift + exposure); }

    float p = lumoraToPerceptual(y2);
    p = lumoraWhitesBlacks(p, whites, blacks);
    p = lumoraPivotContrast(p, contrast, pivot);
    p = lumoraRolloff(p);
    float y3 = lumoraToLinear(p);

    float3 byLuma = y > 1.0e-6f ? c * (y3 / y) : float3(y3);
    if (fabs(contrast) < 1.0e-4f) {
        return float4(max(byLuma, float3(0.0f)), s.a);
    }
    // Contrast also on each channel, like a film curve: colors gain a little richness with
    // more contrast (and soften with less) instead of only getting darker or lighter.
    float3 scaled = y > 1.0e-6f ? c * (y2 / y) : float3(y2);
    float3 pc = pow(max(scaled, float3(0.0f)), float3(1.0f / 2.2f));
    pc.r = lumoraRolloff(lumoraPivotContrast(lumoraWhitesBlacks(pc.r, whites, blacks), contrast, pivot));
    pc.g = lumoraRolloff(lumoraPivotContrast(lumoraWhitesBlacks(pc.g, whites, blacks), contrast, pivot));
    pc.b = lumoraRolloff(lumoraPivotContrast(lumoraWhitesBlacks(pc.b, whites, blacks), contrast, pivot));
    float3 byChannel = pow(max(pc, float3(0.0f)), float3(2.2f));
    // Keep the luminance of the luma path, take part of the color from the channel path.
    float yc = lumoraLuma(byChannel);
    float3 matched = yc > 1.0e-6f ? byChannel * (y3 / yc) : byLuma;
    return float4(max(mix(byLuma, matched, 0.5f), float3(0.0f)), s.a);
}

// Texture (fine detail) and clarity (mid-scale local contrast).
// blurredLog: Gaussian-blurred log luminance. clarityBase: guided coefficients (a, b).
float4 lumora_localContrast(sample_t s, sample_t blurredLog, sample_t clarityBase, float texture, float clarity) {
    float3 c = max(s.rgb, float3(0.0f));
    float y = lumoraLuma(c);
    if (y < 1.0e-4f) { return s; }
    float logY = clamp(log2(y), -10.0f, 4.0f);
    float result = logY;

    float fine = logY - blurredLog.r;
    fine = fine / (1.0f + fabs(fine) * 1.5f);
    result += texture * 0.9f * fine;

    float baseLog = clarityBase.r * logY + clarityBase.g;
    float mid = logY - baseLog;
    mid = mid / (1.0f + fabs(mid) * 0.8f);
    float p = lumoraToPerceptual(y);
    float midtones = 1.0f - pow(fabs(2.0f * clamp(p, 0.0f, 1.0f) - 1.0f), 2.0f);
    result += clarity * 0.8f * mid * (0.35f + 0.65f * midtones);

    float y2 = exp2(result);
    return float4(c * (y2 / y), s.a);
}

// Removes (amount > 0) or adds (amount < 0) atmospheric haze.
// coeff: guided coefficients turning perceptual luminance into transmission.
float4 lumora_dehaze(sample_t s, sample_t coeff, float4 airlight, float amount) {
    float3 c = max(s.rgb, float3(0.0f));
    float guide = lumoraToPerceptual(lumoraLuma(c));
    float t = clamp(coeff.r * guide + coeff.g, 0.0f, 1.0f);
    float3 a = airlight.rgb;
    if (amount >= 0.0f) {
        float3 clear = max((c - a) / max(t, 0.12f) + a, float3(0.0f));
        c = mix(c, clear, amount);
    } else {
        float h = -amount * 0.6f * (1.0f - 0.85f * t);
        c = mix(c, a, h);
    }
    return float4(c, s.a);
}

// Dark channel: min of RGB.
float4 lumora_darkChannel(sample_t s) {
    float d = min(min(s.r, s.g), s.b);
    return float4(d, d, d, 1.0f);
}

// Raw transmission estimate from the (min-filtered) dark channel.
float4 lumora_transmission(sample_t dark, float airlightMax) {
    float t = 1.0f - 0.95f * dark.r / max(airlightMax, 1.0e-3f);
    t = clamp(t, 0.0f, 1.0f);
    return float4(t, t, t, 1.0f);
}

}}
