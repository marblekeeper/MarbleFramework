/*
 * test_cmd.c -- Command Buffer + Rule System Tests
 *
 * Tests the new architecture where:
 *   - Systems emit commands (never mutate pools directly)
 *   - Commands are validated and applied at tick boundary
 *   - Rules define multi-effect interactions
 *
 * BUILD:
 *   gcc -std=c99 -Wall -Wextra -O2 test_cmd.c -o test_cmd.exe
 */

#include "marble_cmd.h"

/* =========================================================================
 * TEST FRAMEWORK (same as test.c)
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
 * SECTION 1: COMMAND BUFFER PRIMITIVE TESTS
 * ========================================================================= */

static void test_cmd_buf_init(void) {
    TEST_BEGIN("cmd_buf: init produces empty buffer");
    {
        CommandBuffer buf;
        mc_cmd_buf_init(&buf);
        ASSERT_EQ_U32(buf.count, 0);
        ASSERT_EQ_U32(buf.applied, 0);
        ASSERT_EQ_U32(buf.rejected, 0);
    }
    TEST_END();
}

static void test_cmd_push_and_count(void) {
    TEST_BEGIN("cmd_buf: push increments count");
    {
        CommandBuffer buf;
        mc_cmd_buf_init(&buf);

        mc_emit_feedback(&buf, 0, 0, 42);
        ASSERT_EQ_U32(buf.count, 1);

        mc_emit_feedback(&buf, 0, 0, 43);
        ASSERT_EQ_U32(buf.count, 2);
    }
    TEST_END();
}

static void test_cmd_push_overflow(void) {
    TEST_BEGIN("cmd_buf: push returns -1 when full");
    {
        CommandBuffer buf;
        Command cmd;
        uint32_t i;
        mc_cmd_buf_init(&buf);
        memset(&cmd, 0, sizeof(cmd));
        cmd.type = CMD_PLAY_FEEDBACK;

        for (i = 0; i < MAX_COMMANDS; i++) {
            ASSERT_EQ_I32(mc_cmd_push(&buf, &cmd), 0);
        }
        /* Next push should fail */
        ASSERT_EQ_I32(mc_cmd_push(&buf, &cmd), -1);
        ASSERT_EQ_U32(buf.count, MAX_COMMANDS);
    }
    TEST_END();
}

static void test_cmd_flush_resets(void) {
    TEST_BEGIN("cmd_buf: flush resets count to 0");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        memset(&pools, 0, sizeof(pools));
        mc_cmd_buf_init(&buf);

        mc_emit_feedback(&buf, 0, 0, 1);
        mc_emit_feedback(&buf, 0, 0, 2);
        ASSERT_EQ_U32(buf.count, 2);

        mc_cmd_flush(&buf, &pools);
        ASSERT_EQ_U32(buf.count, 0);
        ASSERT_EQ_U32(buf.applied, 2);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 2: DAMAGE VIA COMMAND BUFFER
 * ========================================================================= */

static SparseSet g_tp_layers;

static void test_cmd_damage_layer(void) {
    TEST_BEGIN("cmd_buf: DAMAGE_LAYER reduces integrity via flush");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CLayerStack ls;
        CLayerStack* fetched;

        mc_cmd_buf_init(&buf);
        mc_sparse_set_init(&g_tp_layers, sizeof(CLayerStack));

        ls.layer_count = 2;
        ls.layers[0].material = MAT_BARK; ls.layers[0].integrity = 3; ls.layers[0].max_integrity = 3;
        ls.layers[1].material = MAT_WOOD; ls.layers[1].integrity = 5; ls.layers[1].max_integrity = 5;
        mc_sparse_set_add(&g_tp_layers, 10, &ls);

        /* Emit damage command -- pool is NOT mutated yet */
        mc_emit_damage_layer(&buf, 0, 0, 10, 1);
        ASSERT_EQ_U32(buf.count, 1);

        /* Verify pool is still untouched before flush */
        fetched = (CLayerStack*)mc_sparse_set_get(&g_tp_layers, 10);
        ASSERT_EQ_I32(fetched->layers[0].integrity, 3); /* still 3! */

        /* Flush -- NOW it mutates */
        pools.layers = &g_tp_layers;
        pools.item_defs = NULL;
        mc_cmd_flush(&buf, &pools);

        fetched = (CLayerStack*)mc_sparse_set_get(&g_tp_layers, 10);
        ASSERT_EQ_I32(fetched->layers[0].integrity, 2); /* now 2 */
        ASSERT_EQ_U32(buf.applied, 1);
    }
    TEST_END();
}

