/*
 * test.c -- MarbleEngine Test Harness
 *
 * Runs all tests instantly (no tick loop, no sleeps, no wall clock).
 * Each test is self-contained: sets up its own state, runs assertions,
 * reports PASS/FAIL. Exit code 0 = all passed, 1 = any failed.
 *
 * Run after every change. If it's green, you haven't broken anything.
 *
 * BUILD (GCC/MinGW):
 *   gcc -std=c99 -Wall -Wextra -O2 test.c -o test.exe
 *
 * BUILD (MSVC):
 *   cl /std:c11 /W4 /O2 test.c /Fe:test.exe
 *
 * RUN:
 *   test.exe
 */

#include "marble_core.h"
#include "marble_interact.h"

/* =========================================================================
 * TEST FRAMEWORK (minimal, no dependencies)
 * ========================================================================= */

static int g_tests_run    = 0;
static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_BEGIN(name) \
    do { \
        const char* _test_name = (name); \
        int _test_ok = 1; \
        g_tests_run++;

#define ASSERT(expr) \
    do { \
        if (!(expr)) { \
            printf("  FAIL: %s (line %d): %s\n", _test_name, __LINE__, #expr); \
            _test_ok = 0; \
        } \
    } while(0)

#define ASSERT_EQ_I32(a, b) \
    do { \
        int32_t _a = (a); int32_t _b = (b); \
        if (_a != _b) { \
            printf("  FAIL: %s (line %d): %s == %d, expected %d\n", \
                   _test_name, __LINE__, #a, _a, _b); \
            _test_ok = 0; \
        } \
    } while(0)

#define ASSERT_EQ_U32(a, b) \
    do { \
        uint32_t _a = (a); uint32_t _b = (b); \
        if (_a != _b) { \
            printf("  FAIL: %s (line %d): %s == %u, expected %u\n", \
                   _test_name, __LINE__, #a, _a, _b); \
            _test_ok = 0; \
        } \
    } while(0)

#define ASSERT_NULL(ptr) \
    do { \
        if ((ptr) != NULL) { \
            printf("  FAIL: %s (line %d): %s should be NULL\n", \
                   _test_name, __LINE__, #ptr); \
            _test_ok = 0; \
        } \
    } while(0)

#define ASSERT_NOT_NULL(ptr) \
    do { \
        if ((ptr) == NULL) { \
            printf("  FAIL: %s (line %d): %s should not be NULL\n", \
                   _test_name, __LINE__, #ptr); \
            _test_ok = 0; \
        } \
    } while(0)

#define TEST_END() \
        if (_test_ok) { \
            printf("  PASS: %s\n", _test_name); \
            g_tests_passed++; \
        } else { \
            g_tests_failed++; \
        } \
    } while(0)

/* =========================================================================
 * TEST DATA: simple struct for sparse set tests
 * ========================================================================= */

typedef struct {
    int32_t value;
} TestData;

/* =========================================================================
 * SECTION 1: ENTITY ALLOCATOR TESTS
 * ========================================================================= */

static void test_entity_allocator_sequential(void) {
    TEST_BEGIN("entity_alloc: sequential IDs");
    {
        EntityAllocator alloc;
        mc_entity_alloc_init(&alloc);

        ASSERT_EQ_U32(mc_entity_create(&alloc), 0);
        ASSERT_EQ_U32(mc_entity_create(&alloc), 1);
        ASSERT_EQ_U32(mc_entity_create(&alloc), 2);
        ASSERT_EQ_U32(alloc.next_id, 3);
    }
    TEST_END();
}

static void test_entity_allocator_exhaustion(void) {
    TEST_BEGIN("entity_alloc: returns INVALID when exhausted");
    {
        EntityAllocator alloc;
        uint32_t i;
        mc_entity_alloc_init(&alloc);

        /* Burn through all IDs */
        for (i = 0; i < MC_MAX_ENTITIES; i++) {
            ASSERT(mc_entity_create(&alloc) != MC_INVALID_INDEX);
        }
        /* Next one should fail */
        ASSERT_EQ_U32(mc_entity_create(&alloc), MC_INVALID_INDEX);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 2: PRNG TESTS
 * ========================================================================= */

static void test_prng_deterministic(void) {
    TEST_BEGIN("prng: same seed produces same sequence");
    {
        McRng a, b;
        uint32_t i;
        mc_rng_seed(&a, 42);
        mc_rng_seed(&b, 42);

        for (i = 0; i < 1000; i++) {
            ASSERT_EQ_U32(mc_rng_next(&a), mc_rng_next(&b));
        }
    }
    TEST_END();
}

static void test_prng_different_seeds(void) {
    TEST_BEGIN("prng: different seeds produce different sequences");
    {
        McRng a, b;
        int differ = 0;
        uint32_t i;
        mc_rng_seed(&a, 42);
        mc_rng_seed(&b, 99);

        for (i = 0; i < 10; i++) {
            if (mc_rng_next(&a) != mc_rng_next(&b)) differ = 1;
        }
        ASSERT(differ);
    }
    TEST_END();
}

static void test_prng_d100_range(void) {
    TEST_BEGIN("prng: d100 always returns 0-99");
    {
        McRng rng;
        uint32_t i;
        mc_rng_seed(&rng, 12345);

        for (i = 0; i < 10000; i++) {
            int32_t val = mc_rng_d100(&rng);
            ASSERT(val >= 0 && val < 100);
        }
    }
    TEST_END();
}

static void test_prng_distribution(void) {
    TEST_BEGIN("prng: d100 distribution is roughly uniform");
    {
        McRng rng;
        uint32_t i;
        int32_t low_count = 0;  /* 0-49 */
        int32_t high_count = 0; /* 50-99 */
        mc_rng_seed(&rng, 7777);

        for (i = 0; i < 10000; i++) {
            int32_t val = mc_rng_d100(&rng);
            if (val < 50) low_count++;
            else high_count++;
        }
        /* Should be roughly 50/50, allow 10% tolerance */
        ASSERT(low_count > 4000 && low_count < 6000);
        ASSERT(high_count > 4000 && high_count < 6000);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 3: SPARSE SET TESTS
 * ========================================================================= */

/* Each test gets its own SparseSet. Since these are huge (~70KB each),
 * we use a single static one and re-init between tests. */
static SparseSet g_test_ss;

static void test_ss_init_empty(void) {
    TEST_BEGIN("sparse_set: init produces empty set");
    mc_sparse_set_init(&g_test_ss, sizeof(TestData));
    ASSERT_EQ_U32(g_test_ss.count, 0);
    ASSERT_EQ_U32(g_test_ss.stride, sizeof(TestData));
    ASSERT(!mc_sparse_set_has(&g_test_ss, 0));
    ASSERT(!mc_sparse_set_has(&g_test_ss, 999));
    TEST_END();
}

static void test_ss_add_and_get(void) {
    TEST_BEGIN("sparse_set: add then get returns correct data");
    {
        TestData d;
        TestData* fetched;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 42;
        ASSERT_EQ_I32(mc_sparse_set_add(&g_test_ss, 5, &d), 0);
        ASSERT(mc_sparse_set_has(&g_test_ss, 5));
        ASSERT_EQ_U32(g_test_ss.count, 1);

        fetched = (TestData*)mc_sparse_set_get(&g_test_ss, 5);
        ASSERT_NOT_NULL(fetched);
        ASSERT_EQ_I32(fetched->value, 42);
    }
    TEST_END();
}

static void test_ss_add_multiple(void) {
    TEST_BEGIN("sparse_set: add multiple entities with sparse IDs");
    {
        TestData d;
        TestData* f;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 10; mc_sparse_set_add(&g_test_ss, 0, &d);
        d.value = 20; mc_sparse_set_add(&g_test_ss, 50, &d);
        d.value = 30; mc_sparse_set_add(&g_test_ss, 999, &d);

        ASSERT_EQ_U32(g_test_ss.count, 3);
        ASSERT(mc_sparse_set_has(&g_test_ss, 0));
        ASSERT(mc_sparse_set_has(&g_test_ss, 50));
        ASSERT(mc_sparse_set_has(&g_test_ss, 999));
        ASSERT(!mc_sparse_set_has(&g_test_ss, 1));
        ASSERT(!mc_sparse_set_has(&g_test_ss, 500));

        f = (TestData*)mc_sparse_set_get(&g_test_ss, 50);
        ASSERT_NOT_NULL(f);
        ASSERT_EQ_I32(f->value, 20);

        f = (TestData*)mc_sparse_set_get(&g_test_ss, 999);
        ASSERT_NOT_NULL(f);
        ASSERT_EQ_I32(f->value, 30);
    }
    TEST_END();
}

static void test_ss_add_duplicate_fails(void) {
    TEST_BEGIN("sparse_set: add duplicate entity returns -1");
    {
        TestData d;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 1;
        ASSERT_EQ_I32(mc_sparse_set_add(&g_test_ss, 5, &d), 0);
        ASSERT_EQ_I32(mc_sparse_set_add(&g_test_ss, 5, &d), -1);
        ASSERT_EQ_U32(g_test_ss.count, 1);
    }
    TEST_END();
}

static void test_ss_add_out_of_range_fails(void) {
    TEST_BEGIN("sparse_set: add entity >= MAX_ENTITIES returns -1");
    {
        TestData d;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));
        d.value = 1;
        ASSERT_EQ_I32(mc_sparse_set_add(&g_test_ss, MC_MAX_ENTITIES, &d), -1);
        ASSERT_EQ_I32(mc_sparse_set_add(&g_test_ss, MC_MAX_ENTITIES + 100, &d), -1);
        ASSERT_EQ_U32(g_test_ss.count, 0);
    }
    TEST_END();
}

static void test_ss_get_missing_returns_null(void) {
    TEST_BEGIN("sparse_set: get on missing entity returns NULL");
    mc_sparse_set_init(&g_test_ss, sizeof(TestData));
    ASSERT_NULL(mc_sparse_set_get(&g_test_ss, 0));
    ASSERT_NULL(mc_sparse_set_get(&g_test_ss, 999));
    ASSERT_NULL(mc_sparse_set_get_const(&g_test_ss, 0));
    TEST_END();
}

static void test_ss_remove_swap_pop(void) {
    TEST_BEGIN("sparse_set: remove uses swap-and-pop correctly");
    {
        TestData d;
        TestData* f;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 10; mc_sparse_set_add(&g_test_ss, 0, &d);
        d.value = 20; mc_sparse_set_add(&g_test_ss, 1, &d);
        d.value = 30; mc_sparse_set_add(&g_test_ss, 2, &d);
        /* Dense: [0, 1, 2] */

        /* Remove entity 0 -- entity 2 should swap into slot 0 */
        ASSERT_EQ_I32(mc_sparse_set_remove(&g_test_ss, 0), 0);
        ASSERT_EQ_U32(g_test_ss.count, 2);
        ASSERT(!mc_sparse_set_has(&g_test_ss, 0));
        ASSERT(mc_sparse_set_has(&g_test_ss, 1));
        ASSERT(mc_sparse_set_has(&g_test_ss, 2));

        /* Entity 2's data should still be correct */
        f = (TestData*)mc_sparse_set_get(&g_test_ss, 2);
        ASSERT_NOT_NULL(f);
        ASSERT_EQ_I32(f->value, 30);

        /* Entity 1's data should still be correct */
        f = (TestData*)mc_sparse_set_get(&g_test_ss, 1);
        ASSERT_NOT_NULL(f);
        ASSERT_EQ_I32(f->value, 20);
    }
    TEST_END();
}

static void test_ss_remove_last(void) {
    TEST_BEGIN("sparse_set: remove last element (no swap needed)");
    {
        TestData d;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 10; mc_sparse_set_add(&g_test_ss, 0, &d);
        d.value = 20; mc_sparse_set_add(&g_test_ss, 1, &d);

        /* Remove entity 1 (last in dense) */
        ASSERT_EQ_I32(mc_sparse_set_remove(&g_test_ss, 1), 0);
        ASSERT_EQ_U32(g_test_ss.count, 1);
        ASSERT(mc_sparse_set_has(&g_test_ss, 0));
        ASSERT(!mc_sparse_set_has(&g_test_ss, 1));
    }
    TEST_END();
}

static void test_ss_remove_missing_fails(void) {
    TEST_BEGIN("sparse_set: remove missing entity returns -1");
    mc_sparse_set_init(&g_test_ss, sizeof(TestData));
    ASSERT_EQ_I32(mc_sparse_set_remove(&g_test_ss, 0), -1);
    ASSERT_EQ_I32(mc_sparse_set_remove(&g_test_ss, 999), -1);
    TEST_END();
}

static void test_ss_remove_then_readd(void) {
    TEST_BEGIN("sparse_set: remove then re-add same entity");
    {
        TestData d;
        TestData* f;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 10; mc_sparse_set_add(&g_test_ss, 5, &d);
        mc_sparse_set_remove(&g_test_ss, 5);
        ASSERT(!mc_sparse_set_has(&g_test_ss, 5));
        ASSERT_EQ_U32(g_test_ss.count, 0);

        d.value = 99; mc_sparse_set_add(&g_test_ss, 5, &d);
        ASSERT(mc_sparse_set_has(&g_test_ss, 5));
        ASSERT_EQ_U32(g_test_ss.count, 1);

        f = (TestData*)mc_sparse_set_get(&g_test_ss, 5);
        ASSERT_NOT_NULL(f);
        ASSERT_EQ_I32(f->value, 99);
    }
    TEST_END();
}

static void test_ss_packed_iteration(void) {
    TEST_BEGIN("sparse_set: dense array is contiguous for iteration");
    {
        TestData d;
        int32_t sum = 0;
        uint32_t i;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 1; mc_sparse_set_add(&g_test_ss, 10, &d);
        d.value = 2; mc_sparse_set_add(&g_test_ss, 20, &d);
        d.value = 3; mc_sparse_set_add(&g_test_ss, 30, &d);

        /* Iterate packed data -- should see all 3 values */
        for (i = 0; i < g_test_ss.count; i++) {
            TestData* td = (TestData*)&g_test_ss.data[i * g_test_ss.stride];
            sum += td->value;
        }
        ASSERT_EQ_I32(sum, 6); /* 1+2+3 */
    }
    TEST_END();
}

static void test_ss_mutation_during_iteration(void) {
    TEST_BEGIN("sparse_set: mutate data during packed iteration");
    {
        TestData d;
        TestData* f;
        uint32_t i;
        mc_sparse_set_init(&g_test_ss, sizeof(TestData));

        d.value = 10; mc_sparse_set_add(&g_test_ss, 0, &d);
        d.value = 20; mc_sparse_set_add(&g_test_ss, 1, &d);
        d.value = 30; mc_sparse_set_add(&g_test_ss, 2, &d);

        /* Double every value during iteration */
        for (i = 0; i < g_test_ss.count; i++) {
            TestData* td = (TestData*)&g_test_ss.data[i * g_test_ss.stride];
            td->value *= 2;
        }

        f = (TestData*)mc_sparse_set_get(&g_test_ss, 0);
        ASSERT_EQ_I32(f->value, 20);
        f = (TestData*)mc_sparse_set_get(&g_test_ss, 1);
        ASSERT_EQ_I32(f->value, 40);
        f = (TestData*)mc_sparse_set_get(&g_test_ss, 2);
        ASSERT_EQ_I32(f->value, 60);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 4: MATERIAL / LAYER TESTS
 * ========================================================================= */

static void test_material_hardness_table(void) {
    TEST_BEGIN("material: hardness lookup table is correct");
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_NONE],  0);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_WOOD],  30);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_IRON],  80);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_FLESH], 10);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_BARK],  25);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_BONE],  40);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_STONE], 65);
    TEST_END();
}

