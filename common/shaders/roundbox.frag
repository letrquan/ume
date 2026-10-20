#version 440
// RoundedBox.qml: a rounded box (fill, border, soft shadow), also cut to a
// second rounded box. Colors come premultiplied.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 box;           // x, y, w, h in the item
    float radius;
    vec4 fillPm;
    float borderWidth;
    vec4 borderPm;
    vec4 shadowPm;
    float shadowBlur;
    vec2 shadowOffset;
    vec4 clipBox;
    float clipRadius;
};

// Distance to a rounded box (< 0 inside).
float rounded(vec2 p, vec4 b, float r) {
    vec2 h = b.zw * 0.5;
    r = clamp(r, 0.0, min(h.x, h.y));
    vec2 q = abs(p - b.xy - h) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    // One screen pixel, in the item's units (it may be drawn scaled).
    float px = max(fwidth(p.x), 1e-4);
    float d = rounded(p, box, radius);
    float inside = clamp(0.5 - d / px, 0.0, 1.0);
    vec4 c = fillPm * inside;
    if (borderWidth > 0.0) {
        float ring = inside * clamp(0.5 + (d + borderWidth) / px, 0.0, 1.0);
        c = borderPm * ring + c * (1.0 - borderPm.a * ring);
    }
    if (shadowPm.a > 0.0) {
        float ds = rounded(p - shadowOffset, box, radius);
        // A blurred edge (about a Gaussian's, sigma = blur / 2).
        float s = 1.0 / (1.0 + exp(3.4 * ds / max(shadowBlur, 1.0)));
        c += shadowPm * s * (1.0 - c.a);
    }
    float keep = clamp(0.5 - rounded(p, clipBox, clipRadius) / px, 0.0, 1.0);
    fragColor = c * (keep * qt_Opacity);
}
