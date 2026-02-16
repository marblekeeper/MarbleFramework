/*
 * test_gen.c -- Tests using ONLY generated code from marble_gen.h
 *
 * This proves the full pipeline:
 *   oak_forest.marble -> marble_compile.lua -> marble_gen.h -> test
 *
 * NO hand-written marble_interact.h is included.
 * All types, enums, data tables, conditions, and rules come from
 * the generated header.
 *
 * BUILD:
 *   lua marble_compile.lua oak_forest.marble -o marble_gen.h
 *   gcc -std=c99 -Wall -Wextra -O2 test_gen.c -o test_gen.exe
 */

#include "marble_gen.h"

/* =========================================================================
 * COMMAND BUFFER (inline subset of marble_cmd.h)
 *
 * We duplicate the minimal command buffer here to avoid including
 * marble_cmd.h which includes marble_interact.h. In Phase 1 we'll
 * refactor the include chain. For now this proves the gen header
 * works in complete isolation.
 * ========================================================================= */

#define MAX_COMMANDS 256

typedef struct {
    CommandType type;
    EntityID    source_entity;
    EntityID    target_entity;
    int32_t     damage_amount;
    uint32_t    bodypart_id;
    uint32_t    stat_id;
    int32_t     stat_amount;
    StatOperation stat_op;
    uint32_t    new_def_id;
    uint32_t    destination;
    uint32_t    message_id;
    uint64_t    tick;
} Command;

typedef struct {
    Command  commands[MAX_COMMANDS];
    uint32_t count;
    uint32_t applied;
    uint32_t rejected;
} CommandBuffer;

static void cmd_init(CommandBuffer* b) { b->count = 0; b->applied = 0; b->rejected = 0; }

static int cmd_push(CommandBuffer* b, const Command* c) {
    if (b->count >= MAX_COMMANDS) return -1;
    b->commands[b->count] = *c;
    b->count++;
    return 0;
}

static void cmd_emit_damage(CommandBuffer* b, uint64_t tick, EntityID src, EntityID tgt, int32_t amt) {
    Command c; memset(&c, 0, sizeof(c));
    c.type = CMD_DAMAGE_LAYER; c.source_entity = src; c.target_entity = tgt;
    c.damage_amount = amt; c.tick = tick;
    cmd_push(b, &c);
}

static void cmd_emit_crit(CommandBuffer* b, uint64_t tick, EntityID src, EntityID tgt, uint32_t bp, int32_t amt) {
    Command c; memset(&c, 0, sizeof(c));
    c.type = CMD_CRIT_DAMAGE; c.source_entity = src; c.target_entity = tgt;
    c.bodypart_id = bp; c.damage_amount = amt; c.tick = tick;
    cmd_push(b, &c);
}

/* Apply layer damage (same logic as marble_cmd.h) */
static int apply_damage_layer(const Command* cmd, SparseSet* pool_layers) {
    CLayerStack* stack = (CLayerStack*)mc_sparse_set_get(pool_layers, cmd->target_entity);
    int32_t d;
    if (!stack || stack->layer_count == 0) return -1;
    for (d = 0; d < cmd->damage_amount && stack->layer_count > 0; d++) {
        stack->layers[0].integrity--;
        if (stack->layers[0].integrity <= 0) {
            uint32_t i;
            for (i = 0; i + 1 < stack->layer_count; i++) stack->layers[i] = stack->layers[i+1];
            stack->layer_count--;
        }
    }
    return 0;
}

static int apply_crit_damage(const Command* cmd, SparseSet* pool_layers) {
    CLayerStack* stack = (CLayerStack*)mc_sparse_set_get(pool_layers, cmd->target_entity);
    int32_t d;
    if (!stack) return -1;
    for (d = 0; d < cmd->damage_amount && stack->layer_count > 0; d++) {
        stack->layers[0].integrity--;
        if (stack->layers[0].integrity <= 0) {
            uint32_t i;
            for (i = 0; i + 1 < stack->layer_count; i++) stack->layers[i] = stack->layers[i+1];
            stack->layer_count--;
        }
    }
    return 0;
}

