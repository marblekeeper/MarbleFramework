/*
 * main.c -- MarbleEngine Phase 0.2 Validation
 *
 * NEW IN 0.2:
 *   - Deterministic PRNG (SplitMix32): same seed = same simulation on
 *     all platforms. No more rand(). Seeded per-interaction with
 *     (world_seed ^ tick ^ actor_id ^ target_id) for full reproducibility.
 *   - Entity ID Allocator: monotonic bump allocator, no more magic numbers.
 *     Entity IDs are assigned at init and printed in the log.
 *
 * SCENARIO: Same as 0.1b (lumberjack chops tree, crit fail damages hand)
 *
 * BUILD (GCC/MinGW):
 *   gcc -std=c99 -Wall -Wextra -O2 main.c -o marble_phase0_2.exe
 *
 * BUILD (MSVC):
 *   cl /std:c11 /W4 /O2 main.c /Fe:marble_phase0_2.exe
 */

#include "marble_core.h"
#include "marble_interact.h"

#ifdef _WIN32
#include "marble_platform_win32.h"
#else
#include "marble_platform_posix.h"
#endif

/* =========================================================================
 * BASIC COMPONENTS
 * ========================================================================= */

typedef struct {
    int32_t hp;
    int32_t max_hp;
} CHealth;

typedef struct {
    float x;
    float y;
} CPosition;

/* =========================================================================
 * GLOBALS
 * ========================================================================= */

/* Entity allocator -- all entity IDs come from here */
static EntityAllocator g_alloc;

/* World PRNG seed -- set once, used to derive per-interaction seeds */
#define WORLD_SEED 42u

/* Component pools */
static SparseSet g_pool_health;
static SparseSet g_pool_position;
static SparseSet g_pool_layers;
static SparseSet g_pool_skills;
static SparseSet g_pool_anatomy;
static SparseSet g_pool_capabilities;
static SparseSet g_pool_affordances;
static SparseSet g_pool_tool;
static SparseSet g_pool_body_parts;

/* Well-known entity IDs -- assigned by allocator at init, stored for
 * system lookups. In Phase 1+ these come from the world definition. */
static EntityID g_eid_lumberjack;
static EntityID g_eid_right_hand;
static EntityID g_eid_oak_tree;

/* Interaction request queue */
static InteractionRequest g_requests[MAX_INTERACTION_REQUESTS];
static uint32_t           g_request_count = 0;

static void push_request(EntityID actor, EntityID target, VerbID verb) {
    if (g_request_count < MAX_INTERACTION_REQUESTS) {
        g_requests[g_request_count].actor  = actor;
        g_requests[g_request_count].target = target;
        g_requests[g_request_count].verb   = verb;
        g_request_count++;
    }
}

/* =========================================================================
 * SYSTEMS
 * ========================================================================= */

typedef enum {
    SYS_TICK_LOG     = 0,
    SYS_INTERACTION  = 1,
    SYS_WORLD_STATUS = 2,
    SYS_COUNT
} SystemID;

static const uint32_t SYSTEM_FREQ[SYS_COUNT] = {
    1, /* SYS_TICK_LOG:     every tick */
    2, /* SYS_INTERACTION:  every 2 ticks */
    3, /* SYS_WORLD_STATUS: every 3 ticks */
};

/* --- System: Tick Log (freq 1) --- */
static void System_TickLog(uint64_t tick) {
    printf("=== TICK %llu ===\n", (unsigned long long)tick);
}

/* --- System: Interaction Processor (freq 2) ---
 * Seeds the PRNG per-interaction for deterministic replay. */