static void test_cmd_damage_peels_layer(void) {
    TEST_BEGIN("cmd_buf: DAMAGE_LAYER peels destroyed layer on flush");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CLayerStack ls;
        CLayerStack* fetched;

        mc_cmd_buf_init(&buf);
        mc_sparse_set_init(&g_tp_layers, sizeof(CLayerStack));

        ls.layer_count = 2;
        ls.layers[0].material = MAT_BARK; ls.layers[0].integrity = 1; ls.layers[0].max_integrity = 1;
        ls.layers[1].material = MAT_WOOD; ls.layers[1].integrity = 5; ls.layers[1].max_integrity = 5;
        mc_sparse_set_add(&g_tp_layers, 10, &ls);

        mc_emit_damage_layer(&buf, 0, 0, 10, 1);

        pools.layers = &g_tp_layers;
        pools.item_defs = NULL;
        mc_cmd_flush(&buf, &pools);

        fetched = (CLayerStack*)mc_sparse_set_get(&g_tp_layers, 10);
        ASSERT_EQ_U32(fetched->layer_count, 1);
        ASSERT_EQ_I32(fetched->layers[0].material, MAT_WOOD);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 3: CRIT DAMAGE VIA COMMAND BUFFER
 * ========================================================================= */

static void test_cmd_crit_damage(void) {
    TEST_BEGIN("cmd_buf: CRIT_DAMAGE destroys hand layers via flush");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CLayerStack hand_ls;
        CLayerStack* fetched;

        mc_cmd_buf_init(&buf);
        mc_sparse_set_init(&g_tp_layers, sizeof(CLayerStack));

        hand_ls.layer_count = 2;
        hand_ls.layers[0].material = MAT_FLESH; hand_ls.layers[0].integrity = 1; hand_ls.layers[0].max_integrity = 1;
        hand_ls.layers[1].material = MAT_BONE;  hand_ls.layers[1].integrity = 1; hand_ls.layers[1].max_integrity = 1;
        mc_sparse_set_add(&g_tp_layers, 1, &hand_ls);

        /* Emit crit damage (2 points to hand with 1+1 layers) */
        mc_emit_crit_damage(&buf, 0, 0, 1, BODYPART_RIGHT_HAND, 2);

        pools.layers = &g_tp_layers;
        pools.item_defs = NULL;
        mc_cmd_flush(&buf, &pools);

        fetched = (CLayerStack*)mc_sparse_set_get(&g_tp_layers, 1);
        ASSERT_EQ_U32(fetched->layer_count, 0); /* fully destroyed */
        ASSERT_EQ_U32(buf.applied, 1);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 4: TRANSFORM VIA COMMAND BUFFER
 * ========================================================================= */

static SparseSet g_tp_item_defs;

static void test_cmd_transform(void) {
    TEST_BEGIN("cmd_buf: TRANSFORM_ENTITY changes def_id via flush");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CItemDef def;
        CItemDef* fetched;

        mc_cmd_buf_init(&buf);
        mc_sparse_set_init(&g_tp_item_defs, sizeof(CItemDef));

        def.def_id = 900;  /* Golden Apple */
        mc_sparse_set_add(&g_tp_item_defs, 50, &def);

        /* Emit transform: Golden Apple -> Apple Core */
        mc_emit_transform(&buf, 0, 0, 50, 901);

        /* Verify NOT transformed yet */
        fetched = (CItemDef*)mc_sparse_set_get(&g_tp_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 900);

        pools.layers = NULL;
        pools.item_defs = &g_tp_item_defs;
        mc_cmd_flush(&buf, &pools);

        fetched = (CItemDef*)mc_sparse_set_get(&g_tp_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 901); /* now Apple Core */
    }
    TEST_END();
}

static void test_cmd_transform_chain(void) {
    TEST_BEGIN("cmd_buf: multi-step transform chain (apple -> core -> seeds)");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CItemDef def;
        CItemDef* fetched;

        mc_sparse_set_init(&g_tp_item_defs, sizeof(CItemDef));
        pools.layers = NULL;
        pools.item_defs = &g_tp_item_defs;

        def.def_id = 900;  /* Golden Apple */
        mc_sparse_set_add(&g_tp_item_defs, 50, &def);

        /* Step 1: Eat apple -> apple core */
        mc_cmd_buf_init(&buf);
        mc_emit_transform(&buf, 0, 0, 50, 901);
        mc_cmd_flush(&buf, &pools);
        fetched = (CItemDef*)mc_sparse_set_get(&g_tp_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 901);

        /* Step 2: Extract seeds from core -> apple seeds */
        mc_cmd_buf_init(&buf);
        mc_emit_transform(&buf, 1, 0, 50, 902);
        mc_cmd_flush(&buf, &pools);
        fetched = (CItemDef*)mc_sparse_set_get(&g_tp_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 902);

        /* Step 3: Plant seeds -> sapling */
        mc_cmd_buf_init(&buf);
        mc_emit_transform(&buf, 2, 0, 50, 903);
        mc_cmd_flush(&buf, &pools);
        fetched = (CItemDef*)mc_sparse_set_get(&g_tp_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 903);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 5: MULTI-COMMAND FLUSH (atomic batch)
 * ========================================================================= */

static void test_cmd_multi_command_batch(void) {
    TEST_BEGIN("cmd_buf: multiple commands applied in single flush");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        CLayerStack ls;
        CLayerStack* fetched;

        mc_cmd_buf_init(&buf);
        mc_sparse_set_init(&g_tp_layers, sizeof(CLayerStack));

        ls.layer_count = 1;
        ls.layers[0].material = MAT_WOOD; ls.layers[0].integrity = 5; ls.layers[0].max_integrity = 5;
        mc_sparse_set_add(&g_tp_layers, 10, &ls);

        /* Emit 3 damage commands in one tick */
        mc_emit_damage_layer(&buf, 0, 0, 10, 1);
        mc_emit_damage_layer(&buf, 0, 0, 10, 1);
        mc_emit_damage_layer(&buf, 0, 0, 10, 1);
        ASSERT_EQ_U32(buf.count, 3);

        pools.layers = &g_tp_layers;
        pools.item_defs = NULL;
        mc_cmd_flush(&buf, &pools);

        fetched = (CLayerStack*)mc_sparse_set_get(&g_tp_layers, 10);
        ASSERT_EQ_I32(fetched->layers[0].integrity, 2); /* 5 - 3 = 2 */
        ASSERT_EQ_U32(buf.applied, 3);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 6: RULE SYSTEM TESTS
 * ========================================================================= */

/* Standard pools for rule tests */
static SparseSet rp_caps, rp_affs, rp_anatomy, rp_skills, rp_tool, rp_bp, rp_layers;

static void rule_pools_init(void) {
    mc_sparse_set_init(&rp_caps,    sizeof(CCapabilities));
    mc_sparse_set_init(&rp_affs,    sizeof(CAffordances));
    mc_sparse_set_init(&rp_anatomy, sizeof(CAnatomy));
    mc_sparse_set_init(&rp_skills,  sizeof(CSkills));
    mc_sparse_set_init(&rp_tool,    sizeof(CTool));
    mc_sparse_set_init(&rp_bp,      sizeof(CBodyParts));
    mc_sparse_set_init(&rp_layers,  sizeof(CLayerStack));
}

/* Create standard lumberjack + tree for rule tests */
static void create_rule_scenario(void) {
    CCapabilities caps;
    CAffordances affs;
    CAnatomy anat;
    CSkills skills;
    CTool tool;
    CBodyParts bp;
    CLayerStack hand_ls, tree_ls;
    uint32_t i;

    rule_pools_init();

    /* Entity 0: Lumberjack */
    caps.flags = (1u << CAP_CHOP);
    mc_sparse_set_add(&rp_caps, 0, &caps);
    anat.flags = ANAT_ARMS | ANAT_HANDS | ANAT_LEGS;
    mc_sparse_set_add(&rp_anatomy, 0, &anat);
    memset(&skills, 0, sizeof(skills));
    skills.level[SKILL_WOODCUTTING] = 60;
    mc_sparse_set_add(&rp_skills, 0, &skills);
    tool.material = MAT_IRON;
    mc_sparse_set_add(&rp_tool, 0, &tool);
    for (i = 0; i < MAX_BODY_PARTS; i++) bp.part_entity[i] = MC_INVALID_INDEX;
    bp.part_entity[BODYPART_RIGHT_HAND] = 1;
    mc_sparse_set_add(&rp_bp, 0, &bp);

    /* Entity 1: Right Hand */
    hand_ls.layer_count = 2;
    hand_ls.layers[0].material = MAT_FLESH; hand_ls.layers[0].integrity = 1; hand_ls.layers[0].max_integrity = 1;
    hand_ls.layers[1].material = MAT_BONE;  hand_ls.layers[1].integrity = 1; hand_ls.layers[1].max_integrity = 1;
    mc_sparse_set_add(&rp_layers, 1, &hand_ls);

    /* Entity 2: Oak Tree */
    tree_ls.layer_count = 2;
    tree_ls.layers[0].material = MAT_BARK; tree_ls.layers[0].integrity = 3; tree_ls.layers[0].max_integrity = 3;
    tree_ls.layers[1].material = MAT_WOOD; tree_ls.layers[1].integrity = 5; tree_ls.layers[1].max_integrity = 5;
    mc_sparse_set_add(&rp_layers, 2, &tree_ls);
    affs.flags = (1u << AFF_CHOPPABLE);
    mc_sparse_set_add(&rp_affs, 2, &affs);
}

/* Define the Chop rule (equivalent to old AffordanceDef for CHOPPABLE) */
static RuleDef make_chop_rule(void) {
    RuleDef r;
    memset(&r, 0, sizeof(r));
    r.rule_id        = 1;
    r.trigger_verb   = VERB_CHOP;
    r.required_cap   = CAP_CHOP;
    r.difficulty      = 40;
    r.crit_fail_threshold = 15;
    r.crit_fail_bodypart  = BODYPART_RIGHT_HAND;
    r.crit_fail_damage    = 2;

    /* Condition: tool harder than layer */
    r.cond_ids[0] = COND_TOOL_HARDER_THAN_LAYER;
    r.cond_count = 1;

    /* Effect: damage target's outermost layer */
    r.effects[0].type        = CMD_DAMAGE_LAYER;
    r.effects[0].target_role = CMD_TARGET_TARGET;
    r.effects[0].amount      = 1;
    r.effect_count = 1;

    return r;
}

static void test_rule_success_emits_commands(void) {
    TEST_BEGIN("rule: successful chop emits DAMAGE_LAYER command");
    {
        CommandBuffer buf;
        RuleDef rules[1];
        InteractResult result;
        InteractionRequest req;
        uint32_t seed = 100;
        McRng rng;

        create_rule_scenario();
        mc_cmd_buf_init(&buf);
        rules[0] = make_chop_rule();

        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Find a seed that avoids crit fail (roll >= 15) */
        while (seed < 10000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) >= 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_SUCCESS);
        ASSERT_EQ_U32(buf.count, 1); /* one DAMAGE_LAYER command */
        ASSERT_EQ_I32(buf.commands[0].type, CMD_DAMAGE_LAYER);
        ASSERT_EQ_U32(buf.commands[0].target_entity, 2); /* oak tree */

        /* Pool is still untouched -- read-only invariant */
        {
            const CLayerStack* tree = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 2);
            ASSERT_EQ_I32(tree->layers[0].integrity, 3); /* still 3! */
        }
    }
    TEST_END();
}

static void test_rule_crit_emits_crit_cmd(void) {
    TEST_BEGIN("rule: crit fail emits CRIT_DAMAGE command (not direct mutation)");
    {
        CommandBuffer buf;
        RuleDef rules[1];
        InteractResult result;
        InteractionRequest req;
        uint32_t seed = 0;
        McRng rng;

        create_rule_scenario();
        mc_cmd_buf_init(&buf);
        rules[0] = make_chop_rule();

        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Find crit fail seed (roll < 15) */
        while (seed < 100000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) < 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);
        ASSERT_EQ_U32(buf.count, 1); /* one CRIT_DAMAGE command */
        ASSERT_EQ_I32(buf.commands[0].type, CMD_CRIT_DAMAGE);
        ASSERT_EQ_U32(buf.commands[0].target_entity, 1); /* hand entity */
        ASSERT_EQ_I32(buf.commands[0].damage_amount, 2);

        /* Hand is STILL INTACT -- cmd not applied yet */
        {
            const CLayerStack* hand = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 1);
            ASSERT_EQ_U32(hand->layer_count, 2); /* still 2 layers! */
        }
    }
    TEST_END();
}

