/*
 * marble_core.h — MarbleEngine Runtime Foundation (Phase 0)
 *
 * PURPOSE:
 *   Prove out the two non-negotiable primitives before any DSL/codegen layer:
 *     1. A generic Sparse Set with O(1) add/remove/has and O(n) packed iteration.
 *     2. A deterministic fixed-timestep tick loop with logging.
 *
 * CONSTRAINTS (subset of JPL/NASA Power-of-Ten):
 *   - No malloc/free after init. All memory is pre-allocated in static pools.
 *   - No function pointers. All dispatch is via explicit switch.
 *   - No recursion. All loops have bounded iteration counts.
 *   - No strings at runtime. Identifiers are integer enums/hashes.
 *   - No polymorphism. Composition via component bitsets.
 *   - Pointers are used ONLY internally for memory pool arithmetic,
 *     never exposed as entity references (use EntityID uint32_t).
 *
 * TARGET: C99, Windows 10, MSVC or GCC/MinGW
 *
 * FUTURE (Phase 1+):
 *   MarbleScript DSL -> JSON manifest -> C codegen for struct definitions
 *   and system dispatch tables. This file is what that codegen will TARGET.
 */

#ifndef MARBLE_CORE_H
#define MARBLE_CORE_H

#include <stdint.h>
#include <string.h>  /* memcpy, memset */
#include <stdio.h>   /* printf for tick log — replace with ring buffer later */

/* =========================================================================
 * SECTION 1: CONFIGURATION
 * ========================================================================= */

/* Hard upper bound. In Phase 1+, the DSL manifest will define this. */
#define MC_MAX_ENTITIES     1024
#define MC_INVALID_INDEX    UINT32_MAX

/* Tick rate: 600ms per tick. Stored as microseconds for integer math. */
#define MC_TICK_INTERVAL_US 600000

/* =========================================================================
 * SECTION 2: ENTITY ID
 * ========================================================================= */

typedef uint32_t EntityID;

/* =========================================================================
 * SECTION 2b: ENTITY ID ALLOCATOR
 *
 * Monotonic bump allocator. IDs are never reused (generational reuse
 * is Phase 2+). Call mc_entity_create() to get the next available ID.
 *
 * The allocator is a simple global counter. In Phase 1+ the manifest
 * can reserve ID ranges for specific entity categories (e.g., body
 * parts get IDs 1000-1999, trees get 2000-2999).
 * ========================================================================= */

typedef struct {
    EntityID next_id;
} EntityAllocator;

static void mc_entity_alloc_init(EntityAllocator* alloc) {
    alloc->next_id = 0;
}

/* Returns the next available EntityID, or MC_INVALID_INDEX if exhausted. */
static EntityID mc_entity_create(EntityAllocator* alloc) {
    EntityID id;
    if (alloc->next_id >= MC_MAX_ENTITIES) return MC_INVALID_INDEX;
    id = alloc->next_id;
    alloc->next_id++;
    return id;
}

/* =========================================================================
 * SECTION 2c: DETERMINISTIC PRNG (SplitMix32)
 *
 * Replaces stdlib rand(). Properties:
 *   - Deterministic: same seed = same sequence on ALL platforms
 *   - Seedable per-context: each system/interaction can have its own state
 *   - No global mutable state (the state is passed explicitly)
 *   - Period: 2^32 (sufficient for simulation, not crypto)
 *
 * For interaction rolls, seed with: (world_seed ^ tick_number ^ entity_id)
 * This ensures the same interaction at the same tick with the same entity
 * always produces the same roll, enabling deterministic replay.
 * ========================================================================= */

typedef struct {
    uint32_t state;
} McRng;

static void mc_rng_seed(McRng* rng, uint32_t seed) {
    rng->state = seed;
}

/* Returns a pseudo-random uint32_t and advances state. */
static uint32_t mc_rng_next(McRng* rng) {
    uint32_t z = rng->state + 0x9E3779B9u;  /* golden ratio constant */
    rng->state = z;
    z ^= z >> 16;
    z *= 0x21F0AAADu;
    z ^= z >> 15;
    z *= 0x735A2D97u;
    z ^= z >> 15;
    return z;
}

/* Returns a value in [0, max_exclusive). */
static uint32_t mc_rng_range(McRng* rng, uint32_t max_exclusive) {
    if (max_exclusive == 0) return 0;
    return mc_rng_next(rng) % max_exclusive;
}

/* Convenience: d100 roll returning 0-99. */
static int32_t mc_rng_d100(McRng* rng) {
    return (int32_t)mc_rng_range(rng, 100);
}

/* =========================================================================
 * SECTION 3: SPARSE SET (generic, type-erased via byte stride)
 *
 * Architecture:
 *   sparse[EntityID] -> index into dense[]
 *   dense[i]         -> EntityID that lives at packed position i
 *   data[i]          -> component struct at packed position i (stride bytes)
 *
 * All three arrays are inline (no heap alloc). The SparseSet struct itself
 * must be placed in a static/global memory region.
 *
 * The data[] array is a raw byte pool. The caller provides stride (sizeof
 * their component struct) at init time. All access goes through
 * mc_sparse_set_get() which returns a void* — the ONLY place raw pointers
 * appear. Callers immediately cast and use; no pointer is ever stored as
 * an entity reference.
 * ========================================================================= */

