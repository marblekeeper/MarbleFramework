/*
 * marble_interact.h — Affordance/Capability Interaction Engine (Phase 0.1b)
 *
 * ADDITIONS OVER v1:
 *   - Degrees of failure: CRIT_FAIL when d100 roll is critically low
 *   - Self-damage effect: crit fail damages the ACTOR's hand layers
 *   - Fine Motor capability: required for CHOP, gated on hand integrity
 *   - Cascading failure: hand destroyed -> fine motor check fails ->
 *     CHOP becomes impossible until hand is healed
 *
 * DESIGN DECISION — DECLARATIVE FINE MOTOR:
 *   Fine motor is NOT a flag that gets imperatively cleared. Instead,
 *   the CapabilityDef for CAP_CHOP includes a body_part_condition that
 *   the processor evaluates every tick: "does the actor's hand layer
 *   stack have integrity > 0?" If the hand is destroyed, the condition
 *   fails and the capability is effectively lost — without ever mutating
 *   the capability bitfield. This is the MarbleScript-native pattern:
 *   the translation table defines the rule, the processor evaluates it.
 *
 * CONSTRAINTS: Same as marble_core.h (no malloc, no fn ptrs, no recursion)
 */

#ifndef MARBLE_INTERACT_H
#define MARBLE_INTERACT_H

#include "marble_core.h"

/* =========================================================================
 * SECTION 1: MATERIAL & LAYER SYSTEM
 * ========================================================================= */

#define MAX_LAYERS 4

typedef enum {
    MAT_NONE  = 0,
    MAT_WOOD  = 1,
    MAT_STONE = 2,
    MAT_IRON  = 3,
    MAT_FLESH = 4,
    MAT_BARK  = 5,
    MAT_BONE  = 6,
    MAT_COUNT
} MaterialID;

static const char* MATERIAL_NAMES[MAT_COUNT] = {
    "None", "Wood", "Stone", "Iron", "Flesh", "Bark", "Bone"
};

/* Hardness values (0-100 scale) */
static const int32_t MATERIAL_HARDNESS[MAT_COUNT] = {
    /*NONE*/ 0,
    /*WOOD*/ 30,
    /*STONE*/65,
    /*IRON*/ 80,
    /*FLESH*/10,
    /*BARK*/ 25,
    /*BONE*/ 40
};

typedef struct {
    MaterialID material;
    int32_t    integrity;
    int32_t    max_integrity;
} Layer;

typedef struct {
    Layer    layers[MAX_LAYERS];
    uint32_t layer_count;
} CLayerStack;

/* =========================================================================
 * SECTION 2: BODY PARTS
 *
 * An entity can have multiple named body part slots, each referencing
 * a LayerStack entity. This allows the interaction processor to check
 * "does the actor's RIGHT_HAND have integrity?" declaratively.
 *
 * MarbleScript (future):
 *   body Humanoid {
 *       part right_hand { layers: [Flesh 3, Bone 5] }
 *       part left_hand  { layers: [Flesh 3, Bone 5] }
 *   }
 * ========================================================================= */

typedef enum {
    BODYPART_NONE       = 0,
    BODYPART_RIGHT_HAND = 1,
    BODYPART_LEFT_HAND  = 2,
    BODYPART_TORSO      = 3,
    BODYPART_HEAD       = 4,
    BODYPART_COUNT
} BodyPartID;

static const char* BODYPART_NAMES[BODYPART_COUNT] = {
    "None", "Right Hand", "Left Hand", "Torso", "Head"
};

#define MAX_BODY_PARTS 6

/* Maps body part slot -> EntityID of its LayerStack.
 * MC_INVALID_INDEX means "no such body part." */
typedef struct {
    EntityID part_entity[MAX_BODY_PARTS]; /* indexed by BodyPartID */
} CBodyParts;

/* =========================================================================
 * SECTION 3: SKILLS
 * ========================================================================= */

typedef enum {
    SKILL_NONE        = 0,
    SKILL_WOODCUTTING = 1,
    SKILL_MINING      = 2,
    SKILL_COMBAT      = 3,
    SKILL_COUNT
} SkillID;

#define MAX_SKILLS 8

typedef struct {
    int32_t level[MAX_SKILLS];  /* indexed by SkillID */
} CSkills;

