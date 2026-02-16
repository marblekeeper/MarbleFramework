/*
 * marble_platform_win32.h — Windows 10 platform shim (Phase 0)
 *
 * Provides:
 *   mc_platform_time_us()  — microsecond wall-clock via QueryPerformanceCounter
 *   mc_platform_sleep_us() — OS yield via Sleep()
 *
 * This is the ONLY file that includes <windows.h>.
 * In Phase 1+, Linux/macOS shims go in separate headers with the same API.
 */

#ifndef MARBLE_PLATFORM_WIN32_H
#define MARBLE_PLATFORM_WIN32_H

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

/* Cache the QPC frequency at init. Call once before any time queries. */
static LARGE_INTEGER g_qpc_freq;
static int g_qpc_initialized = 0;

static void mc_platform_init(void) {
    QueryPerformanceFrequency(&g_qpc_freq);
    g_qpc_initialized = 1;
}

/* Returns current wall-clock time in microseconds. */
static uint64_t mc_platform_time_us(void) {
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    /* Multiply first to avoid precision loss, divide second.
     * For frequencies in the MHz range this won't overflow for years. */
    return (uint64_t)((now.QuadPart * 1000000ULL) / g_qpc_freq.QuadPart);
}

/* Sleep for approximately `us` microseconds. Granularity is ~1ms on Windows.
 * Good enough for a 600ms tick. For sub-ms precision, use a spin-wait
 * hybrid (Phase 2). */
static void mc_platform_sleep_us(uint64_t us) {
    DWORD ms = (DWORD)(us / 1000);
    if (ms == 0) ms = 1;
    Sleep(ms);
}

#else
#error "This header is Windows-only. Use marble_platform_posix.h for Linux/macOS."
#endif /* _WIN32 */

#endif /* MARBLE_PLATFORM_WIN32_H */