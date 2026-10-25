#version 440
// desktop/CardLyrics.qml: the lyrics list, sharp in the middle and
// softly blurred as it fades out over the top and bottom edges (one pass
// over the list's own layer, however many lines there are).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float fadeTop;      // px over which the top edge fades out
    float fadeBottom;   // px over which the bottom edge fades out
    float blurRadius;   // px at the very edge (none in the middle)
};
layout(binding = 1) uniform sampler2D source;

// 12 taps on a disk (golden angle spiral), radius 0..1.
const vec2 taps[12] = vec2[12](
    vec2( 0.2887,  0.0000), vec2(-0.3027,  0.2773), vec2( 0.0479, -0.5755),
    vec2( 0.4296,  0.4977), vec2(-0.7270, -0.1351), vec2( 0.6668, -0.4386),
    vec2(-0.2234,  0.8317), vec2(-0.4600, -0.7801), vec2( 0.9119,  0.2265),
    vec2(-0.9013,  0.4026), vec2( 0.3436, -0.9384), vec2( 0.3570,  0.9339)
);

void main() {
    float y = qt_TexCoord0.y * itemSize.y;
    float top = clamp(y / max(fadeTop, 1.0), 0.0, 1.0);
    float bottom = clamp((itemSize.y - y) / max(fadeBottom, 1.0), 0.0, 1.0);
    float keep = smoothstep(0.0, 1.0, top) * smoothstep(0.0, 1.0, bottom);
    // Blur grows toward the edges, where the text is fading anyway.
    float r = blurRadius * (1.0 - min(top, bottom));
    vec4 c = texture(source, qt_TexCoord0);
    if (r > 0.25) {
        vec2 px = r / itemSize;
        vec4 sum = c;
        for (int i = 0; i < 12; i++)
            sum += texture(source, qt_TexCoord0 + taps[i] * px);
        c = sum / 13.0;
    }
    fragColor = c * (keep * qt_Opacity);
}