static void cmd_flush(CommandBuffer* b, SparseSet* pool_layers) {
    uint32_t i;
    b->applied = 0; b->rejected = 0;
    for (i = 0; i < b->count; i++) {
        Command* c = &b->commands[i];
        int r = -1;
        switch (c->type) {
            case CMD_DAMAGE_LAYER: r = apply_damage_layer(c, pool_layers); break;
            case CMD_CRIT_DAMAGE:  r = apply_crit_damage(c, pool_layers); break;
            case CMD_PLAY_FEEDBACK: r = 0; break;
            case CMD_MODIFY_STAT:  r = 0; break;
            default: break;
        }
        if (r == 0) b->applied++; else b->rejected++;
    }
    b->count = 0;
}

/* =========================================================================
 * RULE PROCESSOR using generated data
 *
 * This is the key function: it uses GEN_RULES[], gen_evaluate_condition(),
 * gen_check_body_part_integrity(), and CAPABILITY_DEFS[] -- all from
 * marble_gen.h. Zero hand-written interaction code.
 * ========================================================================= */

static InteractResult gen_process_rule(
    const InteractionRequest* req,
    const SparseSet* pool_caps, const SparseSet* pool_anatomy,
    const SparseSet* pool_skills, const SparseSet* pool_tool,
    const SparseSet* pool_bp, const SparseSet* pool_layers,
    const SparseSet* pool_affs,
    EntityID tool_eid,
    CommandBuffer* buf, McRng* rng, uint64_t tick
) {
    const RuleDef* rule = NULL;
    const CCapabilities* caps;
    const CAnatomy* anat;
    const CSkills* skills;
    const CapabilityDef* cdef;
    int32_t skill_level, roll, threshold;
    uint32_t i;

    /* 1. Find matching rule */
    for (i = 0; i < GEN_RULE_COUNT; i++) {
        if (GEN_RULES[i].trigger_verb == req->verb) { rule = &GEN_RULES[i]; break; }
    }
    if (!rule) return INTERACT_FAIL_NO_RULE;

    /* 2. Capability check */
    caps = (const CCapabilities*)mc_sparse_set_get_const(pool_caps, req->actor);
    if (!caps || !(caps->flags & (1u << rule->required_cap))) return INTERACT_FAIL_NO_CAP;

    /* 3. Capability prerequisites */
    cdef = &CAPABILITY_DEFS[rule->required_cap];
    anat = (const CAnatomy*)mc_sparse_set_get_const(pool_anatomy, req->actor);
    if (!anat || (anat->flags & cdef->required_anatomy) != cdef->required_anatomy) return INTERACT_FAIL_ANATOMY;

    /* Body part integrity - uses generated function */
    if (!gen_check_body_part_integrity(cdef->body_part_required, req->actor, pool_bp, pool_layers))
        return INTERACT_FAIL_BODY_PART;

    /* Skill check */
    skills = (const CSkills*)mc_sparse_set_get_const(pool_skills, req->actor);
    if (!skills) return INTERACT_FAIL_SKILL_LOW;
    skill_level = skills->level[cdef->required_skill];
    if (skill_level < cdef->min_skill_level) return INTERACT_FAIL_SKILL_LOW;

    /* 4. Affordance check */
    if (pool_affs) {
        const CAffordances* affs = (const CAffordances*)mc_sparse_set_get_const(pool_affs, req->target);
        if (!affs) return INTERACT_FAIL_NO_AFF;
    }

    /* 5. Conditions - uses generated evaluator */
    for (i = 0; i < rule->cond_count; i++) {
        if (!gen_evaluate_condition(rule->cond_ids[i], req->actor, req->target, pool_tool, pool_layers))
            return INTERACT_FAIL_CONDITION;
    }

    /* 6. d100 roll */
    if (rule->difficulty > 0) {
        roll = mc_rng_d100(rng);
        threshold = rule->difficulty - skill_level;
        if (threshold < 5) threshold = 5;

        if (rule->crit_fail_threshold > 0 && roll < rule->crit_fail_threshold) {
            if (rule->crit_fail_bodypart != BODYPART_NONE) {
                const CBodyParts* bp = (const CBodyParts*)mc_sparse_set_get_const(pool_bp, req->actor);
                if (bp) {
                    EntityID part_eid = bp->part_entity[rule->crit_fail_bodypart];
                    if (part_eid != MC_INVALID_INDEX)
                        cmd_emit_crit(buf, tick, req->actor, part_eid, rule->crit_fail_bodypart, rule->crit_fail_damage);
                }
            }
            return INTERACT_CRIT_FAIL;
        }
        if (roll < threshold) return INTERACT_FAIL_ROLL;
    }

    /* 7. Emit effects */
    for (i = 0; i < rule->effect_count; i++) {
        const RuleEffect* eff = &rule->effects[i];
        EntityID resolved = (eff->target_role == CMD_TARGET_ACTOR) ? req->actor :
                            (eff->target_role == CMD_TARGET_TOOL) ? tool_eid : req->target;
        switch (eff->type) {
            case CMD_DAMAGE_LAYER: cmd_emit_damage(buf, tick, req->actor, resolved, eff->amount); break;
            default: break;
        }
    }
    return INTERACT_SUCCESS;
}

