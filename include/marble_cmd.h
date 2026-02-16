/*
 * marble_cmd.h -- Command Buffer + Rule Engine (Phase 0.3)
 *
 * ARCHITECTURE:
 *   During a tick, all systems READ component pools but NEVER WRITE.
 *   Any intended mutation is pushed as a Command into the CommandBuffer.
 *   At the tick boundary, commands are validated and applied atomically.
 *
 *   This eliminates:
 *   - Order-dependent bugs (system A writes, system B reads dirty state)
 *   - Double-mutation bugs (two systems modify the same entity)
 *   - Observation-during-mutation bugs (iterator sees half-applied state)
 *
 * COMMAND TYPES:
 *   CMD_DAMAGE_LAYER     -- reduce outermost layer integrity (peel on 0)
 *   CMD_MODIFY_STAT      -- add/subtract a stat on an entity
 *   CMD_TRANSFORM_ENTITY -- replace entity's definition (item -> new item)
 *   CMD_MOVE_ENTITY      -- change entity location/container
 *   CMD_REMOVE_ENTITY    -- destroy entity entirely
 *   CMD_PLAY_FEEDBACK    -- emit message (no state change, logged only)
 *
 * RULE SYSTEM:
 *   A Rule is a higher-level interaction definition:
 *     TRIGGER verb  REQ capability
 *     COND condition_id
 *     EFFECT effect_type  param1  param2 ...
 *     EFFECT effect_type  param1  param2 ...
 *
 *   Rules replace the old single-effect AffordanceDef model.
 *   A single interaction can now produce multiple commands.
 *
 * CONSTRAINTS: Same as marble_core.h (no malloc, no fn ptrs, no recursion)
 */

#ifndef MARBLE_CMD_H
#define MARBLE_CMD_H

#include "marble_core.h"
#include "marble_interact.h"  /* CapabilityDef, conditions, body part checks */

/* =========================================================================
 * SECTION 1: COMMAND TYPES
 * ========================================================================= */

typedef enum {
    CMD_NONE             = 0,
    CMD_DAMAGE_LAYER     = 1,  /* target, amount */
    CMD_MODIFY_STAT      = 2,  /* target, stat_id, amount, operation */
    CMD_TRANSFORM_ENTITY = 3,  /* target, new_def_id */
    CMD_MOVE_ENTITY      = 4,  /* target, destination */
    CMD_REMOVE_ENTITY    = 5,  /* target */
    CMD_PLAY_FEEDBACK    = 6,  /* message_id (no state change) */
    CMD_CRIT_DAMAGE      = 7,  /* actor, bodypart, amount (self-damage) */
    CMD_COUNT
} CommandType;

static const char* CMD_TYPE_NAMES[CMD_COUNT] = {
    "NONE", "DAMAGE_LAYER", "MODIFY_STAT", "TRANSFORM_ENTITY",
    "MOVE_ENTITY", "REMOVE_ENTITY", "PLAY_FEEDBACK", "CRIT_DAMAGE"
};

typedef enum {
    OP_ADD      = 0,
    OP_SUBTRACT = 1,
    OP_SET      = 2,
    OP_COUNT
} StatOperation;

/* --- Target Resolution ---
 * Commands reference entities by role, resolved at emit time. */
typedef enum {
    CMD_TARGET_NONE   = 0,
    CMD_TARGET_ACTOR  = 1,  /* the entity performing the action */
    CMD_TARGET_TARGET = 2,  /* the entity being acted upon */
    CMD_TARGET_TOOL   = 3,  /* the equipped tool/item */
    CMD_TARGET_ENV    = 4,  /* environment entity (tree, rock, etc.) */
    CMD_TARGET_COUNT
} CommandTargetRole;

/* =========================================================================
 * SECTION 2: COMMAND STRUCT
 *
 * Fixed-size, union-free. All fields present, unused ones are 0.
 * This wastes a few bytes per command but avoids unions and keeps
 * the struct trivially copyable.
 * ========================================================================= */

