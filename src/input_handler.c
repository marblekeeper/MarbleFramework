#include "input_handler.h"
#include <string.h>
#include <ctype.h>

#define MAX_KEYS 512
static int g_keyStates[MAX_KEYS] = {0};

void Input_Init(void) {
    memset(g_keyStates, 0, sizeof(g_keyStates));
}

void Input_ProcessEvent(SDL_Event* event) {
    if (event->type == SDL_KEYDOWN || event->type == SDL_KEYUP) {
        int sc = event->key.keysym.scancode;
        if (sc >= 0 && sc < MAX_KEYS) {
            g_keyStates[sc] = (event->type == SDL_KEYDOWN);
        }
    }
}

static SDL_Scancode NameToScancode(const char* name) {
    if (!name || name[0] == '\0') return SDL_SCANCODE_UNKNOWN;

    // 1. Numbers 0-9
    if (name[1] == '\0' && name[0] >= '0' && name[0] <= '9') {
        if (name[0] == '0') return SDL_SCANCODE_0;
        return (SDL_Scancode)(SDL_SCANCODE_1 + (name[0] - '1'));
    }

    // 2. Arrow keys and space
    if (strcmp(name, "up") == 0)      return SDL_SCANCODE_UP;
    if (strcmp(name, "down") == 0)    return SDL_SCANCODE_DOWN;
    if (strcmp(name, "left") == 0)    return SDL_SCANCODE_LEFT;
    if (strcmp(name, "right") == 0)   return SDL_SCANCODE_RIGHT;
    if (strcmp(name, "space") == 0)   return SDL_SCANCODE_SPACE;

    // 3. Any single lowercase letter a-z
    if (name[1] == '\0' && name[0] >= 'a' && name[0] <= 'z') {
        return (SDL_Scancode)(SDL_SCANCODE_A + (name[0] - 'a'));
    }

    // 4. Modifier / special keys
    if (strcmp(name, "escape") == 0)    return SDL_SCANCODE_ESCAPE;
    if (strcmp(name, "enter") == 0)     return SDL_SCANCODE_RETURN;
    if (strcmp(name, "lshift") == 0)    return SDL_SCANCODE_LSHIFT;
    if (strcmp(name, "rshift") == 0)    return SDL_SCANCODE_RSHIFT;
    if (strcmp(name, "tab") == 0)       return SDL_SCANCODE_TAB;
    if (strcmp(name, "backspace") == 0) return SDL_SCANCODE_BACKSPACE;

    return SDL_SCANCODE_UNKNOWN;
}

int Input_GetKeyState(const char* keyName) {
    SDL_Scancode sc = NameToScancode(keyName);
    if (sc <= SDL_SCANCODE_UNKNOWN || sc >= MAX_KEYS) return 0;
    return g_keyStates[sc];
}