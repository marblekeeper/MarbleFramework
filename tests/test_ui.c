/* test_ui.c - EMSCRIPTEN COMPATIBLE VERSION WITH ROBUST AUDIO AND JS INTEROP */
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/html5.h>
#endif

#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#ifndef __EMSCRIPTEN__
#include <SDL2/SDL_syswm.h>
#endif

/* --- Audio Includes (Minimp3) --- */
#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"
#include "minimp3_ex.h"

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "input_handler.h"

/* --- Bridge Engine Imports --- */
extern int InitEngine(void* windowHandle, int width, int height);
extern void ShutdownEngine();
extern void ClearScreen(float r, float g, float b, float a);
extern void RenderUI(void* vertices, int vertexCount);
extern void BridgeSwapBuffers();
extern int CreateWhiteTexture();
extern int CreateTextureFromData(unsigned char* data, int w, int h);
extern int LoadTexture(const char* path, int* outW, int* outH);
extern void BindTexture(int id);
extern void SetProjectionMatrix(float* matrix);
extern void UpdateViewport(int width, int height);
extern void DrawTextureRegion(int textureId, int texWidth, int texHeight,
                              float srcX, float srcY, float srcW, float srcH,
                              float dstX, float dstY, float dstW, float dstH);

/* --- Data Structures --- */
typedef struct { float x, y; float u, v; unsigned int color; } UIVertex;

typedef struct {
    float u0, v0, u1, v1;
    float width, height;
    float advance;
    float xoff, yoff;
} Glyph;

typedef struct {
    int textureId;
    int texWidth;
    int texHeight;
    Glyph glyphs[256];
    int loaded;
} Font;

/* --- Audio State --- */
typedef struct {
    SDL_AudioStream* stream; // Handles resampling/buffering
    int playing;
} AudioState;

AudioState g_audioState = {0};
SDL_AudioDeviceID g_audioDevice = 0;
SDL_AudioSpec g_deviceSpec = {0}; // Stores the actual hardware format

/* Global State */
#define MAX_UI_VERTS 10000
UIVertex g_uiVerts[MAX_UI_VERTS];
int g_uiVertCount = 0;

int g_whiteTexId = 0;
int g_currentTexId = 0;
Font g_activeFont = {0};

/* Emscripten main loop state */
#ifdef __EMSCRIPTEN__
typedef struct {
    SDL_Window* window;
    lua_State* L;
    int winW;
    int winH;
    int running;
} EmscriptenLoopData;

EmscriptenLoopData g_loopData = {0};
#endif

/* --- Embedded Fallback Font Data --- */
const unsigned char FONT_DATA[] = {
    0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x5F,0x00,0x00, 0x00,0x07,0x00,0x07,0x00, 0x14,0x7F,0x14,0x7F,0x14,
    0x24,0x2A,0x7F,0x2A,0x12, 0x23,0x13,0x08,0x64,0x62, 0x36,0x49,0x55,0x22,0x50, 0x00,0x05,0x03,0x00,0x00,
    0x00,0x1C,0x22,0x41,0x00, 0x00,0x41,0x22,0x1C,0x00, 0x14,0x08,0x3E,0x08,0x14, 0x08,0x08,0x3E,0x08,0x08,
    0x00,0x50,0x30,0x00,0x00, 0x08,0x08,0x08,0x08,0x08, 0x00,0x60,0x60,0x00,0x00, 0x20,0x10,0x08,0x04,0x02,
    0x3E,0x51,0x49,0x45,0x3E, 0x00,0x42,0x7F,0x40,0x00, 0x42,0x61,0x51,0x49,0x46, 0x21,0x41,0x45,0x4B,0x31,
    0x18,0x14,0x12,0x7F,0x10, 0x27,0x45,0x45,0x45,0x39, 0x3C,0x4A,0x49,0x49,0x30, 0x01,0x71,0x09,0x05,0x03,
    0x36,0x49,0x49,0x49,0x36, 0x06,0x49,0x49,0x29,0x1E, 0x00,0x36,0x36,0x00,0x00, 0x00,0x56,0x36,0x00,0x00,
    0x08,0x14,0x22,0x41,0x00, 0x14,0x14,0x14,0x14,0x14, 0x00,0x41,0x22,0x14,0x08, 0x02,0x01,0x51,0x09,0x06,
    0x32,0x49,0x79,0x41,0x3E, 0x7E,0x11,0x11,0x11,0x7E, 0x7F,0x49,0x49,0x49,0x36, 0x3E,0x41,0x41,0x41,0x22,
    0x7F,0x41,0x41,0x22,0x1C, 0x7F,0x49,0x49,0x49,0x41, 0x7F,0x09,0x09,0x09,0x01, 0x3E,0x41,0x49,0x49,0x7A,
    0x7F,0x08,0x08,0x08,0x7F, 0x00,0x41,0x7F,0x41,0x00, 0x20,0x40,0x41,0x3F,0x01, 0x7F,0x08,0x14,0x22,0x41,
    0x7F,0x40,0x40,0x40,0x40, 0x7F,0x02,0x0C,0x02,0x7F, 0x7F,0x04,0x08,0x10,0x7F, 0x3E,0x41,0x41,0x41,0x3E,
    0x7F,0x09,0x09,0x09,0x06, 0x3E,0x41,0x51,0x21,0x5E, 0x7F,0x09,0x19,0x29,0x46, 0x46,0x49,0x49,0x49,0x31,
    0x01,0x01,0x7F,0x01,0x01, 0x3F,0x40,0x40,0x40,0x3F, 0x1F,0x20,0x40,0x20,0x1F, 0x3F,0x40,0x38,0x40,0x3F,
    0x63,0x14,0x08,0x14,0x63, 0x07,0x08,0x70,0x08,0x07, 0x61,0x51,0x49,0x45,0x43, 0x00,0x7F,0x41,0x41,0x00,
    0x02,0x04,0x08,0x10,0x20, 0x00,0x41,0x41,0x7F,0x00, 0x04,0x02,0x01,0x02,0x04, 0x40,0x40,0x40,0x40,0x40,
    0x00,0x01,0x02,0x04,0x00, 0x20,0x54,0x54,0x54,0x78, 0x7F,0x48,0x44,0x44,0x38, 0x38,0x44,0x44,0x44,0x20,
    0x38,0x44,0x44,0x48,0x7F, 0x38,0x54,0x54,0x54,0x18, 0x08,0x7E,0x09,0x01,0x02, 0x0C,0x52,0x52,0x52,0x3E,
    0x7F,0x08,0x04,0x04,0x78, 0x00,0x44,0x7D,0x40,0x00, 0x20,0x40,0x44,0x3D,0x00, 0x7F,0x10,0x28,0x44,0x00,
    0x00,0x41,0x7F,0x40,0x00, 0x7C,0x04,0x18,0x04,0x78, 0x7C,0x08,0x04,0x04,0x78, 0x38,0x44,0x44,0x44,0x38,
    0x7C,0x14,0x14,0x14,0x08, 0x08,0x14,0x14,0x18,0x7C, 0x7C,0x08,0x04,0x04,0x08, 0x48,0x54,0x54,0x54,0x20,
    0x04,0x3F,0x44,0x40,0x20, 0x3C,0x40,0x40,0x20,0x7C, 0x1C,0x20,0x40,0x20,0x1C, 0x3C,0x40,0x30,0x40,0x3C,
    0x44,0x28,0x10,0x28,0x44, 0x0C,0x50,0x50,0x50,0x3C, 0x44,0x64,0x54,0x4C,0x44, 0x00,0x08,0x36,0x41,0x00,
    0x00,0x00,0x7F,0x00,0x00, 0x00,0x41,0x36,0x08,0x00, 0x10,0x08,0x08,0x10,0x08, 0x7F,0x7F,0x7F,0x7F,0x7F
};