typedef struct {
    CommandType type;

    EntityID    source_entity;  /* who issued this command (for audit) */
    EntityID    target_entity;  /* resolved entity to mutate */

    /* CMD_DAMAGE_LAYER / CMD_CRIT_DAMAGE */
    int32_t     damage_amount;
    uint32_t    bodypart_id;    /* for CMD_CRIT_DAMAGE: which body part */

    /* CMD_MODIFY_STAT */
    uint32_t    stat_id;
    int32_t     stat_amount;
    StatOperation stat_op;

    /* CMD_TRANSFORM_ENTITY */
    uint32_t    new_def_id;     /* item definition ID to transform into */

    /* CMD_MOVE_ENTITY */
    uint32_t    destination;    /* destination enum or container entity */

    /* CMD_PLAY_FEEDBACK */
    uint32_t    message_id;     /* index into message table */

    /* Tick this command was emitted (for ordering/debug) */
    uint64_t    tick;
} Command;

/* =========================================================================
 * SECTION 3: COMMAND BUFFER
 *
 * Fixed-size ring buffer. Commands are pushed during system processing
 * and flushed (validated + applied) at the tick boundary.
 *
 * If the buffer fills up, excess commands are dropped with a warning.
 * In a real game this would trigger backpressure or priority shedding.
 * ========================================================================= */

#define MAX_COMMANDS 256

typedef struct {
    Command  commands[MAX_COMMANDS];
    uint32_t count;
    uint32_t rejected;  /* count of commands that failed validation */
    uint32_t applied;   /* count of commands successfully applied */
} CommandBuffer;

static void mc_cmd_buf_init(CommandBuffer* buf) {
    buf->count    = 0;
    buf->rejected = 0;
    buf->applied  = 0;
}

/* Push a command into the buffer. Returns 0 on success, -1 if full. */
static int mc_cmd_push(CommandBuffer* buf, const Command* cmd) {
    if (buf->count >= MAX_COMMANDS) {
        printf("  [CMD] WARNING: command buffer full, dropping %s\n",
               CMD_TYPE_NAMES[cmd->type]);
        return -1;
    }
    buf->commands[buf->count] = *cmd;
    buf->count++;
    return 0;
}

/* =========================================================================
 * SECTION 4: COMMAND EMITTERS (convenience functions)
 *
 * Systems call these instead of mutating pools directly.
 * Each emitter builds a Command struct and pushes it.
 * ========================================================================= */

