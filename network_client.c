#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <stdio.h>
#include <stdlib.h>
#include <emscripten.h>

// LuaSocket module loader (we won't use it, but keep for compatibility)
extern int luaopen_socket_core(lua_State *L);

// JavaScript WebSocket bridge using EM_JS
EM_JS(int, js_ws_connect, (const char* host, int port), {
    var hostStr = UTF8ToString(host);
    var url = 'ws://' + hostStr + ':' + port;
    console.log('[WebSocket] Connecting to ' + url);
    
    try {
        if (!window.marbleWS) {
            window.marbleWS = { ws: null, queue: [], connected: false };
        }
        
        window.marbleWS.ws = new WebSocket(url);
        
        window.marbleWS.ws.onopen = function() {
            console.log('[WebSocket] Connected!');
            window.marbleWS.connected = true;
        };
        
        window.marbleWS.ws.onmessage = function(event) {
            var message = event.data;
            // Handle Blob (binary data sent as text)
            if (message instanceof Blob) {
                var reader = new FileReader();
                reader.onload = function() {
                    var text = reader.result;
                    console.log('[WebSocket] ← ' + text);
                    window.marbleWS.queue.push(text);
                };
                reader.readAsText(message);
            } else {
                // Plain text
                console.log('[WebSocket] ← ' + message);
                window.marbleWS.queue.push(message);
            }
        };
        
        window.marbleWS.ws.onerror = function(error) {
            console.error('[WebSocket] Error:', error);
        };
        
        window.marbleWS.ws.onclose = function(event) {
            console.log('[WebSocket] Closed. Code: ' + event.code + ', Reason: ' + event.reason);
            window.marbleWS.connected = false;
        };
        
        return 1;
    } catch(e) {
        console.error('[WebSocket] Failed:', e);
        return 0;
    }
});

EM_JS(int, js_ws_is_connected, (), {
    return (window.marbleWS && window.marbleWS.ws && window.marbleWS.ws.readyState === 1) ? 1 : 0;
});

EM_JS(int, js_ws_send, (const char* msg), {
    var message = UTF8ToString(msg);
    if (window.marbleWS && window.marbleWS.ws && window.marbleWS.ws.readyState === 1) {
        console.log('[WebSocket] → ' + message);
        // Send as binary (ArrayBuffer) not text - websockify requires binary frames
        var encoder = new TextEncoder();
        var data = encoder.encode(message);
        window.marbleWS.ws.send(data.buffer);
        return 1;
    }
    return 0;
});

EM_JS(char*, js_ws_receive, (), {
    if (window.marbleWS && window.marbleWS.queue.length > 0) {
        var msg = window.marbleWS.queue.shift();
        var len = lengthBytesUTF8(msg) + 1;
        var ptr = _malloc(len);
        stringToUTF8(msg, ptr, len);
        return ptr;
    }
    return 0;
});

// Lua bindings
static int l_ws_connect(lua_State *L) {
    const char *host = luaL_checkstring(L, 1);
    int port = (int)luaL_checknumber(L, 2);
    
    int result = js_ws_connect(host, port);
    lua_pushboolean(L, result);
    return 1;
}

static int l_ws_is_connected(lua_State *L) {
    int result = js_ws_is_connected();
    lua_pushboolean(L, result);
    return 1;
}

static int l_ws_send(lua_State *L) {
    const char *msg = luaL_checkstring(L, 1);
    int result = js_ws_send(msg);
    lua_pushboolean(L, result);
    return 1;
}

static int l_ws_receive(lua_State *L) {
    char *msg = js_ws_receive();
    if (msg) {
        lua_pushstring(L, msg);
        free(msg);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// Register WebSocket module
static int luaopen_websocket(lua_State *L) {
    lua_newtable(L);
    
    lua_pushcfunction(L, l_ws_connect);
    lua_setfield(L, -2, "connect");
    
    lua_pushcfunction(L, l_ws_is_connected);
    lua_setfield(L, -2, "is_connected");
    
    lua_pushcfunction(L, l_ws_send);
    lua_setfield(L, -2, "send");
    
    lua_pushcfunction(L, l_ws_receive);
    lua_setfield(L, -2, "receive");
    
    return 1;
}

// Global Lua state for main loop
static lua_State *g_L = NULL;

// Emscripten main loop callback
void emscripten_main_loop() {
    if (!g_L) return;
    
    // Call Lua update() function
    lua_getglobal(g_L, "update");
    if (lua_isfunction(g_L, -1)) {
        if (lua_pcall(g_L, 0, 0, 0) != LUA_OK) {
            const char *err = lua_tostring(g_L, -1);
            printf("[ERROR] update() failed: %s\n", err);
            lua_pop(g_L, 1);
        }
    } else {
        lua_pop(g_L, 1);
    }
}

int main(void) {
    printf("=== Marble Network Client (WASM) ===\n");
    
    g_L = luaL_newstate();
    luaL_openlibs(g_L);
    
    // Set up package paths
    printf("[System] Setting up package paths...\n");
    lua_getglobal(g_L, "package");
    lua_getfield(g_L, -1, "path");
    const char* currentPath = lua_tostring(g_L, -1);
    char newPath[1024];
    snprintf(newPath, sizeof(newPath), "%s;/?.lua", currentPath);
    lua_pop(g_L, 1);
    lua_pushstring(g_L, newPath);
    lua_setfield(g_L, -2, "path");
    lua_pop(g_L, 1);
    
    // Preload WebSocket module
    printf("[System] Preloading websocket module...\n");
    lua_getglobal(g_L, "package");
    lua_getfield(g_L, -1, "preload");
    lua_pushcfunction(g_L, luaopen_websocket);
    lua_setfield(g_L, -2, "websocket");
    lua_pop(g_L, 2);
    
    // Load the WASM client
    printf("[System] Loading client_wasm_main.lua...\n");
    if (luaL_dofile(g_L, "client_wasm_main.lua") != LUA_OK) {
        const char *err = lua_tostring(g_L, -1);
        printf("[ERROR] %s\n", err);
        lua_pop(g_L, 1);
        return 1;
    }
    
    printf("[System] Starting Emscripten main loop...\n");
    
    // Start the main loop (60 FPS)
    emscripten_set_main_loop(emscripten_main_loop, 60, 1);
    
    return 0;
}