/* =========================================================================
 * TEST FRAMEWORK
 * ========================================================================= */

static int g_tests_run = 0, g_tests_passed = 0, g_tests_failed = 0;

#define TEST_BEGIN(name) do { const char* _tn = (name); int _ok = 1; g_tests_run++;
#define ASSERT(e) do { if(!(e)) { printf("  FAIL: %s (L%d): %s\n",_tn,__LINE__,#e); _ok=0; } } while(0)
#define ASSERT_EQ_I32(a,b) do { int32_t _a=(a),_b=(b); if(_a!=_b) { printf("  FAIL: %s (L%d): %s==%d exp %d\n",_tn,__LINE__,#a,_a,_b); _ok=0; } } while(0)
#define ASSERT_EQ_U32(a,b) do { uint32_t _a=(a),_b=(b); if(_a!=_b) { printf("  FAIL: %s (L%d): %s==%u exp %u\n",_tn,__LINE__,#a,_a,_b); _ok=0; } } while(0)
#define TEST_END() if(_ok) { printf("  PASS: %s\n",_tn); g_tests_passed++; } else g_tests_failed++; } while(0)

/* =========================================================================
 * SCENARIO SETUP
 * ========================================================================= */

static SparseSet gp_caps, gp_affs, gp_anat, gp_skills, gp_tool, gp_bp, gp_layers;

static void setup_scenario(void) {
    CCapabilities caps; CAffordances affs; CAnatomy anat;
    CSkills skills; CTool tool; CBodyParts bp;
    CLayerStack hand_ls;
    uint32_t i;

    mc_sparse_set_init(&gp_caps, sizeof(CCapabilities));
    mc_sparse_set_init(&gp_affs, sizeof(CAffordances));
    mc_sparse_set_init(&gp_anat, sizeof(CAnatomy));
    mc_sparse_set_init(&gp_skills, sizeof(CSkills));
    mc_sparse_set_init(&gp_tool, sizeof(CTool));
    mc_sparse_set_init(&gp_bp, sizeof(CBodyParts));
    mc_sparse_set_init(&gp_layers, sizeof(CLayerStack));

    /* Entity 0: Lumberjack */
    caps.flags = (1u << CAP_CHOP);
    mc_sparse_set_add(&gp_caps, 0, &caps);
    anat.flags = ANAT_ARMS | ANAT_HANDS | ANAT_LEGS;
    mc_sparse_set_add(&gp_anat, 0, &anat);
    memset(&skills, 0, sizeof(skills));
    skills.level[SKILL_WOODCUTTING] = 60;
    mc_sparse_set_add(&gp_skills, 0, &skills);
    tool.material = MAT_IRON;
    mc_sparse_set_add(&gp_tool, 0, &tool);
    for (i = 0; i < MAX_BODY_PARTS; i++) bp.part_entity[i] = MC_INVALID_INDEX;
    bp.part_entity[BODYPART_RIGHT_HAND] = 1;
    mc_sparse_set_add(&gp_bp, 0, &bp);

    /* Entity 1: Right Hand (from generated layer template) */
    layer_template_HumanHand(&hand_ls);
    mc_sparse_set_add(&gp_layers, 1, &hand_ls);

    /* Entity 2: Oak Tree (from generated layer template) */
    {
        CLayerStack tree_ls;
        layer_template_OakTree(&tree_ls);
        mc_sparse_set_add(&gp_layers, 2, &tree_ls);
    }
    affs.flags = (1u << AFF_CHOPPABLE);
    mc_sparse_set_add(&gp_affs, 2, &affs);
}