static void test_rule_read_only_invariant(void) {
    TEST_BEGIN("rule: pools are never mutated during process_rule");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        RuleDef rules[1];
        InteractionRequest req;
        McRng rng;
        uint32_t seed = 100;

        create_rule_scenario();
        mc_cmd_buf_init(&buf);
        rules[0] = make_chop_rule();

        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Success path */
        while (seed < 10000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) >= 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        process_rule(&req, rules, 1,
                     &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                     &rp_bp, &rp_layers, &rp_affs,
                     MC_INVALID_INDEX, &buf, &rng, 0);

        /* Verify ALL pools are untouched */
        {
            const CLayerStack* tree = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 2);
            const CLayerStack* hand = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 1);
            ASSERT_EQ_I32(tree->layers[0].integrity, 3);
            ASSERT_EQ_U32(hand->layer_count, 2);
        }

        /* NOW flush -- mutations happen */
        pools.layers = &rp_layers;
        pools.item_defs = NULL;
        mc_cmd_flush(&buf, &pools);

        {
            const CLayerStack* tree = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 2);
            ASSERT_EQ_I32(tree->layers[0].integrity, 2); /* NOW damaged */
        }
    }
    TEST_END();
}

static void test_rule_no_match(void) {
    TEST_BEGIN("rule: unmatched verb returns FAIL_NO_RULE");
    {
        CommandBuffer buf;
        RuleDef rules[1];
        InteractionRequest req;
        McRng rng;
        InteractResult result;

        create_rule_scenario();
        mc_cmd_buf_init(&buf);
        rules[0] = make_chop_rule();

        req.actor = 0; req.target = 2; req.verb = VERB_MINE;
        mc_rng_seed(&rng, 42);

        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_FAIL_NO_RULE);
        ASSERT_EQ_U32(buf.count, 0);
    }
    TEST_END();
}