static void System_Interaction(uint64_t tick) {
    uint32_t i;

    push_request(g_eid_lumberjack, g_eid_oak_tree, VERB_CHOP);

    printf("  [InteractionSystem] Processing %u request(s)...\n", g_request_count);

    for (i = 0; i < g_request_count; i++) {
        InteractResult result;
        McRng rng;

        /* Seed PRNG deterministically: same tick + same entities = same roll.
         * This is the key property that enables replay and network sync. */
        mc_rng_seed(&rng, WORLD_SEED
                    ^ (uint32_t)tick
                    ^ (g_requests[i].actor * 2654435761u)
                    ^ (g_requests[i].target * 2246822519u));

        result = process_interaction(
            &g_requests[i],
            &g_pool_capabilities,
            &g_pool_affordances,
            &g_pool_anatomy,
            &g_pool_skills,
            &g_pool_tool,
            &g_pool_body_parts,
            &g_pool_layers,
            &rng
        );

        printf("    [t%llu] eid %u -> CHOP -> eid %u : %s (roll seed: 0x%08X)\n",
               (unsigned long long)tick,
               g_requests[i].actor,
               g_requests[i].target,
               INTERACT_RESULT_NAMES[result],
               rng.state);  /* print final RNG state for debug/replay */
    }

    g_request_count = 0;
}

/* --- System: World Status (freq 3) --- */
static void System_WorldStatus(uint64_t tick) {
    const CLayerStack* tree_layers;
    const CLayerStack* hand_layers;
    uint32_t i;

    (void)tick;
    printf("  [WorldStatus] --- Snapshot ---\n");

    tree_layers = (const CLayerStack*)mc_sparse_set_get_const(
        &g_pool_layers, g_eid_oak_tree);
    if (tree_layers != NULL && tree_layers->layer_count > 0) {
        printf("    Oak Tree (eid %u): %u layer(s)\n",
               g_eid_oak_tree, tree_layers->layer_count);
        for (i = 0; i < tree_layers->layer_count; i++) {
            printf("      [%u] %s  integrity=%d/%d\n", i,
                   MATERIAL_NAMES[tree_layers->layers[i].material],
                   tree_layers->layers[i].integrity,
                   tree_layers->layers[i].max_integrity);
        }
    } else {
        printf("    Oak Tree (eid %u): FULLY DESTROYED\n", g_eid_oak_tree);
    }

    hand_layers = (const CLayerStack*)mc_sparse_set_get_const(
        &g_pool_layers, g_eid_right_hand);
    if (hand_layers != NULL && hand_layers->layer_count > 0) {
        printf("    Right Hand (eid %u): %u layer(s)\n",
               g_eid_right_hand, hand_layers->layer_count);
        for (i = 0; i < hand_layers->layer_count; i++) {
            printf("      [%u] %s  integrity=%d/%d\n", i,
                   MATERIAL_NAMES[hand_layers->layers[i].material],
                   hand_layers->layers[i].integrity,
                   hand_layers->layers[i].max_integrity);
        }
    } else {
        printf("    Right Hand (eid %u): DESTROYED -- fine motor LOST\n",
               g_eid_right_hand);
    }

    printf("  --------------------------\n");
}

/* =========================================================================
 * DISPATCHER
 * ========================================================================= */

static void dispatch_system(SystemID sys, uint64_t tick) {
    if (tick % SYSTEM_FREQ[sys] != 0) return;

    switch (sys) {
        case SYS_TICK_LOG:     System_TickLog(tick);     break;
        case SYS_INTERACTION:  System_Interaction(tick);  break;
        case SYS_WORLD_STATUS: System_WorldStatus(tick);  break;
        default: break;
    }
}

/* =========================================================================
 * TICK LOOP
 * ========================================================================= */

#define MAX_CATCHUP_TICKS 3
#define TOTAL_DEMO_TICKS  30