static void test_layer_peel(void) {
    TEST_BEGIN("layer: damage_layer peels outermost when integrity hits 0");
    {
        SparseSet pool;
        CLayerStack ls;
        CLayerStack* fetched;

        mc_sparse_set_init(&pool, sizeof(CLayerStack));

        ls.layer_count = 2;
        ls.layers[0].material = MAT_BARK; ls.layers[0].integrity = 1; ls.layers[0].max_integrity = 1;
        ls.layers[1].material = MAT_WOOD; ls.layers[1].integrity = 5; ls.layers[1].max_integrity = 5;
        mc_sparse_set_add(&pool, 0, &ls);

        /* Apply damage -- should peel bark */
        apply_effect(EFFECT_DAMAGE_LAYER, 0, &pool);

        fetched = (CLayerStack*)mc_sparse_set_get(&pool, 0);
        ASSERT_NOT_NULL(fetched);
        ASSERT_EQ_U32(fetched->layer_count, 1);
        ASSERT_EQ_I32(fetched->layers[0].material, MAT_WOOD);
        ASSERT_EQ_I32(fetched->layers[0].integrity, 5);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 5: INTERACTION PIPELINE TESTS
 *
 * These are the critical tests. They exercise the full match pipeline
 * without any tick loop -- just direct calls to process_interaction().
 * Each test sets up minimal world state for the specific scenario.
 * ========================================================================= */

/* Helper: set up the standard pools for interaction tests */
static SparseSet tp_caps, tp_affs, tp_anatomy, tp_skills, tp_tool, tp_bp, tp_layers;

static void interaction_pools_init(void) {
    mc_sparse_set_init(&tp_caps,    sizeof(CCapabilities));
    mc_sparse_set_init(&tp_affs,    sizeof(CAffordances));
    mc_sparse_set_init(&tp_anatomy, sizeof(CAnatomy));
    mc_sparse_set_init(&tp_skills,  sizeof(CSkills));
    mc_sparse_set_init(&tp_tool,    sizeof(CTool));
    mc_sparse_set_init(&tp_bp,      sizeof(CBodyParts));
    mc_sparse_set_init(&tp_layers,  sizeof(CLayerStack));
}

/* Helper: create a standard lumberjack (eid 0) with right hand (eid 1)
 * and oak tree (eid 2). Returns nothing -- modifies the global tp_ pools. */
static void create_standard_scenario(void) {
    CCapabilities caps;
    CAffordances affs;
    CAnatomy anat;
    CSkills skills;
    CTool tool;
    CBodyParts bp;
    CLayerStack hand_ls, tree_ls;
    uint32_t i;

    interaction_pools_init();

    /* Entity 0: Lumberjack */
    caps.flags = (1u << CAP_CHOP);
    mc_sparse_set_add(&tp_caps, 0, &caps);

    anat.flags = ANAT_ARMS | ANAT_HANDS | ANAT_LEGS;
    mc_sparse_set_add(&tp_anatomy, 0, &anat);

    memset(&skills, 0, sizeof(skills));
    skills.level[SKILL_WOODCUTTING] = 60;
    mc_sparse_set_add(&tp_skills, 0, &skills);

    tool.material = MAT_IRON;
    mc_sparse_set_add(&tp_tool, 0, &tool);

    for (i = 0; i < MAX_BODY_PARTS; i++) bp.part_entity[i] = MC_INVALID_INDEX;
    bp.part_entity[BODYPART_RIGHT_HAND] = 1;
    mc_sparse_set_add(&tp_bp, 0, &bp);

    /* Entity 1: Right Hand */
    hand_ls.layer_count = 2;
    hand_ls.layers[0].material = MAT_FLESH; hand_ls.layers[0].integrity = 2; hand_ls.layers[0].max_integrity = 2;
    hand_ls.layers[1].material = MAT_BONE;  hand_ls.layers[1].integrity = 3; hand_ls.layers[1].max_integrity = 3;
    mc_sparse_set_add(&tp_layers, 1, &hand_ls);

    /* Entity 2: Oak Tree */
    tree_ls.layer_count = 2;
    tree_ls.layers[0].material = MAT_BARK; tree_ls.layers[0].integrity = 3; tree_ls.layers[0].max_integrity = 3;
    tree_ls.layers[1].material = MAT_WOOD; tree_ls.layers[1].integrity = 5; tree_ls.layers[1].max_integrity = 5;
    mc_sparse_set_add(&tp_layers, 2, &tree_ls);

    affs.flags = (1u << AFF_CHOPPABLE);
    mc_sparse_set_add(&tp_affs, 2, &affs);
}

static InteractResult run_chop(EntityID actor, EntityID target, uint32_t rng_seed) {
    InteractionRequest req;
    McRng rng;
    req.actor = actor; req.target = target; req.verb = VERB_CHOP;
    mc_rng_seed(&rng, rng_seed);
    return process_interaction(&req, &tp_caps, &tp_affs, &tp_anatomy,
                               &tp_skills, &tp_tool, &tp_bp, &tp_layers, &rng);
}

static void test_interact_success(void) {
    TEST_BEGIN("interact: successful chop damages tree bark");
    {
        CLayerStack* tree;
        /* Find a seed that produces a roll >= 5 (the clamped threshold).
         * With crit threshold 15, we need roll >= 15. */
        uint32_t seed = 100;
        InteractResult result;

        create_standard_scenario();

        /* Try seeds until we get SUCCESS (not crit fail or regular fail) */
        while (seed < 10000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) >= 15) break; /* above crit and above threshold */
            seed++;
        }

        result = run_chop(0, 2, seed);
        ASSERT_EQ_I32(result, INTERACT_SUCCESS);

        tree = (CLayerStack*)mc_sparse_set_get(&tp_layers, 2);
        ASSERT_NOT_NULL(tree);
        ASSERT_EQ_I32(tree->layers[0].integrity, 2); /* was 3, now 2 */
    }
    TEST_END();
}