/* =========================================================================
 * SECTION 4: ANATOMY FLAGS
 * ========================================================================= */

typedef enum {
    ANAT_ARMS  = (1 << 0),
    ANAT_LEGS  = (1 << 1),
    ANAT_HANDS = (1 << 2),
    ANAT_MOUTH = (1 << 3)
} AnatomyFlag;

typedef struct {
    uint32_t flags;
} CAnatomy;

/* =========================================================================
 * SECTION 5: CAPABILITY (Actor-side)
 *
 * NEW: body_part_required field. If not BODYPART_NONE, the processor
 * checks that the actor's body part entity has a LayerStack with
 * integrity > 0 on its outermost layer. This is the "fine motor" gate.
 *
 * MarbleScript:
 *   capability Chop {
 *       require Anatomy.Arms, Anatomy.Hands;
 *       require BodyPart.RightHand.integrity > 0;  // fine motor
 *       skill Woodcutting;
 *   }
 * ========================================================================= */

typedef enum {
    CAP_NONE   = 0,
    CAP_CHOP   = 1,
    CAP_MINE   = 2,
    CAP_STRIKE = 3,
    CAP_COUNT
} CapabilityID;

typedef struct {
    uint32_t   required_anatomy;     /* AnatomyFlag bitfield */
    SkillID    required_skill;
    int32_t    min_skill_level;
    BodyPartID body_part_required;   /* BODYPART_NONE = no body part check */
} CapabilityDef;

static const CapabilityDef CAPABILITY_DEFS[CAP_COUNT] = {
    /*CAP_NONE*/   { 0,                      SKILL_NONE,        0, BODYPART_NONE       },
    /*CAP_CHOP*/   { ANAT_ARMS | ANAT_HANDS, SKILL_WOODCUTTING, 1, BODYPART_RIGHT_HAND },
    /*CAP_MINE*/   { ANAT_ARMS | ANAT_HANDS, SKILL_MINING,      1, BODYPART_RIGHT_HAND },
    /*CAP_STRIKE*/ { ANAT_ARMS,              SKILL_COMBAT,      1, BODYPART_NONE       },
};

typedef struct {
    uint32_t flags;  /* bitfield of (1 << CapabilityID) */
} CCapabilities;

/* =========================================================================
 * SECTION 6: AFFORDANCE (Object-side)
 * ========================================================================= */

typedef enum {
    AFF_NONE      = 0,
    AFF_CHOPPABLE = 1,
    AFF_MINEABLE  = 2,
    AFF_HITTABLE  = 3,
    AFF_COUNT
} AffordanceID;

typedef enum {
    EFFECT_NONE         = 0,
    EFFECT_DAMAGE_LAYER = 1,
    EFFECT_COUNT
} EffectID;

typedef enum {
    COND_NONE                   = 0,
    COND_TOOL_HARDER_THAN_LAYER = 1,
    COND_TARGET_HAS_INTEGRITY   = 2,
    COND_COUNT
} ConditionID;

/* NEW: on_crit_fail field defines what happens on critical failure.
 * crit_fail_threshold: if roll < this value, it's a critical failure. */
typedef struct {
    CapabilityID required_cap;
    ConditionID  condition;
    EffectID     on_success;
    int32_t      difficulty;
    int32_t      crit_fail_threshold;  /* roll below this = crit fail (0 = disabled) */
    BodyPartID   crit_fail_bodypart;   /* which actor body part takes damage on crit */
    int32_t      crit_fail_damage;     /* how much damage on crit fail */
} AffordanceDef;

static const AffordanceDef AFFORDANCE_DEFS[AFF_COUNT] = {
    /*AFF_NONE*/      { CAP_NONE,   COND_NONE,                   EFFECT_NONE,         0,  0, BODYPART_NONE,       0 },
    /*AFF_CHOPPABLE*/ { CAP_CHOP,   COND_TOOL_HARDER_THAN_LAYER, EFFECT_DAMAGE_LAYER, 40, 15, BODYPART_RIGHT_HAND, 2 },
    /*AFF_MINEABLE*/  { CAP_MINE,   COND_TOOL_HARDER_THAN_LAYER, EFFECT_DAMAGE_LAYER, 55, 5, BODYPART_RIGHT_HAND, 1 },
    /*AFF_HITTABLE*/  { CAP_STRIKE, COND_TARGET_HAS_INTEGRITY,   EFFECT_DAMAGE_LAYER, 30, 3, BODYPART_NONE,       0 },
};

