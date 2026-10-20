#version 440
// Glass.qml: the light on a glass edge, drawn over the plain tint. A thin
// rim that is bright where the edge faces the light (the top) and glints
// faintly on the opposite side, a soft glow just inside the lit edge, a thin
// light band all around (light bent by the edge) and a little shade inside
// the bottom edge, so the pane reads as thick glass.
// Everything stays inside the rounded box: nothing is drawn outside it
// (mango blurs every pixel that isn't fully transparent).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
    vec2 light;         // unit vector toward the light (y down: (0, -1) = straight above)
    float rimWidth;     // px
    float rim;          // alpha of the rim facing the light
    float rimBack;      // alpha of the glint on the far side
    float glow;         // alpha of the glow inside the lit edge
    float glowDepth;    // px
    float shade;        // alpha of the shade inside the bottom edge
    float shadeDepth;   // px
    float edge;         // alpha of the light band all around (light bent by the glass edge)
    float edgeDepth;    // px
};

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float px = max(fwidth(p.x), 1e-4);
    vec2 h = itemSize * 0.5;
    float r = clamp(radius, 0.0, min(h.x, h.y));
    vec2 c = p - h;
    vec2 q = abs(c) - h + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;     // < 0 inside
    // Outward direction of the nearest edge.
    vec2 s = vec2(c.x < 0.0 ? -1.0 : 1.0, c.y < 0.0 ? -1.0 : 1.0);
    vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) * s
           : (q.x > q.y ? vec2(s.x, 0.0) : vec2(0.0, s.y));

    float inside = clamp(0.5 - d / px, 0.0, 1.0);
    float depth = -d;                                                // px from the edge, inside
    float facing = dot(n, light);                                   // 1 = edge faces the light
    float ring = inside * clamp(0.5 + (d + rimWidth) / px, 0.0, 1.0);

    float lit = ring * (rim * pow(max(facing, 0.0), 1.6) + rimBack * pow(max(-facing, 0.0), 3.0));
    lit += inside * glow * pow(max(facing, 0.0), 2.0) * (1.0 - smoothstep(0.0, glowDepth, depth));
    lit += inside * edge * (1.0 - smoothstep(0.0, edgeDepth, depth));
    float dark = inside * shade * max(n.y, 0.0) * (1.0 - smoothstep(0.0, shadeDepth, depth));

    // White light over a dark shade, premultiplied.
    vec4 col = vec4(lit) + vec4(0.0, 0.0, 0.0, dark) * (1.0 - lit);
    fragColor = col * qt_Opacity;
}