static void test_interact_no_capability(void) {
    TEST_BEGIN("interact: actor without capability -> FAIL_NO_CAP");
    {
        InteractResult result;
        create_standard_scenario();

        /* Remove lumberjack's capabilities */
        mc_sparse_set_remove(&tp_caps, 0);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_NO_CAP);
    }
    TEST_END();
}

static void test_interact_no_anatomy(void) {
    TEST_BEGIN("interact: actor missing anatomy -> FAIL_ANATOMY");
    {
        CAnatomy anat;
        InteractResult result;
        create_standard_scenario();

        /* Give actor legs only -- no arms or hands */
        mc_sparse_set_remove(&tp_anatomy, 0);
        anat.flags = ANAT_LEGS;
        mc_sparse_set_add(&tp_anatomy, 0, &anat);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_ANATOMY);
    }
    TEST_END();
}

static void test_interact_body_part_destroyed(void) {
    TEST_BEGIN("interact: destroyed hand -> FAIL_BODY_PART");
    {
        CLayerStack destroyed_hand;
        InteractResult result;
        create_standard_scenario();

        /* Destroy the hand's layers completely */
        destroyed_hand.layer_count = 0;
        mc_sparse_set_remove(&tp_layers, 1);
        mc_sparse_set_add(&tp_layers, 1, &destroyed_hand);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_BODY_PART);
    }
    TEST_END();
}

