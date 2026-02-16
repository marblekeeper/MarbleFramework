// js_interop.c - JavaScript interop for Emscripten/WASM
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <string.h>
#include <stdlib.h>

// Call JavaScript function and get string result
char* bridge_callJS(const char* jsCode) {
    // Execute JavaScript and get result as string
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
            var errorStr = "error";
            var len = lengthBytesUTF8(errorStr) + 1;
            var ptr = _malloc(len);
            stringToUTF8(errorStr, ptr, len);
            return ptr;
        }
    }, jsCode);
    
    return result;
}

// Call JavaScript function and get integer result
int bridge_callJS_int(const char* jsCode) {
    int result = EM_ASM_INT({
        try {
            var code = UTF8ToString($0);
            var result = eval(code);
            return parseInt(result) || 0;
        } catch(e) {
            console.error("JavaScript eval error:", e);
            return 0;
        }
    }, jsCode);
    
    return result;
}

#else
// Dummy implementations for non-WASM builds
char* bridge_callJS(const char* jsCode) {
    return strdup("");
}

int bridge_callJS_int(const char* jsCode) {
    return 0;
}
#endif