/* =========================================================================
 * TESTS
 * ========================================================================= */

static void test_gen_enums_match(void) {
    TEST_BEGIN("gen: material enums and hardness match .marble source");
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_WOOD], 30);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_IRON], 80);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_FLESH], 10);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_BARK], 25);
    ASSERT_EQ_I32(MATERIAL_HARDNESS[MAT_BONE], 40);
    ASSERT_EQ_U32(MAT_COUNT, 6);
    TEST_END();
}

static void test_gen_capability_defs(void) {
    TEST_BEGIN("gen: capability defs match .marble source");
    ASSERT_EQ_U32(CAPABILITY_DEFS[CAP_CHOP].required_anatomy, ANAT_ARMS | ANAT_HANDS);
    ASSERT_EQ_I32(CAPABILITY_DEFS[CAP_CHOP].required_skill, SKILL_WOODCUTTING);
    ASSERT_EQ_I32(CAPABILITY_DEFS[CAP_CHOP].min_skill_level, 1);
    ASSERT_EQ_I32(CAPABILITY_DEFS[CAP_CHOP].body_part_required, BODYPART_RIGHT_HAND);
    TEST_END();
}

static void test_gen_affordance_defs(void) {
    TEST_BEGIN("gen: affordance defs match .marble source");
    ASSERT_EQ_I32(AFFORDANCE_DEFS[AFF_CHOPPABLE].required_cap, CAP_CHOP);
    ASSERT_EQ_I32(AFFORDANCE_DEFS[AFF_CHOPPABLE].difficulty, 40);
    ASSERT_EQ_I32(AFFORDANCE_DEFS[AFF_CHOPPABLE].crit_fail_threshold, 15);
    ASSERT_EQ_I32(AFFORDANCE_DEFS[AFF_CHOPPABLE].crit_fail_damage, 2);
    TEST_END();
}

static void test_gen_rule_data(void) {
    TEST_BEGIN("gen: GEN_RULES[0] matches Rule_Chop from .marble");
    ASSERT_EQ_U32(GEN_RULE_COUNT, 1);
    ASSERT_EQ_U32(GEN_RULES[0].trigger_verb, VERB_CHOP);
    ASSERT_EQ_U32(GEN_RULES[0].required_cap, CAP_CHOP);
    ASSERT_EQ_U32(GEN_RULES[0].cond_count, 1);
    ASSERT_EQ_U32(GEN_RULES[0].cond_ids[0], COND_TOOL_HARDER_THAN_LAYER);
    ASSERT_EQ_I32(GEN_RULES[0].difficulty, 40);
    ASSERT_EQ_I32(GEN_RULES[0].crit_fail_threshold, 15);
    ASSERT_EQ_U32(GEN_RULES[0].crit_fail_bodypart, BODYPART_RIGHT_HAND);
    ASSERT_EQ_I32(GEN_RULES[0].crit_fail_damage, 2);
    ASSERT_EQ_U32(GEN_RULES[0].effect_count, 1);
    ASSERT_EQ_I32(GEN_RULES[0].effects[0].type, CMD_DAMAGE_LAYER);
    ASSERT_EQ_I32(GEN_RULES[0].effects[0].target_role, CMD_TARGET_TARGET);
    ASSERT_EQ_I32(GEN_RULES[0].effects[0].amount, 1);
    TEST_END();
}