static void test_interact_skill_too_low(void) {
    TEST_BEGIN("interact: skill level 0 -> FAIL_SKILL_LOW");
    {
        CSkills skills;
        InteractResult result;
        create_standard_scenario();

        /* Set woodcutting to 0 */
        mc_sparse_set_remove(&tp_skills, 0);
        memset(&skills, 0, sizeof(skills));
        skills.level[SKILL_WOODCUTTING] = 0;
        mc_sparse_set_add(&tp_skills, 0, &skills);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_SKILL_LOW);
    }
    TEST_END();
}

static void test_interact_no_affordance(void) {
    TEST_BEGIN("interact: target without affordance -> FAIL_NO_AFF");
    {
        InteractResult result;
        create_standard_scenario();

        /* Remove tree's affordances */
        mc_sparse_set_remove(&tp_affs, 2);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_NO_AFF);
    }
    TEST_END();
}

static void test_interact_condition_fail(void) {
    TEST_BEGIN("interact: tool softer than layer -> FAIL_CONDITION");
    {
        CTool tool;
        InteractResult result;
        create_standard_scenario();

        /* Give actor a wood tool (hardness 30) -- bark is 25, that passes.
         * But let's make the tree's outer layer Stone (65).  */
        mc_sparse_set_remove(&tp_tool, 0);
        tool.material = MAT_BARK;  /* hardness 25, same as bark = NOT harder */
        mc_sparse_set_add(&tp_tool, 0, &tool);

        result = run_chop(0, 2, 100);
        ASSERT_EQ_I32(result, INTERACT_FAIL_CONDITION);
    }
    TEST_END();
}