static void test_rule_multi_effect(void) {
    TEST_BEGIN("rule: multi-effect rule emits multiple commands");
    {
        CommandBuffer buf;
        RuleDef rules[1];
        InteractResult result;
        InteractionRequest req;
        uint32_t seed = 100;
        McRng rng;

        create_rule_scenario();
        mc_cmd_buf_init(&buf);

        /* Build a chop rule with 3 effects:
         * 1. Damage target layer
         * 2. Modify actor stamina
         * 3. Play feedback */
        rules[0] = make_chop_rule();
        rules[0].effects[1].type        = CMD_MODIFY_STAT;
        rules[0].effects[1].target_role = CMD_TARGET_ACTOR;
        rules[0].effects[1].stat_id     = 0; /* stamina */
        rules[0].effects[1].amount      = 8;
        rules[0].effects[1].stat_op     = OP_SUBTRACT;
        rules[0].effects[2].type        = CMD_PLAY_FEEDBACK;
        rules[0].effects[2].target_role = CMD_TARGET_ACTOR;
        rules[0].effects[2].message_id  = 100;
        rules[0].effect_count = 3;

        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        while (seed < 10000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) >= 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_SUCCESS);
        ASSERT_EQ_U32(buf.count, 3);
        ASSERT_EQ_I32(buf.commands[0].type, CMD_DAMAGE_LAYER);
        ASSERT_EQ_I32(buf.commands[1].type, CMD_MODIFY_STAT);
        ASSERT_EQ_I32(buf.commands[2].type, CMD_PLAY_FEEDBACK);
    }
    TEST_END();
}