/* --- JavaScript Interop (Emscripten only) --- */
#ifdef __EMSCRIPTEN__
// Call JavaScript and get string result
static char* bridge_callJS_internal(const char* jsCode) {
    char* result = (char*)EM_ASM_INT({
        try {
            var code = UTF8ToString($0);
            var result = eval(code);
            
            // Convert result to string
            var resultStr = String(result);
            
            // Allocate memory and copy string
            var len = lengthBytesUTF8(resultStr) + 1;
            var ptr = _malloc(len);
            stringToUTF8(resultStr, ptr, len);
            return ptr;
        } catch(e) {
            console.error("JavaScript eval error:", e);
            var errorStr = "";
            var len = lengthBytesUTF8(errorStr) + 1;
            var ptr = _malloc(len);
            stringToUTF8(errorStr, ptr, len);
            return ptr;
        }
    }, jsCode);
    
    return result;
}

// Optimized versions that call the window functions directly (MUCH faster)
static int bridge_wsIsConnected() {
    return EM_ASM_INT({
        return (typeof window.wsIsConnected === 'function') ? window.wsIsConnected() : 0;
    });
}

static char* bridge_wsGetMessage() {
    char* result = (char*)EM_ASM_INT({
        if (typeof window.wsGetMessage !== 'function') {
            return 0;
        }
        var msg = window.wsGetMessage();
        if (!msg || msg === "") {
            return 0;
        }
        var len = lengthBytesUTF8(msg) + 1;
        var ptr = _malloc(len);
        stringToUTF8(msg, ptr, len);
        return ptr;
    });
    return result;
}

static int bridge_wsSendMessage(const char* message) {
    return EM_ASM_INT({
        if (typeof window.wsSendMessage !== 'function') {
            return 0;
        }
        var msg = UTF8ToString($0);
        return window.wsSendMessage(msg);
    }, message);
}

#else
// Dummy for native builds
static char* bridge_callJS_internal(const char* jsCode) {
    return strdup("");
}
static int bridge_wsIsConnected() { return 0; }
static char* bridge_wsGetMessage() { return NULL; }
static int bridge_wsSendMessage(const char* msg) { return 0; }
#endif

/* --- Optimized Lua Bindings --- */
static int l_bridge_callJS(lua_State* L) {
    const char* jsCode = luaL_checkstring(L, 1);
    
    // Check for common optimized functions
    if (strcmp(jsCode, "wsIsConnected()") == 0) {
        lua_pushinteger(L, bridge_wsIsConnected());
        return 1;
    } else if (strcmp(jsCode, "wsGetMessage()") == 0) {
        char* msg = bridge_wsGetMessage();
        if (msg) {
            lua_pushstring(L, msg);
            free(msg);
        } else {
            lua_pushstring(L, "");
        }
        return 1;
    } else if (strncmp(jsCode, "wsSendMessage('", 15) == 0) {
        // Extract message from wsSendMessage('...')
        const char* msgStart = jsCode + 15;
        const char* msgEnd = strrchr(msgStart, '\'');
        if (msgEnd) {
            size_t len = msgEnd - msgStart;
            char* msg = (char*)malloc(len + 1);
            strncpy(msg, msgStart, len);
            msg[len] = '\0';
            int result = bridge_wsSendMessage(msg);
            free(msg);
            lua_pushinteger(L, result);
            return 1;
        }
    }
    
    // Fallback to generic eval
    char* result = bridge_callJS_internal(jsCode);
    
    if (result) {
        lua_pushstring(L, result);
        free(result);
    } else {
        lua_pushstring(L, "");
    }
    
    return 1;
}

/* --- Audio Functions --- */