static void test_interact_crit_fail_damages_hand(void) {
    TEST_BEGIN("interact: crit fail roll damages actor's hand");
    {
        CLayerStack* hand;
        uint32_t seed = 0;
        InteractResult result;

        create_standard_scenario();

        /* Find a seed that produces roll < 15 (crit threshold for CHOPPABLE) */
        while (seed < 100000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) < 15) break;
            seed++;
        }

        result = run_chop(0, 2, seed);
        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);

        /* Hand should have taken damage (crit_fail_damage=2 for CHOPPABLE) */
        hand = (CLayerStack*)mc_sparse_set_get(&tp_layers, 1);
        ASSERT_NOT_NULL(hand);
        /* Original: Flesh 2/2 + Bone 3/3.
         * Damage loop (2 hits): Flesh 2->1, Flesh 1->0 (destroyed+peeled).
         * Both damage points consumed by Flesh. Bone now outermost at 3/3. */
        ASSERT_EQ_U32(hand->layer_count, 1);  /* flesh peeled */
        ASSERT_EQ_I32(hand->layers[0].material, MAT_BONE);
        ASSERT_EQ_I32(hand->layers[0].integrity, 3);  /* untouched */
    }
    TEST_END();
}

static void test_interact_cascading_failure(void) {
    TEST_BEGIN("interact: crit fail -> hand destroyed -> subsequent chops fail");
    {
        CLayerStack fragile_hand;
        uint32_t seed = 0;
        InteractResult result;

        create_standard_scenario();

        /* Make hand fragile: Flesh 1, Bone 1. Crit damage of 2 will destroy it. */
        mc_sparse_set_remove(&tp_layers, 1);
        fragile_hand.layer_count = 2;
        fragile_hand.layers[0].material = MAT_FLESH; fragile_hand.layers[0].integrity = 1; fragile_hand.layers[0].max_integrity = 1;
        fragile_hand.layers[1].material = MAT_BONE;  fragile_hand.layers[1].integrity = 1; fragile_hand.layers[1].max_integrity = 1;
        mc_sparse_set_add(&tp_layers, 1, &fragile_hand);

        /* Find crit fail seed */
        while (seed < 100000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) < 15) break;
            seed++;
        }

        /* First: crit fail destroys hand */
        result = run_chop(0, 2, seed);
        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);

        /* Verify hand is fully destroyed */
        {
            CLayerStack* hand = (CLayerStack*)mc_sparse_set_get(&tp_layers, 1);
            ASSERT_NOT_NULL(hand);
            ASSERT_EQ_U32(hand->layer_count, 0);
        }

        /* Second: try to chop again -- should fail at body part check */
        result = run_chop(0, 2, 99999);
        ASSERT_EQ_I32(result, INTERACT_FAIL_BODY_PART);
    }
    TEST_END();
}

