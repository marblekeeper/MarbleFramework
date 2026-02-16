#version 100
precision mediump float;

varying vec2 v_uv;
varying vec4 v_color;

uniform sampler2D u_texture;
uniform float u_vertexColorMix;
uniform float u_colorQuantization;

// RGB to HSL conversion logic
vec3 rgb2hsl(vec3 c) {
    float maxC = max(max(c.r, c.g), c.b);
    float minC = min(min(c.r, c.g), c.b);
    float l = (maxC + minC) * 0.5;
    float s = 0.0;
    float h = 0.0;
    
    if (maxC != minC) {
        float d = maxC - minC;
        s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);
        
        if (maxC == c.r) {
            h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
        } else if (maxC == c.g) {
            h = (c.b - c.r) / d + 2.0;
        } else {
            h = (c.r - c.g) / d + 4.0;
        }
        h /= 6.0;
    }
    
    return vec3(h, s, l);
}

// Helper for HSL to RGB
float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 0.5) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

// HSL to RGB conversion logic
vec3 hsl2rgb(vec3 hsl) {
    float h = hsl.x;
    float s = hsl.y;
    float l = hsl.z;
    
    if (s == 0.0) {
        return vec3(l);
    }
    
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    
    return vec3(
        hue2rgb(p, q, h + 1.0 / 3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0 / 3.0)
    );
}

// RS2-Style: Quantize to 16-bit HSL
// 6-bit hue (0-63), 3-bit sat (0-7), 7-bit lightness (0-127)
vec3 quantizeHSL16(vec3 rgb) {
    vec3 hsl = rgb2hsl(rgb);
    
    float h = floor(hsl.x * 63.0 + 0.5) / 63.0; 
    float s = floor(hsl.y * 7.0 + 0.5) / 7.0;   
    float l = floor(hsl.z * 127.0 + 0.5) / 127.0; 
    
    return hsl2rgb(vec3(h, s, l));
}

void main() {
    vec4 texColor = texture2D(u_texture, v_uv);
    
    // VECTORIZED OVERLAY BLEND
    // Calculates both possible outcomes for the overlay blend simultaneously
    vec3 low = 2.0 * texColor.rgb * v_color.rgb;
    vec3 high = 1.0 - 2.0 * (1.0 - texColor.rgb) * (1.0 - v_color.rgb);
    
    // Uses step() to choose between 'low' and 'high' per-channel, mimicking RS2 software rasterizer
    vec3 overlay = mix(low, high, step(0.5, v_color.rgb));
    
    vec3 finalRGB;
    
    // VERTEX COLOR MIXING LOGIC
    if (u_vertexColorMix < 0.5) {
        float factor = u_vertexColorMix * 2.0;
        finalRGB = mix(texColor.rgb, overlay, factor);
    } else {
        float factor = (u_vertexColorMix - 0.5) * 2.0;
        finalRGB = mix(overlay, v_color.rgb, factor);
    }
    
    float finalAlpha = texColor.a * v_color.a;

    // PASS 1: 16-bit HSL palette simulation
    finalRGB = quantizeHSL16(finalRGB);

    // PASS 2: Optional RGB banding (Posterization)
    if (u_colorQuantization > 0.0) {
        float levels = exp2(u_colorQuantization); 
        finalRGB = floor(finalRGB * levels + 0.5) / levels;
    }
    
    gl_FragColor = vec4(finalRGB, finalAlpha);
}