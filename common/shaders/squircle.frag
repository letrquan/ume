#version 440
// AppIcon.qml: the tile behind an app icon. A squircle (superellipse, the
// shape of macOS and iOS app icons) filled with a soft top-to-bottom
// gradient and a thin light rim that is strongest along the top edge, like
// light on glass. Colors come premultiplied.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 topPm;         // fill at the top
    vec4 bottomPm;      // fill at the bottom
    vec4 rimPm;         // light along the edge
    float rimWidth;     // in screen pixels
    float power;        // 2 = ellipse, ~5 = squircle, large = square
};

void main() {
    vec2 h = itemSize * 0.5;
    vec2 q = abs(qt_TexCoord0 * itemSize - h) / h;   // 0 in the middle, 1 on the edge
    float f = pow(pow(q.x, power) + pow(q.y, power), 1.0 / power);
    // Roughly the distance to the outline in screen pixels (< 0 inside).
    float d = (f - 1.0) / max(fwidth(f), 1e-5);
    float inside = clamp(0.5 - d, 0.0, 1.0);
    float y = qt_TexCoord0.y;
    vec4 c = mix(topPm, bottomPm, y) * inside;
    if (rimPm.a > 0.0) {
        float ring = inside * clamp(1.0 + d / max(rimWidth, 0.5), 0.0, 1.0);
        float k = ring * mix(1.0, 0.2, smoothstep(0.0, 0.6, y));
        c = rimPm * k + c * (1.0 - rimPm.a * k);
    }
    fragColor = c * qt_Opacity;
}
