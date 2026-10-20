#version 440
// RoundedTexture.qml: a picture with rounded corners, also cut to a second
// rounded box, straight from its texture.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
    vec4 clipBox;
    float clipRadius;
    vec4 uvRect;        // the part of the picture shown (crop)
};
layout(binding = 1) uniform sampler2D source;

float rounded(vec2 p, vec4 b, float r) {
    vec2 h = b.zw * 0.5;
    r = clamp(r, 0.0, min(h.x, h.y));
    vec2 q = abs(p - b.xy - h) - h + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float px = max(fwidth(p.x), 1e-4);
    float keep = clamp(0.5 - rounded(p, vec4(0.0, 0.0, itemSize), radius) / px, 0.0, 1.0)
               * clamp(0.5 - rounded(p, clipBox, clipRadius) / px, 0.0, 1.0);
    fragColor = texture(source, uvRect.xy + qt_TexCoord0 * uvRect.zw) * (keep * qt_Opacity);
}