static void test_rule_cascading_via_cmd_buf(void) {
    TEST_BEGIN("rule: crit fail -> flush -> hand destroyed -> next rule fails body part");
    {
        CommandBuffer buf;
        PoolPtrs pools;
        RuleDef rules[1];
        InteractResult result;
        InteractionRequest req;
        uint32_t seed = 0;
        McRng rng;

        create_rule_scenario();
        rules[0] = make_chop_rule();
        pools.layers = &rp_layers;
        pools.item_defs = NULL;

        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Find crit fail seed */
        while (seed < 100000) {
            McRng test_rng;
            mc_rng_seed(&test_rng, seed);
            if (mc_rng_d100(&test_rng) < 15) break;
            seed++;
        }

        /* Tick 0: Crit fail -- emit command */
        mc_cmd_buf_init(&buf);
        mc_rng_seed(&rng, seed);
        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 0);
        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);

        /* Tick boundary: flush applies crit damage */
        mc_cmd_flush(&buf, &pools);

        /* Verify hand is destroyed */
        {
            const CLayerStack* hand = (const CLayerStack*)mc_sparse_set_get_const(&rp_layers, 1);
            ASSERT_EQ_U32(hand->layer_count, 0);
        }

        /* Tick 1: Try to chop again -- should fail body part check */
        mc_cmd_buf_init(&buf);
        mc_rng_seed(&rng, 99999);
        result = process_rule(&req, rules, 1,
                              &rp_caps, &rp_anatomy, &rp_skills, &rp_tool,
                              &rp_bp, &rp_layers, &rp_affs,
                              MC_INVALID_INDEX, &buf, &rng, 1);
        ASSERT_EQ_I32(result, INTERACT_FAIL_BODY_PART);
        ASSERT_EQ_U32(buf.count, 0); /* no commands emitted */
    }
    TEST_END();
}

