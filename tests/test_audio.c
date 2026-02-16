#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#include <stdio.h>
#include <string.h>  // Added for memcpy

/* Minimp3 Implementation Details */
#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"
#include "minimp3_ex.h"

typedef struct {
    int16_t* buffer;
    uint64_t totalSamples;
    uint64_t currentPos;
    int channels;
} AudioContext;

void AudioCallback(void* userdata, Uint8* stream, int len) {
    AudioContext* ctx = (AudioContext*)userdata;
    int16_t* output = (int16_t*)stream;
    
    int samplesToWrite = len / 2; // 16-bit audio = 2 bytes per sample
    int samplesWritten = 0;

    // Clear buffer to silence first (good practice)
    memset(stream, 0, len);

    while (samplesWritten < samplesToWrite) {
        uint64_t remaining = ctx->totalSamples - ctx->currentPos;
        int chunk = samplesToWrite - samplesWritten;

        if (remaining < chunk) {
            chunk = (int)remaining;
        }

        // Copy audio data
        // Multiply chunk by 2 (sizeof int16) because memcpy works in bytes
        if (chunk > 0) {
            memcpy(output + samplesWritten, 
                   ctx->buffer + ctx->currentPos, 
                   chunk * sizeof(int16_t));
        }

        samplesWritten += chunk;
        ctx->currentPos += chunk;

        // Loop functionality
        if (ctx->currentPos >= ctx->totalSamples) {
            ctx->currentPos = 0;
            printf("[Audio] Loop!\n");
        }
    }
}

int main(int argc, char* argv[]) {
    printf("[System] Init SDL Audio...\n");
    if (SDL_Init(SDL_INIT_AUDIO) < 0) {
        printf("SDL Error: %s\n", SDL_GetError());
        return 1;
    }

    // UPDATED: Point to the correct asset path
    const char* filename = "assets/Content/audio/demo.mp3";
    printf("[Audio] Loading %s...\n", filename);

    mp3dec_t mp3d;
    mp3dec_file_info_t info;
    
    // Load MP3
    if (mp3dec_load(&mp3d, filename, &info, NULL, NULL)) {
        printf("Error: Failed to decode mp3 at path: %s\n", filename);
        printf("       (Make sure the file exists relative to where you run the exe)\n");
        SDL_Quit();
        return 1;
    }

    printf("[Audio] Decoded: %d Hz, %d Channels, %llu Samples\n", 
           info.hz, info.channels, info.samples);

    AudioContext ctx;
    ctx.buffer = info.buffer;
    ctx.totalSamples = info.samples;
    ctx.currentPos = 0;
    ctx.channels = info.channels;

    SDL_AudioSpec want, have;
    SDL_zero(want);
    want.freq = info.hz;
    want.format = AUDIO_S16;
    want.channels = info.channels;
    want.samples = 4096;
    want.callback = AudioCallback;
    want.userdata = &ctx;

    // Open Audio Device
    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (dev == 0) {
        printf("SDL_OpenAudioDevice Error: %s\n", SDL_GetError());
        free(info.buffer);
        SDL_Quit();
        return 1;
    }

    // Unpause (Start playing)
    SDL_PauseAudioDevice(dev, 0);

    printf("[Audio] Playing... Press ENTER to quit.\n");
    getchar();

    // Cleanup
    SDL_CloseAudioDevice(dev);
    free(info.buffer);
    SDL_Quit();
    printf("[System] Done.\n");

    return 0;
}