static void test_gen_layer_templates(void) {
    TEST_BEGIN("gen: layer templates produce correct stacks");
    {
        CLayerStack ls;
        layer_template_OakTree(&ls);
        ASSERT_EQ_U32(ls.layer_count, 2);
        ASSERT_EQ_I32(ls.layers[0].material, MAT_BARK);
        ASSERT_EQ_I32(ls.layers[0].integrity, 3);
        ASSERT_EQ_I32(ls.layers[1].material, MAT_WOOD);
        ASSERT_EQ_I32(ls.layers[1].integrity, 10);

        layer_template_HumanHand(&ls);
        ASSERT_EQ_U32(ls.layer_count, 2);
        ASSERT_EQ_I32(ls.layers[0].material, MAT_FLESH);
        ASSERT_EQ_I32(ls.layers[0].integrity, 1);
    }
    TEST_END();
}

static void test_gen_condition_eval(void) {
    TEST_BEGIN("gen: gen_evaluate_condition works with generated types");
    setup_scenario();
    /* Iron (80) > Bark (25) = pass */
    ASSERT(gen_evaluate_condition(COND_TOOL_HARDER_THAN_LAYER, 0, 2, &gp_tool, &gp_layers));
    TEST_END();
}

static void test_gen_body_part_check(void) {
    TEST_BEGIN("gen: gen_check_body_part_integrity works");
    setup_scenario();
    ASSERT(gen_check_body_part_integrity(BODYPART_RIGHT_HAND, 0, &gp_bp, &gp_layers));
    ASSERT(gen_check_body_part_integrity(BODYPART_NONE, 0, &gp_bp, &gp_layers));
    TEST_END();
}