// SDL calls this on a separate thread when it needs data
void AudioCallback(void* userdata, Uint8* stream, int len) {
    AudioState* state = (AudioState*)userdata;
    
    // Clear buffer to silence
    memset(stream, 0, len);
    
    if (!state->playing || !state->stream) return;
    
    // Pull resampled data from the stream directly into SDL's buffer
    int available = SDL_AudioStreamAvailable(state->stream);
    if (available > 0) {
        int bytesRead = SDL_AudioStreamGet(state->stream, stream, len);
        
        // If we drained the stream, we are done
        if (bytesRead < len) {
            // We could optionally loop here by reloading the stream if we kept the source
            // For now, simple one-shot
            if (SDL_AudioStreamAvailable(state->stream) == 0) {
                state->playing = 0;
            }
        }
    } else {
        state->playing = 0;
    }
}

// Lua Bridge: playSound(path)
static int l_playSound(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    
    // Load MP3 from disk
    mp3dec_t mp3d;
    mp3dec_file_info_t info;
    
    if (mp3dec_load(&mp3d, path, &info, NULL, NULL)) {
        printf("[Audio] Failed to load: %s\n", path);
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // Lock audio device while we manipulate the stream
    SDL_LockAudioDevice(g_audioDevice);
    
    // Clean up previous stream
    if (g_audioState.stream) {
        SDL_FreeAudioStream(g_audioState.stream);
    }
    
    // Create a new stream that converts FROM the MP3 format TO the Device format
    // This handles Pitch (Sample Rate) and Channels (Mono/Stereo) automatically
    g_audioState.stream = SDL_NewAudioStream(
        AUDIO_S16,          // Source Format (minimp3 always outputs S16)
        info.channels,      // Source Channels (from MP3)
        info.hz,            // Source Rate (from MP3)
        g_deviceSpec.format,// Dest Format (Device)
        g_deviceSpec.channels, // Dest Channels (Device)
        g_deviceSpec.freq   // Dest Rate (Device)
    );
    
    if (g_audioState.stream) {
        // Feed the entire decoded buffer into the stream
        // Note: info.samples is total samples (frames * channels), sizeof(int16) is 2 bytes
        int res = SDL_AudioStreamPut(g_audioState.stream, info.buffer, info.samples * sizeof(int16_t));
        if (res == 0) {
            g_audioState.playing = 1;
            printf("[Audio] Playing %s (Rate: %dHz -> %dHz)\n", path, info.hz, g_deviceSpec.freq);
        } else {
            printf("[Audio] Stream Put failed: %s\n", SDL_GetError());
        }
    } else {
        printf("[Audio] Stream creation failed: %s\n", SDL_GetError());
    }
    
    SDL_UnlockAudioDevice(g_audioDevice);
    
    // We can free the raw MP3 buffer now because SDL_AudioStream has made a copy
    free(info.buffer);
    
    lua_pushboolean(L, 1);
    return 1;
}


void FlushBatch() {
    if (g_uiVertCount > 0) {
        BindTexture(g_currentTexId);
        RenderUI(g_uiVerts, g_uiVertCount);
        g_uiVertCount = 0;
    }
}

void SetBatchTexture(int id) {
    if (g_currentTexId != id) {
        FlushBatch();
        g_currentTexId = id;
    }
}

void GenerateDebugFont() {
    printf("[System] Generating Procedural Debug Font...\n");
    int charW = 8, charH = 8, cols = 16, rows = 8;
    int texW = cols * charW, texH = rows * charH;
    int size = texW * texH * 4;
    unsigned char* data = (unsigned char*)malloc(size);
    memset(data, 0, size);
    
    for (int i = 0; i < 96; i++) {
        int ascii = i + 32, col = ascii % cols, row = ascii / cols;
        int startX = col * charW, startY = row * charH;
        const unsigned char* glyph = &FONT_DATA[i * 5];
        for (int x = 0; x < 5; x++) {
            unsigned char strip = glyph[x];
            for (int y = 0; y < 8; y++) {
                if ((strip >> y) & 1) {
                    int px = startX + x + 1, py = startY + y + 1;
                    int idx = (py * texW + px) * 4;
                    if (idx < size - 4) {
                        data[idx+0] = 255; data[idx+1] = 255; 
                        data[idx+2] = 255; data[idx+3] = 255;
                    }
                }
            }
        }
    }
    
    g_activeFont.textureId = CreateTextureFromData(data, texW, texH);
    g_activeFont.texWidth = texW;
    g_activeFont.texHeight = texH;
    free(data);
    
    for (int i = 0; i < 256; i++) {
        int col = i % cols, row = i / cols;
        g_activeFont.glyphs[i].u0 = (float)(col * charW) / texW;
        g_activeFont.glyphs[i].v0 = (float)(row * charH) / texH;
        g_activeFont.glyphs[i].u1 = (float)((col+1) * charW) / texW;
        g_activeFont.glyphs[i].v1 = (float)((row+1) * charH) / texH;
        g_activeFont.glyphs[i].width = (float)charW;
        g_activeFont.glyphs[i].height = (float)charH;
        g_activeFont.glyphs[i].advance = (float)charW;
        g_activeFont.glyphs[i].xoff = 0;
        g_activeFont.glyphs[i].yoff = 0;
    }
    g_activeFont.loaded = 1;
}

int GetValue(const char* line, const char* key) {
    char search[64];
    sprintf(search, "%s=", key);
    char* found = strstr(line, search);
    if (!found) return 0;
    return atoi(found + strlen(search));
}

void LoadFontFromFile(const char* name) {
    char path[256];
#ifdef __EMSCRIPTEN__
    sprintf(path, "/assets/Content/%s.fnt", name);
#else
    sprintf(path, "assets/Content/%s.fnt", name);
#endif
    FILE* file = fopen(path, "r");
    if (!file) { printf("[System] Font file not found: %s - Using debug font\n", path); GenerateDebugFont(); return; }
    printf("[System] Loading font from %s...\n", path);
    char line[512], texFilename[256] = {0};
    while (fgets(line, sizeof(line), file)) {
        if (strstr(line, "page id=0")) {
            char* fileStart = strstr(line, "file=\"");
            if (fileStart) {
                fileStart += 6;
                char* fileEnd = strchr(fileStart, '"');
                if (fileEnd) {
                    int len = (int)(fileEnd - fileStart);
                    if (len < (int)sizeof(texFilename)) { strncpy(texFilename, fileStart, len); texFilename[len] = '\0'; }
                }
            }
        }
        if (strstr(line, "char id=")) {
            int id = GetValue(line, "id");
            if (id >= 0 && id < 256) {
                int x = GetValue(line, "x"), y = GetValue(line, "y");
                int width = GetValue(line, "width"), height = GetValue(line, "height");
                int xoffset = GetValue(line, "xoffset"), yoffset = GetValue(line, "yoffset");
                int xadvance = GetValue(line, "xadvance");
                g_activeFont.glyphs[id].u0 = (float)x / g_activeFont.texWidth;
                g_activeFont.glyphs[id].v0 = (float)y / g_activeFont.texHeight;
                g_activeFont.glyphs[id].u1 = (float)(x + width) / g_activeFont.texWidth;
                g_activeFont.glyphs[id].v1 = (float)(y + height) / g_activeFont.texHeight;
                g_activeFont.glyphs[id].width = (float)width;
                g_activeFont.glyphs[id].height = (float)height;
                g_activeFont.glyphs[id].advance = (float)xadvance;
                g_activeFont.glyphs[id].xoff = (float)xoffset;
                g_activeFont.glyphs[id].yoff = (float)yoffset;
            }
        }
    }
    fclose(file);
    if (texFilename[0] != '\0') {
        char texPath[512];
#ifdef __EMSCRIPTEN__
        sprintf(texPath, "/assets/Content/%s", texFilename);
#else
        sprintf(texPath, "assets/Content/%s", texFilename);
#endif
        int w, h;
        g_activeFont.textureId = LoadTexture(texPath, &w, &h);
        g_activeFont.texWidth = w;
        g_activeFont.texHeight = h;
        if (g_activeFont.textureId) { g_activeFont.loaded = 1; printf("[System] Font texture loaded: %s\n", texPath); }
        else { printf("[System] Font texture failed to load: %s\n", texPath); GenerateDebugFont(); }
    } else { printf("[System] No texture filename found\n"); GenerateDebugFont(); }
}

static int l_draw_rect(lua_State* L) {
    static int callCount = 0;
    callCount++;
    if (callCount == 1) {
        printf("[System] bridge.drawRect called for the first time!\n");
    }
    
    SetBatchTexture(g_whiteTexId);
    float x = (float)luaL_checknumber(L, 1), y = (float)luaL_checknumber(L, 2);
    float w = (float)luaL_checknumber(L, 3), h = (float)luaL_checknumber(L, 4);
    int r = (int)luaL_checknumber(L, 5), g = (int)luaL_checknumber(L, 6);
    int b = (int)luaL_checknumber(L, 7), a = (int)luaL_checknumber(L, 8);
    unsigned int color = (a << 24) | (b << 16) | (g << 8) | r;
    if (g_uiVertCount + 6 >= MAX_UI_VERTS) FlushBatch();
    UIVertex* v = &g_uiVerts[g_uiVertCount];
    v[0] = (UIVertex){x, y, 0,0, color}; v[1] = (UIVertex){x+w, y, 1,0, color}; v[2] = (UIVertex){x, y+h, 0,1, color};
    v[3] = (UIVertex){x+w, y, 1,0, color}; v[4] = (UIVertex){x+w, y+h, 1,1, color}; v[5] = (UIVertex){x, y+h, 0,1, color};
    g_uiVertCount += 6;
    return 0;
}

static int l_draw_text(lua_State* L) {
    static int callCount = 0;
    callCount++;
    if (callCount == 1) {
        printf("[System] bridge.drawText called for the first time!\n");
    }
    
    if (!g_activeFont.loaded) return 0;
    const char* text = luaL_checkstring(L, 1);
    float x = (float)luaL_checknumber(L, 2), y = (float)luaL_checknumber(L, 3);
    int r = (int)luaL_checknumber(L, 4), g = (int)luaL_checknumber(L, 5);
    int b = (int)luaL_checknumber(L, 6), a = (int)luaL_checknumber(L, 7);
    unsigned int color = (a << 24) | (b << 16) | (g << 8) | r;
    SetBatchTexture(g_activeFont.textureId);
    float curX = x, curY = y;
    for (int i = 0; text[i] != '\0'; i++) {
        unsigned char c = (unsigned char)text[i];
        if (c == '\n') { curX = x; curY += g_activeFont.glyphs[(int)'A'].height; continue; }
        Glyph* glyph = &g_activeFont.glyphs[c];
        if (g_uiVertCount + 6 >= MAX_UI_VERTS) FlushBatch();
        float gx = curX + glyph->xoff, gy = curY + glyph->yoff;
        float gw = glyph->width, gh = glyph->height;
        UIVertex* v = &g_uiVerts[g_uiVertCount];
        v[0] = (UIVertex){gx, gy, glyph->u0, glyph->v0, color};
        v[1] = (UIVertex){gx+gw, gy, glyph->u1, glyph->v0, color};
        v[2] = (UIVertex){gx, gy+gh, glyph->u0, glyph->v1, color};
        v[3] = (UIVertex){gx+gw, gy, glyph->u1, glyph->v0, color};
        v[4] = (UIVertex){gx+gw, gy+gh, glyph->u1, glyph->v1, color};
        v[5] = (UIVertex){gx, gy+gh, glyph->u0, glyph->v1, color};
        g_uiVertCount += 6;
        curX += glyph->advance;
    }
    return 0;
}

static int l_measure_text(lua_State* L) {
    if (!g_activeFont.loaded) { lua_pushnumber(L, 0); lua_pushnumber(L, 0); return 2; }
    const char* text = luaL_checkstring(L, 1);
    float width = 0, height = 0;
    for (int i = 0; text[i] != '\0'; i++) {
        unsigned char c = (unsigned char)text[i];
        Glyph* glyph = &g_activeFont.glyphs[c];
        width += glyph->advance;
        if (glyph->height > height) height = glyph->height;
    }
    lua_pushnumber(L, width);
    lua_pushnumber(L, height);
    return 2;
}

static int l_draw_border(lua_State* L) {
    SetBatchTexture(g_whiteTexId);
    float x = (float)luaL_checknumber(L, 1), y = (float)luaL_checknumber(L, 2);
    float w = (float)luaL_checknumber(L, 3), h = (float)luaL_checknumber(L, 4);
    int r = (int)luaL_checknumber(L, 5), g = (int)luaL_checknumber(L, 6);
    int b = (int)luaL_checknumber(L, 7), a = (int)luaL_checknumber(L, 8);
    float thickness = (float)luaL_checknumber(L, 9);
    unsigned int color = (a << 24) | (b << 16) | (g << 8) | r;
    if (g_uiVertCount + 24 >= MAX_UI_VERTS) FlushBatch();
    UIVertex* v = &g_uiVerts[g_uiVertCount];
    v[0] = (UIVertex){x, y, 0,0, color}; v[1] = (UIVertex){x+w, y, 1,0, color}; v[2] = (UIVertex){x, y+thickness, 0,1, color};
    v[3] = (UIVertex){x+w, y, 1,0, color}; v[4] = (UIVertex){x+w, y+thickness, 1,1, color}; v[5] = (UIVertex){x, y+thickness, 0,1, color};
    v[6] = (UIVertex){x, y+h-thickness, 0,0, color}; v[7] = (UIVertex){x+w, y+h-thickness, 1,0, color}; v[8] = (UIVertex){x, y+h, 0,1, color};
    v[9] = (UIVertex){x+w, y+h-thickness, 1,0, color}; v[10] = (UIVertex){x+w, y+h, 1,1, color}; v[11] = (UIVertex){x, y+h, 0,1, color};
    v[12] = (UIVertex){x, y, 0,0, color}; v[13] = (UIVertex){x+thickness, y, 1,0, color}; v[14] = (UIVertex){x, y+h, 0,1, color};
    v[15] = (UIVertex){x+thickness, y, 1,0, color}; v[16] = (UIVertex){x+thickness, y+h, 1,1, color}; v[17] = (UIVertex){x, y+h, 0,1, color};
    v[18] = (UIVertex){x+w-thickness, y, 0,0, color}; v[19] = (UIVertex){x+w, y, 1,0, color}; v[20] = (UIVertex){x+w-thickness, y+h, 0,1, color};
    v[21] = (UIVertex){x+w, y, 1,0, color}; v[22] = (UIVertex){x+w, y+h, 1,1, color}; v[23] = (UIVertex){x+w-thickness, y+h, 0,1, color};
    g_uiVertCount += 24;
    return 0;
}

static int l_draw_texture(lua_State* L) {
    int texId = (int)luaL_checknumber(L, 1);
    float x = (float)luaL_checknumber(L, 2), y = (float)luaL_checknumber(L, 3);
    float w = (float)luaL_checknumber(L, 4), h = (float)luaL_checknumber(L, 5);
    unsigned int color = 0xFFFFFFFF;
    SetBatchTexture(texId);
    if (g_uiVertCount + 6 >= MAX_UI_VERTS) FlushBatch();
    UIVertex* v = &g_uiVerts[g_uiVertCount];
    v[0] = (UIVertex){x, y, 0,0, color}; v[1] = (UIVertex){x+w, y, 1,0, color}; v[2] = (UIVertex){x, y+h, 0,1, color};
    v[3] = (UIVertex){x+w, y, 1,0, color}; v[4] = (UIVertex){x+w, y+h, 1,1, color}; v[5] = (UIVertex){x, y+h, 0,1, color};
    g_uiVertCount += 6;
    return 0;
}

static int l_load_texture(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    int w, h;
    int texId = LoadTexture(path, &w, &h);
    if (texId == 0) { lua_pushnil(L); return 1; }
    lua_pushnumber(L, texId);
    lua_pushnumber(L, w);
    lua_pushnumber(L, h);
    return 3;
}

static int l_draw_texture_region(lua_State* L) {
    int texId = (int)luaL_checknumber(L, 1);
    int texW = (int)luaL_checknumber(L, 2);
    int texH = (int)luaL_checknumber(L, 3);
    float srcX = (float)luaL_checknumber(L, 4);
    float srcY = (float)luaL_checknumber(L, 5);
    float srcW = (float)luaL_checknumber(L, 6);
    float srcH = (float)luaL_checknumber(L, 7);
    float dstX = (float)luaL_checknumber(L, 8);
    float dstY = (float)luaL_checknumber(L, 9);
    float dstW = (float)luaL_checknumber(L, 10);
    float dstH = (float)luaL_checknumber(L, 11);
    
    // Need to flush before changing render state
    FlushBatch();
    
    // Call the native function directly
    DrawTextureRegion(texId, texW, texH, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH);
    
    return 0;
}

static int l_write_file(lua_State* L) {
    const char* path = luaL_checkstring(L, 1);
    const char* data = luaL_checkstring(L, 2);
    FILE* file = fopen(path, "w");
    if (!file) { lua_pushboolean(L, 0); return 1; }
    fprintf(file, "%s", data);
    fclose(file);
    printf("[System] Wrote file: %s\n", path);
    lua_pushboolean(L, 1);
    return 1;
}

/* --- Input bridge for Lua --- */
static int l_getKeyState(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    lua_pushinteger(L, Input_GetKeyState(name));
    return 1;
}

void UpdateProjection(int w, int h) {
    float L = 0, R = (float)w, T = 0, B = (float)h;
    float ortho[16] = {2.0f/(R-L), 0, 0, 0, 0, 2.0f/(T-B), 0, 0, 0, 0, -1, 0, -(R+L)/(R-L), -(T+B)/(T-B), 0, 1};
    SetProjectionMatrix(ortho);
    UpdateViewport(w, h);
}

#ifdef __EMSCRIPTEN__
void emscripten_main_loop() {
    EmscriptenLoopData* data = &g_loopData;
    
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        Input_ProcessEvent(&e);
        if (e.type == SDL_QUIT) {
            data->running = 0;
            emscripten_cancel_main_loop();
            return;
        }
        if (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_RESIZED) {
            data->winW = e.window.data1;
            data->winH = e.window.data2;
            UpdateProjection(data->winW, data->winH);
        }
        if (e.type == SDL_KEYDOWN) {
            const char* keyName = SDL_GetKeyName(e.key.keysym.sym);
            lua_getglobal(data->L, "HandleKeyPress");
            if (lua_isfunction(data->L, -1)) {
                char simpleName[32] = {0};
                if (strcmp(keyName, "Up") == 0) strcpy(simpleName, "up");
                else if (strcmp(keyName, "Down") == 0) strcpy(simpleName, "down");
                else if (strcmp(keyName, "Left") == 0) strcpy(simpleName, "left");
                else if (strcmp(keyName, "Right") == 0) strcpy(simpleName, "right");
                else if (strcmp(keyName, "Space") == 0) strcpy(simpleName, "space");
                else if (strlen(keyName) == 1) { simpleName[0] = keyName[0]; simpleName[1] = '\0'; }
                else strncpy(simpleName, keyName, sizeof(simpleName) - 1);
                lua_pushstring(data->L, simpleName);
                if (lua_pcall(data->L, 1, 0, 0) != LUA_OK) {
                    printf("HandleKeyPress Error: %s\n", lua_tostring(data->L, -1));
                    lua_pop(data->L, 1);
                }
            } else {
                lua_pop(data->L, 1);
            }
        }
    }
    
    int mouseX = 0, mouseY = 0;
    Uint32 buttons = SDL_GetMouseState(&mouseX, &mouseY);
    int mouseDown = (buttons & SDL_BUTTON(SDL_BUTTON_LEFT)) != 0;
    
    lua_getglobal(data->L, "UpdateUI");
    lua_pushnumber(data->L, mouseX);
    lua_pushnumber(data->L, mouseY);
    lua_pushboolean(data->L, mouseDown);
    lua_pushnumber(data->L, data->winW);
    lua_pushnumber(data->L, data->winH);
    if (lua_pcall(data->L, 5, 0, 0) != LUA_OK) {
        printf("Lua Update Error: %s\n", lua_tostring(data->L, -1));
        lua_pop(data->L, 1);
    }
    
    ClearScreen(0.1f, 0.1f, 0.15f, 1.0f);
    g_uiVertCount = 0;
    
    lua_getglobal(data->L, "DrawUI");
    if (lua_pcall(data->L, 0, 0, 0) != LUA_OK) {
        printf("Lua Draw Error: %s\n", lua_tostring(data->L, -1));
        lua_pop(data->L, 1);
    }
    
    FlushBatch();
    BridgeSwapBuffers();
}
#endif