typedef struct {
    /* Sparse: indexed by EntityID, value = index into dense/data or INVALID */
    uint32_t sparse[MC_MAX_ENTITIES];

    /* Dense: packed EntityIDs for iteration */
    EntityID dense[MC_MAX_ENTITIES];

    /* Data: packed component bytes, mirrored 1:1 with dense */
    /* Max component size is bounded. 64 bytes covers most gameplay structs.
       Phase 1+ codegen will size this precisely per-component-type. */
    uint8_t  data[MC_MAX_ENTITIES * 64];

    /* Stride: sizeof(ComponentStruct) — set once at init */
    uint32_t stride;

    /* Count of live entries in dense/data */
    uint32_t count;
} SparseSet;

/* Initialize a sparse set for a component type of `stride` bytes.
 * MUST be called before any other operation.
 * stride must be <= 64 (the per-entity data budget in this phase). */
static void mc_sparse_set_init(SparseSet* ss, uint32_t stride) {
    uint32_t i;
    ss->stride = stride;
    ss->count  = 0;
    for (i = 0; i < MC_MAX_ENTITIES; i++) {
        ss->sparse[i] = MC_INVALID_INDEX;
    }
    /* Dense and data are implicitly valid up to ss->count — no need to zero. */
}

/* Returns 1 if entity has this component, 0 otherwise. */
static int mc_sparse_set_has(const SparseSet* ss, EntityID eid) {
    uint32_t idx;
    if (eid >= MC_MAX_ENTITIES) return 0;
    idx = ss->sparse[eid];
    if (idx >= ss->count) return 0;
    return (ss->dense[idx] == eid) ? 1 : 0;
}

/* Add entity with component data. Returns 0 on success, -1 on failure.
 * `component_data` must point to exactly `stride` bytes. */
static int mc_sparse_set_add(SparseSet* ss, EntityID eid, const void* component_data) {
    uint32_t idx;
    if (eid >= MC_MAX_ENTITIES) return -1;
    if (ss->count >= MC_MAX_ENTITIES) return -1;
    if (mc_sparse_set_has(ss, eid)) return -1; /* no duplicates */

    idx = ss->count;
    ss->dense[idx] = eid;
    ss->sparse[eid] = idx;
    memcpy(&ss->data[idx * ss->stride], component_data, ss->stride);
    ss->count++;
    return 0;
}

/* Remove entity. Uses swap-and-pop to keep dense/data packed.
 * Returns 0 on success, -1 if entity not present. */
static int mc_sparse_set_remove(SparseSet* ss, EntityID eid) {
    uint32_t idx_removed, idx_last;
    EntityID eid_last;

    if (!mc_sparse_set_has(ss, eid)) return -1;

    idx_removed = ss->sparse[eid];
    idx_last    = ss->count - 1;
    eid_last    = ss->dense[idx_last];

    /* Move last element into the removed slot */
    ss->dense[idx_removed] = eid_last;
    memcpy(
        &ss->data[idx_removed * ss->stride],
        &ss->data[idx_last * ss->stride],
        ss->stride
    );
    ss->sparse[eid_last] = idx_removed;

    /* Invalidate removed entity */
    ss->sparse[eid] = MC_INVALID_INDEX;
    ss->count--;
    return 0;
}

/* Get pointer to component data for entity. Returns NULL if not present.
 * Caller casts to their concrete struct type immediately. */
static void* mc_sparse_set_get(SparseSet* ss, EntityID eid) {
    uint32_t idx;
    if (!mc_sparse_set_has(ss, eid)) return NULL;
    idx = ss->sparse[eid];
    return &ss->data[idx * ss->stride];
}

/* Get const pointer — for read-only iteration patterns (immutable snapshots). */
static const void* mc_sparse_set_get_const(const SparseSet* ss, EntityID eid) {
    uint32_t idx;
    if (!mc_sparse_set_has(ss, eid)) return NULL;
    idx = ss->sparse[eid];
    return &ss->data[idx * ss->stride];
}

/* =========================================================================
 * SECTION 4: TICK LOOP
 *
 * Fixed-timestep accumulator model.
 * Platform time source is pluggable (see mc_platform_time_us).
 *
 * Each tick:
 *   1. Log tick number and wall-clock timestamp (Phase 0: printf)
 *   2. Run all systems via static dispatch switch (Phase 0: placeholder)
 *   3. Advance tick counter
 *
 * The loop does NOT free-spin. It yields to the OS between ticks.
 * On Windows: Sleep(). On other platforms: nanosleep().
 * ========================================================================= */

typedef struct {
    uint64_t tick_number;
    uint64_t accumulated_us;  /* leftover microseconds from last frame */
    uint64_t last_time_us;    /* wall-clock at last frame start */
} TickState;

static void mc_tick_state_init(TickState* ts, uint64_t now_us) {
    ts->tick_number    = 0;
    ts->accumulated_us = 0;
    ts->last_time_us   = now_us;
}

/* =========================================================================
 * SECTION 5: SYSTEM OP CODES (static dispatch)
 *
 * Phase 0: We define a tiny enum. Phase 1+ codegen will generate this
 * from the MarbleScript system declarations.
 * ========================================================================= */

typedef enum {
    OP_TICK_LOG = 0,   /* Built-in: emit tick log line */
    OP_SYSTEM_COUNT    /* Sentinel — always last */
} SystemOpCode;

#endif /* MARBLE_CORE_H */