static void mc_emit_damage_layer(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, EntityID target, int32_t amount
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_DAMAGE_LAYER;
    cmd.source_entity = source;
    cmd.target_entity = target;
    cmd.damage_amount = amount;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

static void mc_emit_crit_damage(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, EntityID target_body_part_entity,
    uint32_t bodypart_id, int32_t amount
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_CRIT_DAMAGE;
    cmd.source_entity = source;
    cmd.target_entity = target_body_part_entity;
    cmd.bodypart_id   = bodypart_id;
    cmd.damage_amount = amount;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

static void mc_emit_modify_stat(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, EntityID target,
    uint32_t stat_id, int32_t amount, StatOperation op
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_MODIFY_STAT;
    cmd.source_entity = source;
    cmd.target_entity = target;
    cmd.stat_id       = stat_id;
    cmd.stat_amount   = amount;
    cmd.stat_op       = op;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

static void mc_emit_transform(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, EntityID target,
    uint32_t new_def_id
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_TRANSFORM_ENTITY;
    cmd.source_entity = source;
    cmd.target_entity = target;
    cmd.new_def_id    = new_def_id;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

static void mc_emit_remove(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, EntityID target
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_REMOVE_ENTITY;
    cmd.source_entity = source;
    cmd.target_entity = target;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

static void mc_emit_feedback(
    CommandBuffer* buf, uint64_t tick,
    EntityID source, uint32_t message_id
) {
    Command cmd;
    memset(&cmd, 0, sizeof(cmd));
    cmd.type          = CMD_PLAY_FEEDBACK;
    cmd.source_entity = source;
    cmd.message_id    = message_id;
    cmd.tick          = tick;
    mc_cmd_push(buf, &cmd);
}

/* =========================================================================
 * SECTION 5: COMMAND APPLICATORS
 *
 * These are the ONLY functions that mutate component pools.
 * They are called ONLY during the flush phase at tick boundary.
 * ========================================================================= */

/* Apply layer damage to an entity's LayerStack.
 * Same logic as old apply_effect(DAMAGE_LAYER) but routed through cmd buf. */
static int mc_apply_damage_layer(
    const Command* cmd, SparseSet* pool_layers
) {
    CLayerStack* stack;
    int32_t d;

    stack = (CLayerStack*)mc_sparse_set_get(pool_layers, cmd->target_entity);
    if (stack == NULL) return -1;
    if (stack->layer_count == 0) return -1;

    for (d = 0; d < cmd->damage_amount && stack->layer_count > 0; d++) {
        stack->layers[0].integrity--;

        if (stack->layers[0].integrity <= 0) {
            uint32_t i;
            printf("    >> Layer DESTROYED: %s peeled on eid %u <<\n",
                   MATERIAL_NAMES[stack->layers[0].material],
                   cmd->target_entity);
            for (i = 0; i + 1 < stack->layer_count; i++) {
                stack->layers[i] = stack->layers[i + 1];
            }
            stack->layer_count--;
        }
    }
    return 0;
}

/* Apply critical self-damage to a body part entity's LayerStack. */
static int mc_apply_crit_damage(
    const Command* cmd, SparseSet* pool_layers
) {
    CLayerStack* stack;
    int32_t d;

    stack = (CLayerStack*)mc_sparse_set_get(pool_layers, cmd->target_entity);
    if (stack == NULL) return -1;

    printf("    >> CRIT FAIL! Entity %u damages own body part (eid %u)! <<\n",
           cmd->source_entity, cmd->target_entity);

    for (d = 0; d < cmd->damage_amount && stack->layer_count > 0; d++) {
        stack->layers[0].integrity--;
        printf("    >> %s integrity -> %d/%d <<\n",
               MATERIAL_NAMES[stack->layers[0].material],
               stack->layers[0].integrity,
               stack->layers[0].max_integrity);

        if (stack->layers[0].integrity <= 0) {
            uint32_t i;
            printf("    >> %s layer DESTROYED <<\n",
                   MATERIAL_NAMES[stack->layers[0].material]);
            for (i = 0; i + 1 < stack->layer_count; i++) {
                stack->layers[i] = stack->layers[i + 1];
            }
            stack->layer_count--;

            if (stack->layer_count == 0) {
                printf("    >> Body part eid %u FULLY DESTROYED -- fine motor LOST <<\n",
                       cmd->target_entity);
            }
        }
    }
    return 0;
}

/* Apply a transform: changes an entity's definition ID.
 * In Phase 0.3 this stores the new def in a CItemDef component.
 * The actual item data loading happens via the item definition table. */
typedef struct {
    uint32_t def_id;   /* which item definition this entity currently is */
} CItemDef;

static int mc_apply_transform(
    const Command* cmd, SparseSet* pool_item_defs
) {
    CItemDef* def;
    def = (CItemDef*)mc_sparse_set_get(pool_item_defs, cmd->target_entity);
    if (def == NULL) {
        printf("    >> TRANSFORM: eid %u has no CItemDef, cannot transform <<\n",
               cmd->target_entity);
        return -1;
    }
    printf("    >> TRANSFORM: eid %u def %u -> %u <<\n",
           cmd->target_entity, def->def_id, cmd->new_def_id);
    def->def_id = cmd->new_def_id;
    return 0;
}

/* =========================================================================
 * SECTION 6: COMMAND BUFFER FLUSH
 *
 * Called ONCE at the tick boundary. Iterates all queued commands,
 * validates each, and applies if valid. Invalid commands are rejected
 * with a log entry.
 *
 * pool_ptrs is a struct of all pool pointers so the flush can route
 * each command type to the right pool.
 * ========================================================================= */

typedef struct {
    SparseSet* layers;
    SparseSet* item_defs;
    /* Add more pool pointers as needed */
} PoolPtrs;

static void mc_cmd_flush(CommandBuffer* buf, PoolPtrs* pools) {
    uint32_t i;
    buf->applied  = 0;
    buf->rejected = 0;

    for (i = 0; i < buf->count; i++) {
        Command* cmd = &buf->commands[i];
        int result = -1;

        switch (cmd->type) {
            case CMD_DAMAGE_LAYER:
                result = mc_apply_damage_layer(cmd, pools->layers);
                break;

            case CMD_CRIT_DAMAGE:
                result = mc_apply_crit_damage(cmd, pools->layers);
                break;

            case CMD_MODIFY_STAT:
                /* Phase 0.3: stat modification via generic path.
                 * For now, log only. Full stat system in Phase 0.4. */
                printf("    >> MODIFY_STAT: eid %u stat %u %s %d <<\n",
                       cmd->target_entity, cmd->stat_id,
                       cmd->stat_op == OP_ADD ? "+=" :
                       cmd->stat_op == OP_SUBTRACT ? "-=" : "=",
                       cmd->stat_amount);
                result = 0;
                break;

            case CMD_TRANSFORM_ENTITY:
                if (pools->item_defs) {
                    result = mc_apply_transform(cmd, pools->item_defs);
                } else {
                    printf("    >> TRANSFORM: eid %u -> def %u (no pool, logged only) <<\n",
                           cmd->target_entity, cmd->new_def_id);
                    result = 0;
                }
                break;

            case CMD_REMOVE_ENTITY:
                printf("    >> REMOVE: eid %u <<\n", cmd->target_entity);
                /* Phase 0.3: remove from all pools would go here.
                 * For now, log only. */
                result = 0;
                break;

            case CMD_PLAY_FEEDBACK:
                printf("    >> FEEDBACK: msg_id %u from eid %u <<\n",
                       cmd->message_id, cmd->source_entity);
                result = 0;
                break;

            default:
                printf("    >> UNKNOWN CMD TYPE %d <<\n", cmd->type);
                break;
        }

        if (result == 0) {
            buf->applied++;
        } else {
            buf->rejected++;
            printf("    >> CMD REJECTED: %s on eid %u <<\n",
                   CMD_TYPE_NAMES[cmd->type], cmd->target_entity);
        }
    }

    if (buf->count > 0) {
        printf("  [CMD] Flush: %u applied, %u rejected (of %u total)\n",
               buf->applied, buf->rejected, buf->count);
    }

    /* Reset for next tick */
    buf->count = 0;
}

/* =========================================================================
 * SECTION 7: RULE SYSTEM
 *
 * A Rule defines a complete interaction as a trigger + conditions + effects.
 * Rules are the .marble-authored replacement for the old AffordanceDef model.
 *
 * RULE Rule_Chop
 *   TRIGGER Chop REQ Chop
 *   COND tool_harder_than_layer
 *   EFFECT DAMAGE_LAYER target:target amount:1
 *   EFFECT MODIFY_STAT target:actor stat:stamina op:subtract amount:8
 *
 * At runtime, the rule processor:
 *   1. Matches verb to rule via TRIGGER
 *   2. Checks REQ (capability)
 *   3. Evaluates all CONDs
 *   4. On success: emits all EFFECTs as commands into the buffer
 * ========================================================================= */

#define MAX_RULE_EFFECTS 8
#define MAX_RULE_CONDS   4
#define MAX_RULES        64

typedef struct {
    CommandType      type;           /* what kind of command to emit */
    CommandTargetRole target_role;   /* who this targets (actor/target/tool) */
    uint32_t         stat_id;       /* for MODIFY_STAT */
    int32_t          amount;        /* for DAMAGE/MODIFY */
    StatOperation    stat_op;       /* for MODIFY_STAT */
    uint32_t         new_def_id;    /* for TRANSFORM */
    uint32_t         message_id;    /* for FEEDBACK */
    uint32_t         bodypart_id;   /* for CRIT_DAMAGE */
} RuleEffect;

typedef struct {
    uint32_t     rule_id;
    uint32_t     trigger_verb;       /* VerbID */
    uint32_t     required_cap;       /* CapabilityID */

    uint32_t     cond_ids[MAX_RULE_CONDS];
    uint32_t     cond_count;

    /* d100 roll parameters */
    int32_t      difficulty;          /* base difficulty for d100 */
    int32_t      crit_fail_threshold; /* roll below this = crit fail */
    uint32_t     crit_fail_bodypart;  /* BodyPartID for self-damage */
    int32_t      crit_fail_damage;    /* amount of crit self-damage */

    RuleEffect   effects[MAX_RULE_EFFECTS];
    uint32_t     effect_count;
} RuleDef;

/* =========================================================================
 * SECTION 8: RULE PROCESSOR
 *
 * Given an interaction request, finds the matching rule, validates
 * conditions, rolls d100, and emits commands to the buffer.
 *
 * Returns the interaction result code (same enum as before).
 * ========================================================================= */

/* Resolve a target role to a concrete EntityID.
 * In a full system, "tool" would come from the actor's equipment slot. */
static EntityID resolve_target(
    CommandTargetRole role,
    EntityID actor, EntityID target, EntityID tool_eid
) {
    switch (role) {
        case CMD_TARGET_ACTOR:  return actor;
        case CMD_TARGET_TARGET: return target;
        case CMD_TARGET_TOOL:   return tool_eid;
        default:                return target;
    }
}

/* InteractResult enum is defined in marble_interact.h.
 * We extend it with one additional value for rule matching. */
#define INTERACT_FAIL_NO_RULE 10

/* Extended result names (supersedes the array in marble_interact.h) */
static const char* CMD_RESULT_NAMES[] = {
    "SUCCESS",
    "FAIL:NO_VERB",
    "FAIL:NO_CAPABILITY",
    "FAIL:ANATOMY",
    "FAIL:BODY_PART_DAMAGED",
    "FAIL:SKILL_TOO_LOW",
    "FAIL:NO_AFFORDANCE",
    "FAIL:CONDITION",
    "FAIL:ROLL",
    "CRIT_FAIL:SELF_DAMAGE",
    "FAIL:NO_RULE"
};

/* The rule processor: finds rule, validates, emits commands.
 *
 * NOTE: All pool parameters are const — the processor NEVER mutates them.
 * All mutations go through the command buffer.
 *
 * tool_eid: the entity ID of the actor's equipped tool (for TRANSFORM etc.)
 *           MC_INVALID_INDEX if no tool equipped. */
static InteractResult process_rule(
    const InteractionRequest* req,
    const RuleDef*    rules,
    uint32_t          rule_count,
    const SparseSet*  pool_caps,
    const SparseSet*  pool_anatomy,
    const SparseSet*  pool_skills,
    const SparseSet*  pool_tool,
    const SparseSet*  pool_body_parts,
    const SparseSet*  pool_layers,
    const SparseSet*  pool_affs,
    EntityID          tool_eid,
    CommandBuffer*    cmd_buf,
    McRng*            rng,
    uint64_t          tick
) {
    const RuleDef* rule = NULL;
    const CCapabilities* actor_caps;
    const CAnatomy* actor_anat;
    const CSkills* actor_skills;
    const CapabilityDef* cdef;
    int32_t skill_level, roll, threshold;
    uint32_t i;

    /* 1. Find matching rule by verb */
    for (i = 0; i < rule_count; i++) {
        if (rules[i].trigger_verb == req->verb) {
            rule = &rules[i];
            break;
        }
    }
    if (rule == NULL) return INTERACT_FAIL_NO_RULE;

    /* 2. Check actor has required capability */
    actor_caps = (const CCapabilities*)mc_sparse_set_get_const(pool_caps, req->actor);
    if (actor_caps == NULL) return INTERACT_FAIL_NO_CAP;
    if (!(actor_caps->flags & (1u << rule->required_cap))) return INTERACT_FAIL_NO_CAP;

    /* 3. Check capability prerequisites */
    cdef = &CAPABILITY_DEFS[rule->required_cap];

    /* 3a. Anatomy */
    actor_anat = (const CAnatomy*)mc_sparse_set_get_const(pool_anatomy, req->actor);
    if (actor_anat == NULL) return INTERACT_FAIL_ANATOMY;
    if ((actor_anat->flags & cdef->required_anatomy) != cdef->required_anatomy)
        return INTERACT_FAIL_ANATOMY;

    /* 3b. Body part integrity */
    if (!check_body_part_integrity(cdef->body_part_required,
                                    req->actor, pool_body_parts, pool_layers))
        return INTERACT_FAIL_BODY_PART;

    /* 3c. Skill level */
    actor_skills = (const CSkills*)mc_sparse_set_get_const(pool_skills, req->actor);
    if (actor_skills == NULL) return INTERACT_FAIL_SKILL_LOW;
    skill_level = actor_skills->level[cdef->required_skill];
    if (skill_level < cdef->min_skill_level) return INTERACT_FAIL_SKILL_LOW;

    /* 4. Check target has affordance (if pool provided) */
    if (pool_affs != NULL) {
        const CAffordances* target_affs;
        target_affs = (const CAffordances*)mc_sparse_set_get_const(pool_affs, req->target);
        if (target_affs == NULL) return INTERACT_FAIL_NO_AFF;
        /* Affordance check via rule's trigger verb mapping */
    }

    /* 5. Evaluate conditions */
    for (i = 0; i < rule->cond_count; i++) {
        if (!evaluate_condition(rule->cond_ids[i], req->actor, req->target,
                                pool_tool, pool_layers))
            return INTERACT_FAIL_CONDITION;
    }

    /* 6. Roll d100 */
    if (rule->difficulty > 0) {
        roll = mc_rng_d100(rng);
        threshold = rule->difficulty - skill_level;
        if (threshold < 5) threshold = 5;

        /* 6a. Critical failure */
        if (rule->crit_fail_threshold > 0 && roll < rule->crit_fail_threshold) {
            /* Emit crit damage command -- NOT direct mutation */
            if (rule->crit_fail_bodypart != BODYPART_NONE) {
                const CBodyParts* bp = (const CBodyParts*)mc_sparse_set_get_const(
                    pool_body_parts, req->actor);
                if (bp != NULL) {
                    EntityID part_eid = bp->part_entity[rule->crit_fail_bodypart];
                    if (part_eid != MC_INVALID_INDEX) {
                        mc_emit_crit_damage(cmd_buf, tick, req->actor, part_eid,
                                            rule->crit_fail_bodypart,
                                            rule->crit_fail_damage);
                    }
                }
            }
            return INTERACT_CRIT_FAIL;
        }

        /* 6b. Normal failure */
        if (roll < threshold) {
            return INTERACT_FAIL_ROLL;
        }
    }

    /* 7. SUCCESS -- emit all rule effects as commands */
    for (i = 0; i < rule->effect_count; i++) {
        const RuleEffect* eff = &rule->effects[i];
        EntityID resolved = resolve_target(eff->target_role, req->actor, req->target, tool_eid);

        switch (eff->type) {
            case CMD_DAMAGE_LAYER:
                mc_emit_damage_layer(cmd_buf, tick, req->actor, resolved, eff->amount);
                break;

            case CMD_MODIFY_STAT:
                mc_emit_modify_stat(cmd_buf, tick, req->actor, resolved,
                                    eff->stat_id, eff->amount, eff->stat_op);
                break;

            case CMD_TRANSFORM_ENTITY:
                mc_emit_transform(cmd_buf, tick, req->actor, resolved, eff->new_def_id);
                break;

            case CMD_REMOVE_ENTITY:
                mc_emit_remove(cmd_buf, tick, req->actor, resolved);
                break;

            case CMD_PLAY_FEEDBACK:
                mc_emit_feedback(cmd_buf, tick, req->actor, eff->message_id);
                break;

            default:
                break;
        }
    }

    return INTERACT_SUCCESS;
}

#endif /* MARBLE_CMD_H */