int main(int argc, char** argv) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) return 1;
    
    Input_Init();
    
    /* --- Audio Setup --- */
    SDL_AudioSpec want;
    SDL_zero(want);
    want.freq = 44100;
    want.format = AUDIO_S16;
    want.channels = 2;
    want.samples = 2048;
    want.callback = AudioCallback;
    want.userdata = &g_audioState;
    
    // We remove the strict flag (last 0 -> SDL_AUDIO_ALLOW_ANY_CHANGE)
    // so SDL can give us the native hardware rate if needed.
    // However, for stream simplicity, we'll ask for what we want but capture what we get.
    g_audioDevice = SDL_OpenAudioDevice(NULL, 0, &want, &g_deviceSpec, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE | SDL_AUDIO_ALLOW_CHANNELS_CHANGE);
    
    if (g_audioDevice == 0) {
        printf("Failed to open audio: %s\n", SDL_GetError());
    } else {
        printf("Audio initialized. Device Rate: %dHz Channels: %d\n", g_deviceSpec.freq, g_deviceSpec.channels);
        SDL_PauseAudioDevice(g_audioDevice, 0);
    }

    int winW = 1024, winH = 768;
    SDL_Window* window = SDL_CreateWindow("Project Bridge Lua UI", 
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 
        winW, winH, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE);
    
    void* nativeWindow = NULL;
