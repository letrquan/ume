#version 440
// The screenshot markup's blur tool (screenshot/Mark.qml): the picture cut
// into blocks, each one the average of its pixels, so the detail is gone.
// Blocks are counted in the picture's own pixels from the rectangle's
// top-left corner, so they are the same on screen and in the saved file
// (drawn at any size). Each block averages only what is inside the
// rectangle; samples sit on the corners between four pixels, so with even
// block sizes every pixel of the block counts exactly once.
// Built like the others: qsb --glsl "100 es,120,150,300 es,330" --hlsl 50
//   --msl 12 -o pixelate.frag.qsb pixelate.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 area;          // the rectangle, in the picture's pixels: x, y, w, h
    vec2 texSize;       // the picture's size in pixels
    float block;        // block size in the picture's pixels
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 start = max(floor(area.xy), vec2(0.0));
    vec2 end = min(ceil(area.xy + area.zw), texSize);
    vec2 p = area.xy + qt_TexCoord0 * area.zw;
    vec2 b0 = max(start + floor((p - start) / block) * block, start);
    vec2 b1 = min(b0 + block, end);
    vec2 size = max(b1 - b0, vec2(1.0));
    vec2 n = min(ceil(size / 2.0), vec2(16.0));
    vec2 stride = size / n;
    vec4 sum = vec4(0.0);
    for (int j = 0; j < 16; j++) {
        if (float(j) >= n.y)
            break;
        for (int i = 0; i < 16; i++) {
            if (float(i) >= n.x)
                break;
            vec2 q = b0 + (vec2(float(i), float(j)) + 0.5) * stride;
            // Level 0 always: a mipmapped picture would otherwise pick a
            // smaller level where neighbouring blocks differ.
            sum += textureLod(source, q / texSize, 0.0);
        }
    }
    fragColor = sum / (n.x * n.y) * qt_Opacity;
}