typedef struct {
    uint32_t flags;
} CAffordances;

/* =========================================================================
 * SECTION 7: TOOL COMPONENT
 * ========================================================================= */

typedef struct {
    MaterialID material;
} CTool;

/* =========================================================================
 * SECTION 8: VERB
 * ========================================================================= */

typedef enum {
    VERB_NONE   = 0,
    VERB_CHOP   = 1,
    VERB_MINE   = 2,
    VERB_STRIKE = 3,
    VERB_COUNT
} VerbID;

typedef struct {
    CapabilityID actor_cap;
    AffordanceID target_aff;
} VerbDef;

static const VerbDef VERB_DEFS[VERB_COUNT] = {
    /*VERB_NONE*/   { CAP_NONE,   AFF_NONE      },
    /*VERB_CHOP*/   { CAP_CHOP,   AFF_CHOPPABLE },
    /*VERB_MINE*/   { CAP_MINE,   AFF_MINEABLE  },
    /*VERB_STRIKE*/ { CAP_STRIKE, AFF_HITTABLE  },
};

/* =========================================================================
 * SECTION 9: INTERACTION REQUEST
 * ========================================================================= */

#define MAX_INTERACTION_REQUESTS 64

typedef struct {
    EntityID actor;
    EntityID target;
    VerbID   verb;
} InteractionRequest;

/* =========================================================================
 * SECTION 10: GENERIC PROCESSOR — THE MATCH PIPELINE
 *
 * Updated flow:
 *   1. Lookup VerbDef
 *   2. Check actor capability (bitfield)
 *   3. Check anatomy prerequisites
 *   4. Check body part integrity (fine motor gate) ← NEW
 *   5. Check skill level
 *   6. Check target affordance
 *   7. Evaluate condition
 *   8. Roll d100:
 *      - roll < crit_fail_threshold → CRITICAL FAILURE (damage actor) ← NEW
 *      - roll < difficulty-skill    → normal failure (miss)
 *      - roll >= threshold          → success (damage target)
 *   9. Apply effect
 * ========================================================================= */

typedef enum {
    INTERACT_SUCCESS            = 0,
    INTERACT_FAIL_NO_VERB       = 1,
    INTERACT_FAIL_NO_CAP        = 2,
    INTERACT_FAIL_ANATOMY       = 3,
    INTERACT_FAIL_BODY_PART     = 4,  /* NEW: body part destroyed / fine motor lost */
    INTERACT_FAIL_SKILL_LOW     = 5,
    INTERACT_FAIL_NO_AFF        = 6,
    INTERACT_FAIL_CONDITION     = 7,
    INTERACT_FAIL_ROLL          = 8,
    INTERACT_CRIT_FAIL          = 9,  /* NEW: critical failure, self-damage */
    INTERACT_RESULT_COUNT
} InteractResult;

static const char* INTERACT_RESULT_NAMES[INTERACT_RESULT_COUNT] = {
    "SUCCESS",
    "FAIL:NO_VERB",
    "FAIL:NO_CAPABILITY",
    "FAIL:ANATOMY",
    "FAIL:BODY_PART_DAMAGED",
    "FAIL:SKILL_TOO_LOW",
    "FAIL:NO_AFFORDANCE",
    "FAIL:CONDITION",
    "FAIL:ROLL",
    "CRIT_FAIL:SELF_DAMAGE"
};

/* --- Condition Evaluator --- */
static int evaluate_condition(
    ConditionID cond,
    EntityID actor,
    EntityID target,
    const SparseSet* pool_tool,
    const SparseSet* pool_layers
) {
    switch (cond) {
        case COND_NONE:
            return 1;

        case COND_TOOL_HARDER_THAN_LAYER: {
            const CTool* tool;
            const CLayerStack* stack;
            int32_t tool_hardness, layer_hardness;

            tool = (const CTool*)mc_sparse_set_get_const(pool_tool, actor);
            if (tool == NULL) return 0;

            stack = (const CLayerStack*)mc_sparse_set_get_const(pool_layers, target);
            if (stack == NULL) return 0;
            if (stack->layer_count == 0) return 0;

            tool_hardness  = MATERIAL_HARDNESS[tool->material];
            layer_hardness = MATERIAL_HARDNESS[stack->layers[0].material];
            return (tool_hardness > layer_hardness) ? 1 : 0;
        }

        case COND_TARGET_HAS_INTEGRITY: {
            const CLayerStack* stack;
            stack = (const CLayerStack*)mc_sparse_set_get_const(pool_layers, target);
            if (stack == NULL) return 0;
            if (stack->layer_count == 0) return 0;
            return (stack->layers[0].integrity > 0) ? 1 : 0;
        }

        default:
            return 0;
    }
}