#ifndef __EMSCRIPTEN__
    SDL_SysWMinfo wmInfo;
    SDL_VERSION(&wmInfo.version);
    SDL_GetWindowWMInfo(window, &wmInfo);
    nativeWindow = (void*)wmInfo.info.win.window;
#endif
    
    InitEngine(nativeWindow, winW, winH);
    g_whiteTexId = CreateWhiteTexture();
    g_currentTexId = g_whiteTexId;
    LoadFontFromFile("custom");
    UpdateProjection(winW, winH);

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    
#ifdef __EMSCRIPTEN__
    // Emscripten debug: show what files are available
    printf("[System] Emscripten build - checking virtual filesystem...\n");
    printf("[System] Attempting to list root directory...\n");
    // Try to open and list what's in the virtual FS
#endif
    
    lua_newtable(L);
    lua_pushcfunction(L, l_draw_rect); lua_setfield(L, -2, "drawRect");
    lua_pushcfunction(L, l_draw_text); lua_setfield(L, -2, "drawText");
    lua_pushcfunction(L, l_measure_text); lua_setfield(L, -2, "measureText");
    lua_pushcfunction(L, l_draw_border); lua_setfield(L, -2, "drawBorder");
    lua_pushcfunction(L, l_write_file); lua_setfield(L, -2, "writeFile");
    lua_pushcfunction(L, l_load_texture); lua_setfield(L, -2, "loadTexture");
    lua_pushcfunction(L, l_draw_texture); lua_setfield(L, -2, "drawTexture");
    lua_pushcfunction(L, l_draw_texture_region); lua_setfield(L, -2, "DrawTextureRegion");
    lua_pushcfunction(L, l_getKeyState); lua_setfield(L, -2, "getKeyState");
    lua_pushcfunction(L, l_playSound); lua_setfield(L, -2, "playSound");
    lua_pushcfunction(L, l_bridge_callJS); lua_setfield(L, -2, "callJS"); // NEW: JavaScript interop
    lua_setglobal(L, "bridge");

    const char* scriptName = (argc > 1) ? argv[1] : "ohko";
    char scriptPath[256];
    char frameworkPath[256];