static void run_tick_loop(void) {
    TickState ts;
    uint64_t now_us;
    int ticks_this_frame;
    int sys;

    now_us = mc_platform_time_us();
    mc_tick_state_init(&ts, now_us);

    printf("\n========================================\n");
    printf("  MarbleEngine Phase 0.2\n");
    printf("  Tick interval: %d ms\n", MC_TICK_INTERVAL_US / 1000);
    printf("  World seed: %u\n", WORLD_SEED);
    printf("  PRNG: SplitMix32 (deterministic)\n");
    printf("  Entity allocator: monotonic bump\n");
    printf("  Systems:\n");
    printf("    SYS_TICK_LOG     freq=1\n");
    printf("    SYS_INTERACTION  freq=2\n");
    printf("    SYS_WORLD_STATUS freq=3\n");
    printf("  Running %d ticks.\n", TOTAL_DEMO_TICKS);
    printf("========================================\n\n");

    while (ts.tick_number < TOTAL_DEMO_TICKS) {
        now_us = mc_platform_time_us();
        ts.accumulated_us += (now_us - ts.last_time_us);
        ts.last_time_us = now_us;

        ticks_this_frame = 0;

        while (ts.accumulated_us >= MC_TICK_INTERVAL_US
               && ticks_this_frame < MAX_CATCHUP_TICKS
               && ts.tick_number < TOTAL_DEMO_TICKS) {

            for (sys = 0; sys < SYS_COUNT; sys++) {
                dispatch_system((SystemID)sys, ts.tick_number);
            }
            printf("\n");

            ts.accumulated_us -= MC_TICK_INTERVAL_US;
            ts.tick_number++;
            ticks_this_frame++;
        }

        if (ts.accumulated_us < MC_TICK_INTERVAL_US) {
            uint64_t remaining = MC_TICK_INTERVAL_US - ts.accumulated_us;
            if (remaining > 10000) {
                mc_platform_sleep_us(remaining - 5000);
            } else {
                mc_platform_sleep_us(1000);
            }
        }
    }

    printf("=== Phase 0.2 complete: %llu ticks ===\n",
           (unsigned long long)ts.tick_number);
}

/* =========================================================================
 * WORLD INITIALIZATION
 *
 * All entity IDs are now assigned by the allocator.
 * ========================================================================= */

