#ifndef INPUT_HANDLER_H
#define INPUT_HANDLER_H

#include <SDL2/SDL.h>

void Input_Init(void);
void Input_ProcessEvent(SDL_Event* event);
int  Input_GetKeyState(const char* keyName);

#endif