#ifdef __EMSCRIPTEN__
    // Emscripten uses absolute paths in virtual filesystem
    strcpy(frameworkPath, "/scripts/core/framework.lua");
#else
    // Native uses relative paths
    strcpy(frameworkPath, "scripts/core/framework.lua");
#endif

// Set up package paths FIRST
    if (strcmp(scriptName, "MindMarr") == 0) {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        const char* currentPath = lua_tostring(L, -1);
        char newPath[1024];
#ifdef __EMSCRIPTEN__
        snprintf(newPath, sizeof(newPath), "%s;/MindMarr/?.lua;/scripts/core/?.lua", currentPath);
        sprintf(scriptPath, "/MindMarr/MindMarr.lua");
#else
        snprintf(newPath, sizeof(newPath), "%s;MindMarr/?.lua;scripts/core/?.lua", currentPath);
        sprintf(scriptPath, "MindMarr/MindMarr.lua");
#endif
        lua_pop(L, 1);
        lua_pushstring(L, newPath);
        lua_setfield(L, -2, "path");
        lua_pop(L, 1);
        
        printf("[System] Lua package.path set for MindMarr\n");

    } else if (strcmp(scriptName, "NetRogue") == 0) {
        // NetRogue: ClayMarble renderer + MarbleNet TCP protocol
        // Needs: NetRogue/ folder, project root (protocol.lua), and LuaSocket

        // Set package.path: NetRogue folder + project root + core scripts
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        const char* currentPath = lua_tostring(L, -1);
        char newPath[2048];
#ifdef __EMSCRIPTEN__
        snprintf(newPath, sizeof(newPath),
            "%s;/NetRogue/?.lua;/scripts/core/?.lua;/?.lua",
            currentPath);
        sprintf(scriptPath, "/NetRogue/NetRogue.lua");
#else
        // Add: NetRogue/, project root, scripts/core, and MSYS2 luarocks paths
        snprintf(newPath, sizeof(newPath),
            "%s"
            ";NetRogue/?.lua"
            ";scripts/core/?.lua"
            ";./?.lua"
            ";C:/msys64/ucrt64/share/lua/5.4/?.lua"
            ";C:/msys64/ucrt64/share/lua/5.4/?/init.lua"
            ";C:/msys64/ucrt64/lib/lua/5.4/?.lua"
            ";C:/msys64/ucrt64/lib/lua/5.4/?/init.lua"
            ";C:/msys64/ucrt64/lib/luarocks/rocks-5.4/luasocket/3.1.0-1/lua/?.lua",
            currentPath);
        sprintf(scriptPath, "NetRogue/NetRogue.lua");
#endif
        lua_pop(L, 1);
        lua_pushstring(L, newPath);
        lua_setfield(L, -2, "path");

        // Set package.cpath: LuaSocket native modules (.dll / .so)
        lua_getfield(L, -1, "cpath");
        const char* currentCPath = lua_tostring(L, -1);
        char newCPath[2048];
#ifdef __EMSCRIPTEN__
        snprintf(newCPath, sizeof(newCPath), "%s", currentCPath);
#else
        snprintf(newCPath, sizeof(newCPath),
            "%s"
            ";C:/msys64/ucrt64/lib/lua/5.4/?.dll"
            ";C:/msys64/ucrt64/lib/lua/5.4/?/core.dll"
            ";C:/msys64/ucrt64/lib/lua/5.4/socket/?.dll",
            currentCPath);
#endif
        lua_pop(L, 1);
        lua_pushstring(L, newCPath);
        lua_setfield(L, -2, "cpath");
        lua_pop(L, 1);
        
        printf("[System] Lua package paths set for NetRogue (with LuaSocket)\n");

    } else {
        lua_getglobal(L, "package");
        lua_getfield(L, -1, "path");
        const char* currentPath = lua_tostring(L, -1);
        char newPath[1024];
#ifdef __EMSCRIPTEN__
        snprintf(newPath, sizeof(newPath), "%s;/scripts/demos/?.lua;/scripts/core/?.lua", currentPath);
        sprintf(scriptPath, "/scripts/demos/%s.lua", scriptName);
#else
        snprintf(newPath, sizeof(newPath), "%s;scripts/demos/?.lua;scripts/core/?.lua", currentPath);
        sprintf(scriptPath, "scripts/demos/%s.lua", scriptName);
#endif
        lua_pop(L, 1);
        lua_pushstring(L, newPath);
        lua_setfield(L, -2, "path");
        lua_pop(L, 1);
    }


    printf("[System] Loading framework.lua...\n");
    if (luaL_dofile(L, frameworkPath) != LUA_OK) {
        printf("Error loading framework: %s\n", lua_tostring(L, -1));
        return 1;
    }
    printf("[System] Framework loaded successfully\n");

    printf("[System] Loading %s...\n", scriptPath);
    if (luaL_dofile(L, scriptPath) != LUA_OK) {
        printf("Error loading %s: %s\n", scriptPath, lua_tostring(L, -1));
        lua_pop(L, 1);
        return 1;
    }
    printf("[System] Script loaded successfully\n");
    
    // Debug: Check if game state is accessible
    if (strcmp(scriptName, "MindMarr") == 0) {
        lua_getglobal(L, "state");
        if (lua_istable(L, -1)) {
            lua_getfield(L, -1, "game");
            if (lua_istable(L, -1)) {
                lua_getfield(L, -1, "state");
                if (lua_isstring(L, -1)) {
                    printf("[System] MindMarr game.state = '%s'\n", lua_tostring(L, -1));
                }
                lua_pop(L, 1);
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    
    // Verify required functions exist
    lua_getglobal(L, "UpdateUI");
    if (!lua_isfunction(L, -1)) {
        printf("[ERROR] UpdateUI function not found in %s\n", scriptPath);
        return 1;
    }
    lua_pop(L, 1);
    
    lua_getglobal(L, "DrawUI");
    if (!lua_isfunction(L, -1)) {
        printf("[ERROR] DrawUI function not found in %s\n", scriptPath);
        return 1;
    }
    lua_pop(L, 1);
    
    printf("[System] UpdateUI and DrawUI found - starting main loop\n");
    
    // Test that bridge functions work
    printf("[System] Testing bridge.drawRect availability...\n");
    lua_getglobal(L, "bridge");
    if (!lua_istable(L, -1)) {
        printf("[ERROR] bridge table not found!\n");
        return 1;
    }
    lua_getfield(L, -1, "drawRect");
    if (!lua_isfunction(L, -1)) {
        printf("[ERROR] bridge.drawRect not found!\n");
        return 1;
    }
    lua_pop(L, 2);
    printf("[System] bridge.drawRect verified\n");

#ifdef __EMSCRIPTEN__
    g_loopData.window = window;
    g_loopData.L = L;
    g_loopData.winW = winW;
    g_loopData.winH = winH;
    g_loopData.running = 1;
    printf("[System] Starting Emscripten main loop\n");
    emscripten_set_main_loop(emscripten_main_loop, 0, 1);
#else
    int running = 1, mouseX = 0, mouseY = 0, mouseDown = 0;
    int frameCount = 0;
    printf("[System] Starting native main loop\n");
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Input_ProcessEvent(&e);
            if (e.type == SDL_QUIT) running = 0;
            if (e.type == SDL_WINDOWEVENT && e.window.event == SDL_WINDOWEVENT_RESIZED) {
                winW = e.window.data1; winH = e.window.data2;
                UpdateProjection(winW, winH);
            }
            if (e.type == SDL_KEYDOWN) {
                const char* keyName = SDL_GetKeyName(e.key.keysym.sym);
                lua_getglobal(L, "HandleKeyPress");
                if (lua_isfunction(L, -1)) {
                    char simpleName[32] = {0};
                    if (strcmp(keyName, "Up") == 0) strcpy(simpleName, "up");
                    else if (strcmp(keyName, "Down") == 0) strcpy(simpleName, "down");
                    else if (strcmp(keyName, "Left") == 0) strcpy(simpleName, "left");
                    else if (strcmp(keyName, "Right") == 0) strcpy(simpleName, "right");
                    else if (strcmp(keyName, "Space") == 0) strcpy(simpleName, "space");
                    else if (strlen(keyName) == 1) { simpleName[0] = keyName[0]; simpleName[1] = '\0'; }
                    else strncpy(simpleName, keyName, sizeof(simpleName) - 1);
                    lua_pushstring(L, simpleName);
                    if (lua_pcall(L, 1, 0, 0) != LUA_OK) { printf("HandleKeyPress Error: %s\n", lua_tostring(L, -1)); lua_pop(L, 1); }
                } else lua_pop(L, 1);
            }
        }
        Uint32 buttons = SDL_GetMouseState(&mouseX, &mouseY);
        mouseDown = (buttons & SDL_BUTTON(SDL_BUTTON_LEFT)) != 0;
        
        if (frameCount == 0) {
            printf("[System] Frame 0: Calling UpdateUI and DrawUI\n");
        }
        
        lua_getglobal(L, "UpdateUI");
        lua_pushnumber(L, mouseX); lua_pushnumber(L, mouseY); lua_pushboolean(L, mouseDown);
        lua_pushnumber(L, winW); lua_pushnumber(L, winH);
        if (lua_pcall(L, 5, 0, 0) != LUA_OK) { 
            printf("Lua Update Error: %s\n", lua_tostring(L, -1)); 
            lua_pop(L, 1); 
            if (frameCount < 5) {
                printf("[ERROR] UpdateUI failed on frame %d - stopping\n", frameCount);
                running = 0;
                continue;
            }
        }
        
        ClearScreen(0.1f, 0.1f, 0.15f, 1.0f);
        g_uiVertCount = 0;
        
        lua_getglobal(L, "DrawUI");
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) { 
            printf("Lua Draw Error: %s\n", lua_tostring(L, -1)); 
            lua_pop(L, 1); 
            if (frameCount < 5) {
                printf("[ERROR] DrawUI failed on frame %d - stopping\n", frameCount);
                running = 0;
                continue;
            }
        }
        FlushBatch();
        BridgeSwapBuffers();
        SDL_Delay(16);
        
        frameCount++;
        if (frameCount == 1) {
            printf("[System] Frame 1 completed successfully\n");
        }
        if (frameCount == 10) {
            printf("[System] Frame 10 reached - game is running\n");
        }
    }
    
    printf("[System] Main loop exited - running=%d\n", running);
#endif

    // Cleanup Audio
    if (g_audioDevice) {
        SDL_CloseAudioDevice(g_audioDevice);
    }
    if (g_audioState.stream) {
        SDL_FreeAudioStream(g_audioState.stream);
    }

    ShutdownEngine();
    lua_close(L);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}