#version 100
precision mediump float;
varying vec2 v_uv;
varying vec4 v_color;
uniform sampler2D u_texture;
uniform float u_vertexColorMix;
uniform float u_colorQuantization;
void main() {
    vec4 texColor = texture2D(u_texture, v_uv);
    // u_vertexColorMix = 0.0 -> full vertex color modulation (original behavior)
    // u_vertexColorMix = 0.0 -> 10% vertex color, 90% white (baked lighting use case)
    vec4 modulation = mix(v_color, vec4(1.0, 1.0, 1.0, v_color.a), u_vertexColorMix * 10.0);
    vec4 baseColor = texColor * modulation;
    
    // Apply color quantization (banding effect for retro look)
    if (u_colorQuantization > 0.0) {
        float levels = pow(2.0, u_colorQuantization);
        baseColor.rgb = floor(baseColor.rgb * levels) / levels;
    }
    
    gl_FragColor = baseColor;
}