static void test_interact_invalid_verb(void) {
    TEST_BEGIN("interact: invalid verb ID -> FAIL_NO_VERB");
    {
        InteractionRequest req;
        McRng rng;
        InteractResult result;
        create_standard_scenario();

        req.actor = 0; req.target = 2; req.verb = VERB_NONE;
        mc_rng_seed(&rng, 42);
        result = process_interaction(&req, &tp_caps, &tp_affs, &tp_anatomy,
                                     &tp_skills, &tp_tool, &tp_bp, &tp_layers, &rng);
        ASSERT_EQ_I32(result, INTERACT_FAIL_NO_VERB);
    }
    TEST_END();
}

static void test_interact_deterministic_replay(void) {
    TEST_BEGIN("interact: same seed produces identical results across runs");
    {
        InteractResult r1, r2;
        CLayerStack *tree1_before, *tree2_before;
        int32_t integrity_before_1, integrity_before_2;

        /* Run 1 */
        create_standard_scenario();
        tree1_before = (CLayerStack*)mc_sparse_set_get(&tp_layers, 2);
        integrity_before_1 = tree1_before->layers[0].integrity;
        r1 = run_chop(0, 2, 42);

        /* Run 2 -- fresh state, same seed */
        create_standard_scenario();
        tree2_before = (CLayerStack*)mc_sparse_set_get(&tp_layers, 2);
        integrity_before_2 = tree2_before->layers[0].integrity;
        r2 = run_chop(0, 2, 42);

        ASSERT_EQ_I32(r1, r2);
        ASSERT_EQ_I32(integrity_before_1, integrity_before_2);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 6: FREQUENCY GATING TEST
 * ========================================================================= */

static void test_frequency_gating(void) {
    TEST_BEGIN("frequency: modulo gating fires at correct ticks");
    {
        uint32_t freq1_count = 0, freq2_count = 0, freq3_count = 0;
        uint64_t tick;

        for (tick = 0; tick < 12; tick++) {
            if (tick % 1 == 0) freq1_count++;
            if (tick % 2 == 0) freq2_count++;
            if (tick % 3 == 0) freq3_count++;
        }

        ASSERT_EQ_U32(freq1_count, 12);  /* every tick */
        ASSERT_EQ_U32(freq2_count, 6);   /* 0,2,4,6,8,10 */
        ASSERT_EQ_U32(freq3_count, 4);   /* 0,3,6,9 */
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 7: CONDITION EVALUATOR TESTS
 * ========================================================================= */

static void test_condition_tool_harder(void) {
    TEST_BEGIN("condition: iron tool (80) is harder than bark layer (25)");
    {
        SparseSet pool_tool, pool_layers;
        CTool tool;
        CLayerStack ls;

        mc_sparse_set_init(&pool_tool,   sizeof(CTool));
        mc_sparse_set_init(&pool_layers, sizeof(CLayerStack));

        tool.material = MAT_IRON;
        mc_sparse_set_add(&pool_tool, 0, &tool);

        ls.layer_count = 1;
        ls.layers[0].material = MAT_BARK; ls.layers[0].integrity = 3; ls.layers[0].max_integrity = 3;
        mc_sparse_set_add(&pool_layers, 1, &ls);

        ASSERT(evaluate_condition(COND_TOOL_HARDER_THAN_LAYER, 0, 1, &pool_tool, &pool_layers));
    }
    TEST_END();
}

static void test_condition_tool_not_harder(void) {
    TEST_BEGIN("condition: wood tool (30) is NOT harder than stone layer (65)");
    {
        SparseSet pool_tool, pool_layers;
        CTool tool;
        CLayerStack ls;

        mc_sparse_set_init(&pool_tool,   sizeof(CTool));
        mc_sparse_set_init(&pool_layers, sizeof(CLayerStack));

        tool.material = MAT_WOOD;
        mc_sparse_set_add(&pool_tool, 0, &tool);

        ls.layer_count = 1;
        ls.layers[0].material = MAT_STONE; ls.layers[0].integrity = 5; ls.layers[0].max_integrity = 5;
        mc_sparse_set_add(&pool_layers, 1, &ls);

        ASSERT(!evaluate_condition(COND_TOOL_HARDER_THAN_LAYER, 0, 1, &pool_tool, &pool_layers));
    }
    TEST_END();
}

static void test_condition_no_tool(void) {
    TEST_BEGIN("condition: actor without tool -> condition fails");
    {
        SparseSet pool_tool, pool_layers;
        CLayerStack ls;

        mc_sparse_set_init(&pool_tool,   sizeof(CTool));
        mc_sparse_set_init(&pool_layers, sizeof(CLayerStack));

        ls.layer_count = 1;
        ls.layers[0].material = MAT_BARK; ls.layers[0].integrity = 3; ls.layers[0].max_integrity = 3;
        mc_sparse_set_add(&pool_layers, 1, &ls);

        /* Actor 0 has no tool */
        ASSERT(!evaluate_condition(COND_TOOL_HARDER_THAN_LAYER, 0, 1, &pool_tool, &pool_layers));
    }
    TEST_END();
}

/* =========================================================================
 * RUN ALL TESTS
 * ========================================================================= */

int main(void) {
    printf("MarbleEngine Test Harness\n");
    printf("=========================\n\n");

    /* Entity Allocator */
    printf("[Entity Allocator]\n");
    test_entity_allocator_sequential();
    test_entity_allocator_exhaustion();

    /* PRNG */
    printf("\n[Deterministic PRNG]\n");
    test_prng_deterministic();
    test_prng_different_seeds();
    test_prng_d100_range();
    test_prng_distribution();

    /* Sparse Set */
    printf("\n[Sparse Set]\n");
    test_ss_init_empty();
    test_ss_add_and_get();
    test_ss_add_multiple();
    test_ss_add_duplicate_fails();
    test_ss_add_out_of_range_fails();
    test_ss_get_missing_returns_null();
    test_ss_remove_swap_pop();
    test_ss_remove_last();
    test_ss_remove_missing_fails();
    test_ss_remove_then_readd();
    test_ss_packed_iteration();
    test_ss_mutation_during_iteration();

    /* Materials & Layers */
    printf("\n[Materials & Layers]\n");
    test_material_hardness_table();
    test_layer_peel();

    /* Conditions */
    printf("\n[Condition Evaluator]\n");
    test_condition_tool_harder();
    test_condition_tool_not_harder();
    test_condition_no_tool();

    /* Frequency Gating */
    printf("\n[Frequency Gating]\n");
    test_frequency_gating();

    /* Interaction Pipeline */
    printf("\n[Interaction Pipeline]\n");
    test_interact_success();
    test_interact_no_capability();
    test_interact_no_anatomy();
    test_interact_body_part_destroyed();
    test_interact_skill_too_low();
    test_interact_no_affordance();
    test_interact_condition_fail();
    test_interact_crit_fail_damages_hand();
    test_interact_cascading_failure();
    test_interact_invalid_verb();
    test_interact_deterministic_replay();

    /* Summary */
    printf("\n=========================\n");
    printf("TOTAL: %d  PASSED: %d  FAILED: %d\n",
           g_tests_run, g_tests_passed, g_tests_failed);

    if (g_tests_failed == 0) {
        printf("ALL TESTS PASSED\n");
    } else {
        printf("*** FAILURES DETECTED ***\n");
    }

    return (g_tests_failed > 0) ? 1 : 0;
}