static void init_world(void) {
    /* Init allocator and all pools */
    mc_entity_alloc_init(&g_alloc);

    mc_sparse_set_init(&g_pool_health,       sizeof(CHealth));
    mc_sparse_set_init(&g_pool_position,     sizeof(CPosition));
    mc_sparse_set_init(&g_pool_layers,       sizeof(CLayerStack));
    mc_sparse_set_init(&g_pool_skills,       sizeof(CSkills));
    mc_sparse_set_init(&g_pool_anatomy,      sizeof(CAnatomy));
    mc_sparse_set_init(&g_pool_capabilities, sizeof(CCapabilities));
    mc_sparse_set_init(&g_pool_affordances,  sizeof(CAffordances));
    mc_sparse_set_init(&g_pool_tool,         sizeof(CTool));
    mc_sparse_set_init(&g_pool_body_parts,   sizeof(CBodyParts));

    /* === Allocate all entity IDs up front === */
    g_eid_lumberjack = mc_entity_create(&g_alloc);  /* 0 */
    g_eid_right_hand = mc_entity_create(&g_alloc);  /* 1 */
    g_eid_oak_tree   = mc_entity_create(&g_alloc);  /* 2 */

    printf("Entity IDs assigned by allocator:\n");
    printf("  Lumberjack:  eid %u\n", g_eid_lumberjack);
    printf("  Right Hand:  eid %u\n", g_eid_right_hand);
    printf("  Oak Tree:    eid %u\n", g_eid_oak_tree);
    printf("  Next free:   eid %u\n\n", g_alloc.next_id);

    /* === Entity: Lumberjack's Right Hand === */
    {
        CLayerStack hand_ls;
        hand_ls.layer_count = 2;
        hand_ls.layers[0].material      = MAT_FLESH;
        hand_ls.layers[0].integrity     = 1;
        hand_ls.layers[0].max_integrity = 1;
        hand_ls.layers[1].material      = MAT_BONE;
        hand_ls.layers[1].integrity     = 1;
        hand_ls.layers[1].max_integrity = 1;

        mc_sparse_set_add(&g_pool_layers, g_eid_right_hand, &hand_ls);

        printf("Entity %u: Lumberjack's Right Hand\n", g_eid_right_hand);
        printf("  Layer 0: Flesh (integrity %d/%d) -- fragile!\n",
               hand_ls.layers[0].integrity, hand_ls.layers[0].max_integrity);
        printf("  Layer 1: Bone (integrity %d/%d)\n\n",
               hand_ls.layers[1].integrity, hand_ls.layers[1].max_integrity);
    }

    /* === Entity: Lumberjack === */
    {
        CHealth h;
        CPosition p;
        CAnatomy anat;
        CSkills skills;
        CCapabilities caps;
        CTool tool;
        CBodyParts bp;
        uint32_t i;

        h.hp = 100; h.max_hp = 100;
        p.x = 5.0f; p.y = 3.0f;
        anat.flags = ANAT_ARMS | ANAT_HANDS | ANAT_LEGS;
        memset(&skills, 0, sizeof(skills));
        skills.level[SKILL_WOODCUTTING] = 60;
        caps.flags = (1u << CAP_CHOP);
        tool.material = MAT_IRON;

        for (i = 0; i < MAX_BODY_PARTS; i++) {
            bp.part_entity[i] = MC_INVALID_INDEX;
        }
        bp.part_entity[BODYPART_RIGHT_HAND] = g_eid_right_hand;

        mc_sparse_set_add(&g_pool_health,       g_eid_lumberjack, &h);
        mc_sparse_set_add(&g_pool_position,     g_eid_lumberjack, &p);
        mc_sparse_set_add(&g_pool_anatomy,      g_eid_lumberjack, &anat);
        mc_sparse_set_add(&g_pool_skills,       g_eid_lumberjack, &skills);
        mc_sparse_set_add(&g_pool_capabilities, g_eid_lumberjack, &caps);
        mc_sparse_set_add(&g_pool_tool,         g_eid_lumberjack, &tool);
        mc_sparse_set_add(&g_pool_body_parts,   g_eid_lumberjack, &bp);

        printf("Entity %u: Lumberjack\n", g_eid_lumberjack);
        printf("  Anatomy: Arms+Hands+Legs\n");
        printf("  Skill: Woodcutting %d\n", skills.level[SKILL_WOODCUTTING]);
        printf("  Capability: CHOP (requires fine motor on right hand)\n");
        printf("  Tool: Iron Axe (hardness %d)\n", MATERIAL_HARDNESS[MAT_IRON]);
        printf("  Body: right_hand -> eid %u\n\n", g_eid_right_hand);
    }

    /* === Entity: Oak Tree === */
    {
        CPosition p;
        CLayerStack ls;
        CAffordances affs;

        p.x = 6.0f; p.y = 3.0f;
        affs.flags = (1u << AFF_CHOPPABLE);

        ls.layer_count = 2;
        ls.layers[0].material      = MAT_BARK;
        ls.layers[0].integrity     = 3;
        ls.layers[0].max_integrity = 3;
        ls.layers[1].material      = MAT_WOOD;
        ls.layers[1].integrity     = 10;
        ls.layers[1].max_integrity = 10;

        mc_sparse_set_add(&g_pool_position,    g_eid_oak_tree, &p);
        mc_sparse_set_add(&g_pool_layers,      g_eid_oak_tree, &ls);
        mc_sparse_set_add(&g_pool_affordances, g_eid_oak_tree, &affs);

        printf("Entity %u: Oak Tree\n", g_eid_oak_tree);
        printf("  Layer 0: Bark (hardness %d, integrity %d/%d)\n",
               MATERIAL_HARDNESS[MAT_BARK],
               ls.layers[0].integrity, ls.layers[0].max_integrity);
        printf("  Layer 1: Wood (hardness %d, integrity %d/%d)\n",
               MATERIAL_HARDNESS[MAT_WOOD],
               ls.layers[1].integrity, ls.layers[1].max_integrity);
        printf("  Affordance: CHOPPABLE (crit_fail_threshold=15)\n\n");
    }
}

/* =========================================================================
 * ENTRY POINT
 * ========================================================================= */

int main(void) {
    mc_platform_init();
    init_world();
    run_tick_loop();
    return 0;
}