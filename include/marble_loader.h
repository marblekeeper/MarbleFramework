/*
 * marble_loader.h -- Phase 0.3 Data-Driven Initialization
 *
 * PURPOSE:
 *   Defines the binary manifest format and the loader that populates
 *   the runtime from it. This replaces imperative 'init_world()' code.
 *
 * CONCEPT:
 *   The "Manifest" is a flat array of 'ComponentRecord's.
 *   This is analogous to a compiled .data section in an executable.
 *   The loader iterates this array and performs type-safe copying
 *   into the appropriate SparseSets.
 */

#ifndef MARBLE_LOADER_H
#define MARBLE_LOADER_H

#include "marble_core.h"
#include "marble_interact.h"
#include "marble_behavior.h"

/* =========================================================================
 * MANIFEST SCHEMA
 * ========================================================================= */

typedef enum
{
    COMP_TYPE_HEALTH = 0,
    COMP_TYPE_POSITION,
    COMP_TYPE_LAYERS,
    COMP_TYPE_SKILLS,
    COMP_TYPE_ANATOMY,
    COMP_TYPE_CAPABILITIES,
    COMP_TYPE_AFFORDANCES,
    COMP_TYPE_TOOL,
    COMP_TYPE_BODY_PARTS,
    COMP_TYPE_BEHAVIOR
} ComponentType;

/*
 * A single record in the manifest.
 * "Attach this data to this entity index."
 *
 * entity_idx: 0-based index. The Loader allocates entities sequentially,
 * so index 0 becomes EntityID 0, etc.
 */
typedef struct
{
    uint32_t entity_idx;
    ComponentType type;
    const void *data_ptr;
} ManifestEntry;

/* =========================================================================
 * LOADER CONTEXT
 *
 * The loader needs access to all pools to populate them.
 * ========================================================================= */

typedef struct
{
    EntityAllocator *alloc;
    SparseSet *pool_health;
    SparseSet *pool_position;
    SparseSet *pool_layers;
    SparseSet *pool_skills;
    SparseSet *pool_anatomy;
    SparseSet *pool_capabilities;
    SparseSet *pool_affordances;
    SparseSet *pool_tool;
    SparseSet *pool_body_parts;
    SparseSet *pool_behavior;
} WorldContext;

/* =========================================================================
 * LOADER IMPLEMENTATION
 * ========================================================================= */

static void Loader_LoadWorld(
    WorldContext *ctx,
    const ManifestEntry *entries,
    uint32_t entry_count)
{
    uint32_t i;
    EntityID current_max_eid = 0;

    printf("[Loader] Loading %u manifest entries...\n", entry_count);

    /* Phase 1: Ensure entities exist */
    /* Because entries might be unordered, we need to ensure the allocator
       has bumped enough times to cover the max index seen.
       Assumption: Manifest indices are 0..N packed. */

    for (i = 0; i < entry_count; i++)
    {
        if (entries[i].entity_idx >= current_max_eid)
        {
            /* Bump allocator until we reach this index */
            /* Note: In a real engine we'd have a smarter mapping,
               but for Phase 0.3 we assume contiguous indices. */
            while (ctx->alloc->next_id <= entries[i].entity_idx)
            {
                mc_entity_create(ctx->alloc);
            }
            current_max_eid = entries[i].entity_idx;
        }
    }
    printf("[Loader] Allocated %u entities.\n", ctx->alloc->next_id);

    /* Phase 2: Populate Components */
    for (i = 0; i < entry_count; i++)
    {
        EntityID eid = (EntityID)entries[i].entity_idx;
        const void *data = entries[i].data_ptr;

        switch (entries[i].type)
        {
        case COMP_TYPE_HEALTH:
            mc_sparse_set_add(ctx->pool_health, eid, data);
            break;
        case COMP_TYPE_POSITION:
            mc_sparse_set_add(ctx->pool_position, eid, data);
            break;
        case COMP_TYPE_LAYERS:
            mc_sparse_set_add(ctx->pool_layers, eid, data);
            break;
        case COMP_TYPE_SKILLS:
            mc_sparse_set_add(ctx->pool_skills, eid, data);
            break;
        case COMP_TYPE_ANATOMY:
            mc_sparse_set_add(ctx->pool_anatomy, eid, data);
            break;
        case COMP_TYPE_CAPABILITIES:
            mc_sparse_set_add(ctx->pool_capabilities, eid, data);
            break;
        case COMP_TYPE_AFFORDANCES:
            mc_sparse_set_add(ctx->pool_affordances, eid, data);
            break;
        case COMP_TYPE_TOOL:
            mc_sparse_set_add(ctx->pool_tool, eid, data);
            break;
        case COMP_TYPE_BODY_PARTS:
            mc_sparse_set_add(ctx->pool_body_parts, eid, data);
            break;
        case COMP_TYPE_BEHAVIOR:
            mc_sparse_set_add(ctx->pool_behavior, eid, data);
            break;
        default:
            break;
        }
    }
    printf("[Loader] Population complete.\n");
}

#endif /* MARBLE_LOADER_H */