static void test_gen_rule_success(void) {
    TEST_BEGIN("gen: rule processor success emits DAMAGE_LAYER cmd");
    {
        CommandBuffer buf;
        InteractionRequest req;
        InteractResult result;
        McRng rng;
        uint32_t seed = 100;

        setup_scenario();
        cmd_init(&buf);
        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Find non-crit seed */
        while (seed < 10000) {
            McRng t; mc_rng_seed(&t, seed);
            if (mc_rng_d100(&t) >= 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        result = gen_process_rule(&req, &gp_caps, &gp_anat, &gp_skills, &gp_tool,
                                  &gp_bp, &gp_layers, &gp_affs, MC_INVALID_INDEX,
                                  &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_SUCCESS);
        ASSERT_EQ_U32(buf.count, 1);
        ASSERT_EQ_I32(buf.commands[0].type, CMD_DAMAGE_LAYER);
        ASSERT_EQ_U32(buf.commands[0].target_entity, 2);

        /* Pool still untouched (read-only invariant) */
        {
            const CLayerStack* tree = (const CLayerStack*)mc_sparse_set_get_const(&gp_layers, 2);
            ASSERT_EQ_I32(tree->layers[0].integrity, 3);
        }

        /* Flush applies damage */
        cmd_flush(&buf, &gp_layers);
        {
            const CLayerStack* tree = (const CLayerStack*)mc_sparse_set_get_const(&gp_layers, 2);
            ASSERT_EQ_I32(tree->layers[0].integrity, 2);
        }
    }
    TEST_END();
}

static void test_gen_rule_crit_fail(void) {
    TEST_BEGIN("gen: rule processor crit fail emits CRIT_DAMAGE cmd");
    {
        CommandBuffer buf;
        InteractionRequest req;
        InteractResult result;
        McRng rng;
        uint32_t seed = 0;

        setup_scenario();
        cmd_init(&buf);
        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Find crit fail seed (roll < 15) */
        while (seed < 100000) {
            McRng t; mc_rng_seed(&t, seed);
            if (mc_rng_d100(&t) < 15) break;
            seed++;
        }
        mc_rng_seed(&rng, seed);

        result = gen_process_rule(&req, &gp_caps, &gp_anat, &gp_skills, &gp_tool,
                                  &gp_bp, &gp_layers, &gp_affs, MC_INVALID_INDEX,
                                  &buf, &rng, 0);

        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);
        ASSERT_EQ_U32(buf.count, 1);
        ASSERT_EQ_I32(buf.commands[0].type, CMD_CRIT_DAMAGE);
        ASSERT_EQ_I32(buf.commands[0].damage_amount, 2);
    }
    TEST_END();
}

static void test_gen_cascading_failure(void) {
    TEST_BEGIN("gen: crit -> flush -> hand destroyed -> next chop fails body part");
    {
        CommandBuffer buf;
        InteractionRequest req;
        InteractResult result;
        McRng rng;
        uint32_t seed = 0;

        setup_scenario();
        req.actor = 0; req.target = 2; req.verb = VERB_CHOP;

        /* Crit fail -> hand destroyed */
        while (seed < 100000) {
            McRng t; mc_rng_seed(&t, seed);
            if (mc_rng_d100(&t) < 15) break;
            seed++;
        }
        cmd_init(&buf);
        mc_rng_seed(&rng, seed);
        result = gen_process_rule(&req, &gp_caps, &gp_anat, &gp_skills, &gp_tool,
                                  &gp_bp, &gp_layers, &gp_affs, MC_INVALID_INDEX,
                                  &buf, &rng, 0);
        ASSERT_EQ_I32(result, INTERACT_CRIT_FAIL);
        cmd_flush(&buf, &gp_layers);

        /* Verify hand destroyed */
        {
            const CLayerStack* hand = (const CLayerStack*)mc_sparse_set_get_const(&gp_layers, 1);
            ASSERT_EQ_U32(hand->layer_count, 0);
        }

        /* Try again -> body part check fails */
        cmd_init(&buf);
        mc_rng_seed(&rng, 99999);
        result = gen_process_rule(&req, &gp_caps, &gp_anat, &gp_skills, &gp_tool,
                                  &gp_bp, &gp_layers, &gp_affs, MC_INVALID_INDEX,
                                  &buf, &rng, 1);
        ASSERT_EQ_I32(result, INTERACT_FAIL_BODY_PART);
        ASSERT_EQ_U32(buf.count, 0);
    }
    TEST_END();
}

static void test_gen_deterministic_replay(void) {
    TEST_BEGIN("gen: same seed produces identical results across runs");
    {
        uint32_t seed = 500;
        int run;
        InteractResult results[2];

        for (run = 0; run < 2; run++) {
            CommandBuffer buf;
            InteractionRequest req;
            McRng rng;
            setup_scenario();
            cmd_init(&buf);
            mc_rng_seed(&rng, seed);
            req.actor = 0; req.target = 2; req.verb = VERB_CHOP;
            results[run] = gen_process_rule(&req, &gp_caps, &gp_anat, &gp_skills, &gp_tool,
                                            &gp_bp, &gp_layers, &gp_affs, MC_INVALID_INDEX,
                                            &buf, &rng, 0);
        }
        ASSERT_EQ_I32(results[0], results[1]);
    }
    TEST_END();
}

/* =========================================================================
 * RUN ALL
 * ========================================================================= */

int main(void) {
    printf("MarbleEngine Generated Code Tests\n");
    printf("==================================\n");
    printf("(All types/data from marble_gen.h -- zero hand-written interact code)\n\n");

    printf("[Generated Enums & Tables]\n");
    test_gen_enums_match();
    test_gen_capability_defs();
    test_gen_affordance_defs();
    test_gen_rule_data();
    test_gen_layer_templates();

    printf("\n[Generated Functions]\n");
    test_gen_condition_eval();
    test_gen_body_part_check();

    printf("\n[Full Pipeline: .marble -> Rule -> Cmd -> Flush]\n");
    test_gen_rule_success();
    test_gen_rule_crit_fail();
    test_gen_cascading_failure();
    test_gen_deterministic_replay();

    printf("\n==================================\n");
    printf("TOTAL: %d  PASSED: %d  FAILED: %d\n", g_tests_run, g_tests_passed, g_tests_failed);
    if (g_tests_failed == 0) printf("ALL TESTS PASSED\n");
    else printf("*** FAILURES DETECTED ***\n");
    return (g_tests_failed > 0) ? 1 : 0;
}