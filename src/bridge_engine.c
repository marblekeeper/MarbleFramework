/*
 * Project Bridge - C Backend
 * Phase 8: Hardening 2D Render State & Resource Management
 * UPDATED: Font texture filtering fix + drawTextureRegion for sprite sheets
 */

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#ifdef _WIN32
#include <windows.h>
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

// --- Structures ---

typedef struct {
    GLuint program;
    GLint posAttrib;
    GLint uvAttrib;
    GLint colorAttrib;
    GLint textureUniform;
    GLint projectionUniform;
    GLint vertexColorMixUniform;
    GLint colorQuantizationUniform;
} ShaderState;

typedef struct {
    EGLDisplay display;
    EGLContext context;
    EGLSurface surface;
    EGLConfig config;
    
    GLuint vbo;
    
    ShaderState shader2D;
    ShaderState shader3D;
    
    GLuint fbo;
    GLuint fboTexture;
    GLuint fboDepth;
    int fboWidth;
    int fboHeight;
    int windowWidth;
    int windowHeight;

    int initialized;
} EngineState;

static EngineState g_engine = {0};

typedef struct { float x, y; float u, v; unsigned int color; } UIVertex;
typedef struct { float x, y, z; float u, v; unsigned int color; } Vertex3D;

// --- Helper Functions ---

static char* ReadFileToString(const char* filepath) {
    FILE* file = fopen(filepath, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    char* buffer = (char*)malloc(size + 1);
    if (!buffer) { fclose(file); return NULL; }
    fread(buffer, 1, size, file);
    buffer[size] = '\0';
    fclose(file);
    return buffer;
}

static GLuint CompileShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) return 0;
    return shader;
}

static GLuint CreateShaderProgramFromFiles(const char* vertPath, const char* fragPath) {
    char* vertSource = ReadFileToString(vertPath);
    char* fragSource = ReadFileToString(fragPath);
    if (!vertSource || !fragSource) {
        if(vertSource) free(vertSource);
        if(fragSource) free(fragSource);
        return 0;
    }
    GLuint vert = CompileShader(GL_VERTEX_SHADER, vertSource);
    GLuint frag = CompileShader(GL_FRAGMENT_SHADER, fragSource);
    free(vertSource); free(fragSource);
    if (!vert || !frag) return 0;
    
    GLuint prog = glCreateProgram();
    glAttachShader(prog, vert);
    glAttachShader(prog, frag);
    glLinkProgram(prog);
    glDeleteShader(vert); glDeleteShader(frag);
    return prog;
}

static void InitShaderState(ShaderState* state, GLuint program) {
    if (program == 0) { memset(state, 0, sizeof(ShaderState)); return; }
    state->program = program;
    state->posAttrib = glGetAttribLocation(program, "a_position");
    state->uvAttrib = glGetAttribLocation(program, "a_uv");
    state->colorAttrib = glGetAttribLocation(program, "a_color");
    state->textureUniform = glGetUniformLocation(program, "u_texture");
    state->projectionUniform = glGetUniformLocation(program, "u_projection");
    state->vertexColorMixUniform = glGetUniformLocation(program, "u_vertexColorMix");
    state->colorQuantizationUniform = glGetUniformLocation(program, "u_colorQuantization");
}

// --- API ---

EXPORT int InitEngine(void* windowHandle, int width, int height) {
    g_engine.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(g_engine.display, NULL, NULL);
    
    EGLint configAttribs[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_NONE };
    EGLint numConfigs;
    eglChooseConfig(g_engine.display, configAttribs, &g_engine.config, 1, &numConfigs);
    
    g_engine.surface = eglCreateWindowSurface(g_engine.display, g_engine.config, (EGLNativeWindowType)windowHandle, NULL);
    EGLint contextAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    g_engine.context = eglCreateContext(g_engine.display, g_engine.config, EGL_NO_CONTEXT, contextAttribs);
    eglMakeCurrent(g_engine.display, g_engine.surface, g_engine.surface, g_engine.context);
    
    // Load Shaders
    GLuint p2d = CreateShaderProgramFromFiles("assets/Content/Shaders/2d.vert", "assets/Content/Shaders/2d.frag");
    GLuint p3d = CreateShaderProgramFromFiles("assets/Content/Shaders/3d.vert", "assets/Content/Shaders/3d.frag");
    InitShaderState(&g_engine.shader2D, p2d);
    InitShaderState(&g_engine.shader3D, p3d);
    
    glGenBuffers(1, &g_engine.vbo);
    g_engine.windowWidth = width;
    g_engine.windowHeight = height;
    glViewport(0, 0, width, height);
    
    // Default Blend State
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    g_engine.initialized = 1;
    return 1;
}