/* =========================================================================
 * RUN ALL TESTS
 * ========================================================================= */

int main(void) {
    printf("MarbleEngine Command Buffer + Rule System Tests\n");
    printf("================================================\n\n");

    /* Command Buffer Primitives */
    printf("[Command Buffer]\n");
    test_cmd_buf_init();
    test_cmd_push_and_count();
    test_cmd_push_overflow();
    test_cmd_flush_resets();

    /* Damage via Buffer */
    printf("\n[Damage via Command Buffer]\n");
    test_cmd_damage_layer();
    test_cmd_damage_peels_layer();

    /* Crit Damage via Buffer */
    printf("\n[Crit Damage via Command Buffer]\n");
    test_cmd_crit_damage();

    /* Transform via Buffer */
    printf("\n[Transform via Command Buffer]\n");
    test_cmd_transform();
    test_cmd_transform_chain();

    /* Multi-Command Batch */
    printf("\n[Multi-Command Batch]\n");
    test_cmd_multi_command_batch();

    /* Rule System */
    printf("\n[Rule System]\n");
    test_rule_success_emits_commands();
    test_rule_crit_emits_crit_cmd();
    test_rule_read_only_invariant();
    test_rule_no_match();
    test_rule_multi_effect();
    test_rule_cascading_via_cmd_buf();

    /* Summary */
    printf("\n================================================\n");
    printf("TOTAL: %d  PASSED: %d  FAILED: %d\n",
           g_tests_run, g_tests_passed, g_tests_failed);

    if (g_tests_failed == 0) {
        printf("ALL TESTS PASSED\n");
    } else {
        printf("*** FAILURES DETECTED ***\n");
    }

    return (g_tests_failed > 0) ? 1 : 0;
}