/* --- Body Part Integrity Check ---
 * Returns 1 if the actor's specified body part has a LayerStack
 * with outermost layer integrity > 0. Returns 1 if no check needed. */
static int check_body_part_integrity(
    BodyPartID part,
    EntityID actor,
    const SparseSet* pool_body_parts,
    const SparseSet* pool_layers
) {
    const CBodyParts* bp;
    EntityID part_eid;
    const CLayerStack* stack;

    if (part == BODYPART_NONE) return 1; /* no check needed */

    bp = (const CBodyParts*)mc_sparse_set_get_const(pool_body_parts, actor);
    if (bp == NULL) return 0; /* actor has no body parts component */

    if ((uint32_t)part >= MAX_BODY_PARTS) return 0;
    part_eid = bp->part_entity[part];
    if (part_eid == MC_INVALID_INDEX) return 0; /* body part doesn't exist */

    stack = (const CLayerStack*)mc_sparse_set_get_const(pool_layers, part_eid);
    if (stack == NULL) return 0;
    if (stack->layer_count == 0) return 0; /* all layers destroyed */

    return (stack->layers[0].integrity > 0) ? 1 : 0;
}

/* --- Effect Applicator --- */
static void apply_effect(
    EffectID effect,
    EntityID target,
    SparseSet* pool_layers
) {
    switch (effect) {
        case EFFECT_NONE:
            break;

        case EFFECT_DAMAGE_LAYER: {
            CLayerStack* stack;
            stack = (CLayerStack*)mc_sparse_set_get(pool_layers, target);
            if (stack == NULL) break;
            if (stack->layer_count == 0) break;

            stack->layers[0].integrity--;

            if (stack->layers[0].integrity <= 0) {
                uint32_t i;
                printf("    >> Layer DESTROYED: %s peeled <<\n",
                       MATERIAL_NAMES[stack->layers[0].material]);
                for (i = 0; i + 1 < stack->layer_count; i++) {
                    stack->layers[i] = stack->layers[i + 1];
                }
                stack->layer_count--;
            }
            break;
        }

        default:
            break;
    }
}

/* --- Critical Failure: Self-Damage ---
 * Damages the actor's body part. Uses the same layer damage logic. */
static void apply_crit_fail_damage(
    EntityID actor,
    BodyPartID part,
    int32_t damage,
    const SparseSet* pool_body_parts,
    SparseSet* pool_layers
) {
    const CBodyParts* bp;
    EntityID part_eid;
    CLayerStack* stack;
    int32_t d;

    if (part == BODYPART_NONE) return;
    if (damage <= 0) return;

    bp = (const CBodyParts*)mc_sparse_set_get_const(pool_body_parts, actor);
    if (bp == NULL) return;

    part_eid = bp->part_entity[part];
    if (part_eid == MC_INVALID_INDEX) return;

    stack = (CLayerStack*)mc_sparse_set_get(pool_layers, part_eid);
    if (stack == NULL) return;

    printf("    >> CRIT FAIL! Entity %u damages own %s! <<\n",
           actor, BODYPART_NAMES[part]);

    for (d = 0; d < damage && stack->layer_count > 0; d++) {
        stack->layers[0].integrity--;
        printf("    >> %s integrity -> %d/%d <<\n",
               MATERIAL_NAMES[stack->layers[0].material],
               stack->layers[0].integrity,
               stack->layers[0].max_integrity);

        if (stack->layers[0].integrity <= 0) {
            uint32_t i;
            printf("    >> %s layer on %s DESTROYED <<\n",
                   MATERIAL_NAMES[stack->layers[0].material],
                   BODYPART_NAMES[part]);
            for (i = 0; i + 1 < stack->layer_count; i++) {
                stack->layers[i] = stack->layers[i + 1];
            }
            stack->layer_count--;

            if (stack->layer_count == 0) {
                printf("    >> %s FULLY DESTROYED -- fine motor LOST <<\n",
                       BODYPART_NAMES[part]);
            }
        }
    }
}