EXPORT void UpdateViewport(int width, int height) {
    if (!g_engine.initialized) return;
    g_engine.windowWidth = width;
    g_engine.windowHeight = height;
    glViewport(0, 0, width, height);
}

// --- FBO Logic (Fixed Leak) ---

EXPORT void InitLowResBuffer(int width, int height) {
    if (!g_engine.initialized) return;
    
    // FIX: Clean up previous resources if they exist
    if (g_engine.fbo != 0) {
        glDeleteFramebuffers(1, &g_engine.fbo);
        glDeleteTextures(1, &g_engine.fboTexture);
        if (g_engine.fboDepth != 0) glDeleteRenderbuffers(1, &g_engine.fboDepth);
    }
    
    g_engine.fboWidth = width;
    g_engine.fboHeight = height;

    glGenFramebuffers(1, &g_engine.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, g_engine.fbo);

    glGenTextures(1, &g_engine.fboTexture);
    glBindTexture(GL_TEXTURE_2D, g_engine.fboTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_engine.fboTexture, 0);

    glGenRenderbuffers(1, &g_engine.fboDepth);
    glBindRenderbuffer(GL_RENDERBUFFER, g_engine.fboDepth);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, g_engine.fboDepth);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

EXPORT void BindLowResBuffer() {
    if (!g_engine.initialized || g_engine.fbo == 0) return;
    glBindFramebuffer(GL_FRAMEBUFFER, g_engine.fbo);
    glViewport(0, 0, g_engine.fboWidth, g_engine.fboHeight);
}

EXPORT void UnbindLowResBuffer() {
    if (!g_engine.initialized) return;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, g_engine.windowWidth, g_engine.windowHeight);
}

EXPORT int GetLowResTextureId() { return (int)g_engine.fboTexture; }

// --- Rendering State ---

EXPORT void SetProjectionMatrix(float* matrix) {
    if (!g_engine.initialized) return;
    if (g_engine.shader2D.program) {
        glUseProgram(g_engine.shader2D.program);
        glUniformMatrix4fv(g_engine.shader2D.projectionUniform, 1, GL_FALSE, matrix);
    }
    if (g_engine.shader3D.program) {
        glUseProgram(g_engine.shader3D.program);
        glUniformMatrix4fv(g_engine.shader3D.projectionUniform, 1, GL_FALSE, matrix);
    }
}

EXPORT void SetVertexColorMix(float mixFactor) {
    if (!g_engine.initialized) return;
    if (g_engine.shader2D.program) {
        glUseProgram(g_engine.shader2D.program);
        glUniform1f(g_engine.shader2D.vertexColorMixUniform, mixFactor);
    }
    if (g_engine.shader3D.program) {
        glUseProgram(g_engine.shader3D.program);
        glUniform1f(g_engine.shader3D.vertexColorMixUniform, mixFactor);
    }
}

EXPORT void SetColorQuantization(float bitDepth) {
    if (!g_engine.initialized) return;
    if (g_engine.shader2D.program) {
        glUseProgram(g_engine.shader2D.program);
        glUniform1f(g_engine.shader2D.colorQuantizationUniform, bitDepth);
    }
    if (g_engine.shader3D.program) {
        glUseProgram(g_engine.shader3D.program);
        glUniform1f(g_engine.shader3D.colorQuantizationUniform, bitDepth);
    }
}

EXPORT void SetDepthState(int enabled) {
    if (enabled) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
}

EXPORT void ClearScreen(float r, float g, float b, float a) {
    if (!g_engine.initialized) return;
    glClearColor(r, g, b, a);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

// --- Render Functions ---

EXPORT void Render3D(Vertex3D* vertices, int vertexCount, int primitiveType) {
    if (!g_engine.initialized || vertexCount == 0 || !g_engine.shader3D.program) return;
    
    ShaderState* shader = &g_engine.shader3D;
    glUseProgram(shader->program);
    glBindBuffer(GL_ARRAY_BUFFER, g_engine.vbo);
    glBufferData(GL_ARRAY_BUFFER, vertexCount * sizeof(Vertex3D), vertices, GL_DYNAMIC_DRAW);

    
    glEnableVertexAttribArray(shader->posAttrib);
    glVertexAttribPointer(shader->posAttrib, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex3D), (void*)0);
    glEnableVertexAttribArray(shader->uvAttrib);
    glVertexAttribPointer(shader->uvAttrib, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex3D), (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(shader->colorAttrib);
    glVertexAttribPointer(shader->colorAttrib, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(Vertex3D), (void*)(5 * sizeof(float)));
    
    glDrawArrays((primitiveType == 1) ? GL_LINES : GL_TRIANGLES, 0, vertexCount);
    
    glDisableVertexAttribArray(shader->posAttrib);
    glDisableVertexAttribArray(shader->uvAttrib);
    glDisableVertexAttribArray(shader->colorAttrib);
}

EXPORT void Render2D(UIVertex* vertices, int vertexCount) {
    if (!g_engine.initialized || vertexCount == 0 || !g_engine.shader2D.program) return;
    
    ShaderState* shader = &g_engine.shader2D;
    glUseProgram(shader->program);
    
    // HARDENING: Force Standard UI State
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // CRITICAL FIX: Reset VertexColorMix to 0.0 (Texture Mode) for UI
    glUniform1f(shader->vertexColorMixUniform, 0.0f);
    
    glBindBuffer(GL_ARRAY_BUFFER, g_engine.vbo);
    glBufferData(GL_ARRAY_BUFFER, vertexCount * sizeof(UIVertex), vertices, GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(shader->posAttrib);
    glVertexAttribPointer(shader->posAttrib, 2, GL_FLOAT, GL_FALSE, sizeof(UIVertex), (void*)0);
    glEnableVertexAttribArray(shader->uvAttrib);
    glVertexAttribPointer(shader->uvAttrib, 2, GL_FLOAT, GL_FALSE, sizeof(UIVertex), (void*)(2 * sizeof(float)));
    glEnableVertexAttribArray(shader->colorAttrib);
    glVertexAttribPointer(shader->colorAttrib, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(UIVertex), (void*)(4 * sizeof(float)));
    
    glDrawArrays(GL_TRIANGLES, 0, vertexCount);
    
    glDisableVertexAttribArray(shader->posAttrib);
    glDisableVertexAttribArray(shader->uvAttrib);
    glDisableVertexAttribArray(shader->colorAttrib);
}

EXPORT void RenderUI(UIVertex* vertices, int vertexCount) { Render2D(vertices, vertexCount); }

// --- Texture Functions ---

EXPORT int LoadTexture(const char* path, int* outW, int* outH) {
    if (!g_engine.initialized) return 0;
    int w, h, c;
    stbi_set_flip_vertically_on_load(0);
    unsigned char* data = stbi_load(path, &w, &h, &c, 4);
    if (!data) return 0;
    GLuint tex; glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
    
    // Use LINEAR for fonts, NEAREST for sprites/textures
    // Fonts should be in paths containing "font" or "Font"
    int useLinear = (strstr(path, "font") != NULL || strstr(path, "Font") != NULL);
    
    if (useLinear) {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    } else {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    stbi_image_free(data);
    if (outW) *outW = w; if (outH) *outH = h;
    return (int)tex;
}

EXPORT int CreateTextureFromData(unsigned char* data, int w, int h) {
    if (!g_engine.initialized) return 0;
    GLuint tex; glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    return (int)tex;
}

EXPORT int CreateWhiteTexture() {
    unsigned char w[4] = {255, 255, 255, 255};
    return CreateTextureFromData(w, 1, 1);
}

EXPORT void BindTexture(int id) {
    if (!g_engine.initialized) return;
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, (GLuint)id);
    if (g_engine.shader2D.program) { glUseProgram(g_engine.shader2D.program); glUniform1i(g_engine.shader2D.textureUniform, 0); }
    if (g_engine.shader3D.program) { glUseProgram(g_engine.shader3D.program); glUniform1i(g_engine.shader3D.textureUniform, 0); }
}

EXPORT void SetTextureFilter(int id, int mode) {
    if (!g_engine.initialized) return;
    glBindTexture(GL_TEXTURE_2D, (GLuint)id);
    GLint min = (mode == 2) ? GL_LINEAR_MIPMAP_LINEAR : ((mode == 1) ? GL_LINEAR : GL_NEAREST);
    GLint mag = (mode >= 1) ? GL_LINEAR : GL_NEAREST;
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, min);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, mag);
    glBindTexture(GL_TEXTURE_2D, 0);
}

EXPORT void BridgeSwapBuffers() { if (g_engine.initialized) eglSwapBuffers(g_engine.display, g_engine.surface); }

// --- Sprite Sheet Support: Draw Texture Region ---