/* --- The Generic Processor --- */
static InteractResult process_interaction(
    const InteractionRequest* req,
    const SparseSet* pool_caps,
    const SparseSet* pool_affs,
    const SparseSet* pool_anatomy,
    const SparseSet* pool_skills,
    const SparseSet* pool_tool,
    const SparseSet* pool_body_parts,
    SparseSet*       pool_layers,  /* mutable -- effects write here */
    McRng*           rng           /* deterministic PRNG state */
) {
    const VerbDef*       vdef;
    const CapabilityDef* cdef;
    const AffordanceDef* adef;
    const CCapabilities* actor_caps;
    const CAffordances*  target_affs;
    const CAnatomy*      actor_anat;
    const CSkills*       actor_skills;
    int32_t              skill_level;
    int32_t              roll;
    int32_t              threshold;

    /* 1. Lookup verb */
    if (req->verb <= VERB_NONE || req->verb >= VERB_COUNT) {
        return INTERACT_FAIL_NO_VERB;
    }
    vdef = &VERB_DEFS[req->verb];

    /* 2. Check actor has required capability flag */
    actor_caps = (const CCapabilities*)mc_sparse_set_get_const(pool_caps, req->actor);
    if (actor_caps == NULL) return INTERACT_FAIL_NO_CAP;
    if (!(actor_caps->flags & (1u << vdef->actor_cap))) return INTERACT_FAIL_NO_CAP;

    /* 3. Check capability prerequisites */
    cdef = &CAPABILITY_DEFS[vdef->actor_cap];

    /* 3a. Anatomy check */
    actor_anat = (const CAnatomy*)mc_sparse_set_get_const(pool_anatomy, req->actor);
    if (actor_anat == NULL) return INTERACT_FAIL_ANATOMY;
    if ((actor_anat->flags & cdef->required_anatomy) != cdef->required_anatomy) {
        return INTERACT_FAIL_ANATOMY;
    }

    /* 3b. Body part integrity check (fine motor gate) — NEW */
    if (!check_body_part_integrity(cdef->body_part_required,
                                    req->actor, pool_body_parts, pool_layers)) {
        return INTERACT_FAIL_BODY_PART;
    }

    /* 3c. Skill level check */
    actor_skills = (const CSkills*)mc_sparse_set_get_const(pool_skills, req->actor);
    if (actor_skills == NULL) return INTERACT_FAIL_SKILL_LOW;
    skill_level = actor_skills->level[cdef->required_skill];
    if (skill_level < cdef->min_skill_level) return INTERACT_FAIL_SKILL_LOW;

    /* 4. Check target has required affordance */
    target_affs = (const CAffordances*)mc_sparse_set_get_const(pool_affs, req->target);
    if (target_affs == NULL) return INTERACT_FAIL_NO_AFF;
    if (!(target_affs->flags & (1u << vdef->target_aff))) return INTERACT_FAIL_NO_AFF;

    /* 5. Evaluate condition */
    adef = &AFFORDANCE_DEFS[vdef->target_aff];
    if (!evaluate_condition(adef->condition, req->actor, req->target,
                            pool_tool, pool_layers)) {
        return INTERACT_FAIL_CONDITION;
    }

    /* 6. Roll d100 -- deterministic PRNG */
    roll = mc_rng_d100(rng);
    threshold = adef->difficulty - skill_level;
    if (threshold < 5) threshold = 5;  /* minimum 5% fail chance */

    /* 6a. Critical failure check — NEW */
    if (adef->crit_fail_threshold > 0 && roll < adef->crit_fail_threshold) {
        apply_crit_fail_damage(
            req->actor,
            adef->crit_fail_bodypart,
            adef->crit_fail_damage,
            pool_body_parts,
            pool_layers
        );
        return INTERACT_CRIT_FAIL;
    }

    /* 6b. Normal failure */
    if (roll < threshold) {
        return INTERACT_FAIL_ROLL;
    }

    /* 7. Apply effect on target */
    apply_effect(adef->on_success, req->target, pool_layers);
    return INTERACT_SUCCESS;
}

#endif /* MARBLE_INTERACT_H */