EXPORT void DrawTextureRegion(int textureId, int texWidth, int texHeight,
                               float srcX, float srcY, float srcW, float srcH,
                               float dstX, float dstY, float dstW, float dstH) {
    if (!g_engine.initialized || !g_engine.shader2D.program) return;
    
    GLuint tex = (GLuint)textureId;
    
    // DEBUG: Always print for first few calls
    static int callCount = 0;
    if (callCount < 10) {
        printf("DrawTextureRegion #%d: tex=%d, texSize=%dx%d, src=(%.1f,%.1f %.1fx%.1f), dst=(%.1f,%.1f %.1fx%.1f)\n",
               callCount, textureId, texWidth, texHeight, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH);
    }
    
    // Calculate UV coordinates (normalized 0-1)
    float u0 = srcX / (float)texWidth;
    float v0 = srcY / (float)texHeight;
    float u1 = (srcX + srcW) / (float)texWidth;
    float v1 = (srcY + srcH) / (float)texHeight;
    
    // DEBUG: Print UV coordinates
    if (callCount < 10) {
        printf("  UV calculation: srcX/texW = %.1f/%d = %.3f, (srcX+srcW)/texW = (%.1f+%.1f)/%d = %.3f\n", 
               srcX, texWidth, u0, srcX, srcW, texWidth, u1);
        printf("  UV coords: u0=%.3f v0=%.3f u1=%.3f v1=%.3f\n", u0, v0, u1, v1);
        callCount++;
    }
    
    // Build quad vertices
    UIVertex vertices[6];
    unsigned int white = 0xFFFFFFFF;
    
    // Triangle 1
    vertices[0] = (UIVertex){dstX, dstY, u0, v0, white};
    vertices[1] = (UIVertex){dstX + dstW, dstY, u1, v0, white};
    vertices[2] = (UIVertex){dstX, dstY + dstH, u0, v1, white};
    
    // Triangle 2
    vertices[3] = (UIVertex){dstX + dstW, dstY, u1, v0, white};
    vertices[4] = (UIVertex){dstX + dstW, dstY + dstH, u1, v1, white};
    vertices[5] = (UIVertex){dstX, dstY + dstH, u0, v1, white};
    
    // Render using 2D shader
    ShaderState* shader = &g_engine.shader2D;
    glUseProgram(shader->program);
    
    // Force standard 2D state
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    // Ensure texture mode (not vertex color)
    glUniform1f(shader->vertexColorMixUniform, 0.0f);
    
    // Bind texture
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex);
    
    // CRITICAL: Set clamp mode to prevent sprite sheet bleeding
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glUniform1i(shader->textureUniform, 0);
    
    // Upload vertices
    glBindBuffer(GL_ARRAY_BUFFER, g_engine.vbo);
    glBufferData(GL_ARRAY_BUFFER, 6 * sizeof(UIVertex), vertices, GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(shader->posAttrib);
    glVertexAttribPointer(shader->posAttrib, 2, GL_FLOAT, GL_FALSE, sizeof(UIVertex), (void*)0);
    glEnableVertexAttribArray(shader->uvAttrib);
    glVertexAttribPointer(shader->uvAttrib, 2, GL_FLOAT, GL_FALSE, sizeof(UIVertex), (void*)(2 * sizeof(float)));
    glEnableVertexAttribArray(shader->colorAttrib);
    glVertexAttribPointer(shader->colorAttrib, 4, GL_UNSIGNED_BYTE, GL_TRUE, sizeof(UIVertex), (void*)(4 * sizeof(float)));
    
    glDrawArrays(GL_TRIANGLES, 0, 6);
    
    glDisableVertexAttribArray(shader->posAttrib);
    glDisableVertexAttribArray(shader->uvAttrib);
    glDisableVertexAttribArray(shader->colorAttrib);
    
    // Unbind texture to prevent state contamination
    glBindTexture(GL_TEXTURE_2D, 0);
}

EXPORT void ShutdownEngine() {
    if (!g_engine.initialized) return;
    if (g_engine.vbo) glDeleteBuffers(1, &g_engine.vbo);
    if (g_engine.fbo) glDeleteFramebuffers(1, &g_engine.fbo);
    if (g_engine.fboTexture) glDeleteTextures(1, &g_engine.fboTexture);
    if (g_engine.fboDepth) glDeleteRenderbuffers(1, &g_engine.fboDepth);
    if (g_engine.shader2D.program) glDeleteProgram(g_engine.shader2D.program);
    if (g_engine.shader3D.program) glDeleteProgram(g_engine.shader3D.program);
    eglMakeCurrent(g_engine.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglTerminate(g_engine.display);
    g_engine.initialized = 0;
}