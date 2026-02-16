/*
 * marble_items.h -- Item Definition System (Phase 0.3)
 *
 * ARCHITECTURE:
 *   Items have two layers:
 *
 *   1. DEFINITION (ItemDef) -- static, immutable, shared.
 *      "What IS a Health Potion?" -- name, weight, tags, affordances,
 *      components, transform targets. Stored in a global lookup table
 *      indexed by def_id. Never mutated at runtime.
 *
 *   2. INSTANCE (CItemDef component on an entity) -- per-entity.
 *      "This particular Health Potion in slot 3." Entity has a CItemDef
 *      component with def_id=2, plus instance-specific components like
 *      CStack{count:3} or CDurability{current:80}.
 *
 *   TRANSFORM CHAINS:
 *     AFFORD Eat -> 901 means: "When the Eat affordance succeeds, emit
 *     CMD_TRANSFORM_ENTITY with new_def_id=901." The entity's CItemDef
 *     changes from def 900 (Golden Apple) to def 901 (Apple Core).
 *     The entity ID stays the same -- only the definition changes.
 *
 *   AFFORDANCE PROPERTIES:
 *     Each item-affordance entry carries key-value properties that the
 *     rule system reads at runtime. Example:
 *       AFFORD Drink -> 500 { heal_amount: 30, message: "A refreshing gulp!" }
 *     The rule for Drink reads heal_amount from the affordance properties
 *     and emits CMD_MODIFY_STAT with that value.
 *
 * CONSTRAINTS: Same as marble_core.h (no malloc, no fn ptrs, no recursion)
 */

#ifndef MARBLE_ITEMS_H
#define MARBLE_ITEMS_H

#include "marble_core.h"

/* =========================================================================
 * SECTION 1: ITEM TAGS (bitfield)
 *
 * Tags categorize items for filtering, crafting recipes, and condition
 * checks. An item can have multiple tags ORed together.
 * ========================================================================= */

typedef enum {
    TAG_NONE        = 0,
    TAG_WEAPON      = (1 << 0),
    TAG_METAL       = (1 << 1),
    TAG_CONSUMABLE  = (1 << 2),
    TAG_LIQUID      = (1 << 3),
    TAG_HEALING     = (1 << 4),
    TAG_FOOD        = (1 << 5),
    TAG_CONTAINER   = (1 << 6),
    TAG_GLASS       = (1 << 7),
    TAG_CRAFTING    = (1 << 8),
    TAG_TRASH       = (1 << 9),
    TAG_SHARP       = (1 << 10),
    TAG_MATERIAL    = (1 << 11),
    TAG_ORGANIC     = (1 << 12),
    TAG_SEED        = (1 << 13),
    TAG_PLANT       = (1 << 14),
    TAG_TOOL        = (1 << 15),
    TAG_FIRE        = (1 << 16),
    TAG_MAGIC       = (1 << 17),
    TAG_DOCUMENT    = (1 << 18),
    TAG_LEATHER     = (1 << 19),
    TAG_ORE         = (1 << 20),
    TAG_REFINED     = (1 << 21),
    TAG_SPOILED     = (1 << 22),
    TAG_RARE        = (1 << 23),
    TAG_BLUNT       = (1 << 24),
    TAG_BONE        = (1 << 25),
    TAG_INSCRIBED   = (1 << 26),
    TAG_LIGHT       = (1 << 27),
    TAG_BURNING     = (1 << 28),
    TAG_MEAT        = (1 << 29),
    TAG_FRUIT       = (1 << 30),
} ItemTag;

/* =========================================================================
 * SECTION 2: AFFORDANCE PROPERTIES
 *
 * Each item-affordance entry can carry up to MAX_ITEM_PROPS key-value
 * pairs. Keys are uint32 hashes; values are either int32 or float
 * (determined by the consuming rule).
 *
 * This is how "heal_amount: 30" gets attached to a specific item's
 * Drink affordance without hardcoding it into the AffordanceDef.
 * ========================================================================= */

#define MAX_ITEM_PROPS 8

/* Property keys -- these are the known property names hashed to enums.
 * Phase 1+ will generate these from .marble source. */
typedef enum {
    PROP_NONE          = 0,
    PROP_HEAL_AMOUNT   = 1,
    PROP_MESSAGE       = 2,   /* index into message table */
    PROP_NUTRITION     = 3,
    PROP_TRANSFORM_ID  = 4,   /* redundant with afford->transform_to, but
                                 available for rule indirection */
    PROP_DAMAGE        = 5,
    PROP_STAMINA_COST  = 6,
    PROP_MANA_COST     = 7,
    PROP_DURABILITY_LOSS = 8,
    PROP_DESCRIPTION   = 9,
    PROP_GROWTH_AMOUNT = 10,
    PROP_QUALITY_BOOST = 11,
    PROP_REPAIR_AMOUNT = 12,
    PROP_PRICE         = 13,
    PROP_SELL_VALUE    = 14,
    PROP_ARMOR_VALUE   = 15,
    PROP_STRENGTH_REQ  = 16,
    PROP_ARROW_COST    = 17,
    PROP_SPELL_EFFECT  = 18,
    PROP_COUNT
} PropertyKey;

typedef struct {
    uint32_t key;     /* PropertyKey */
    int32_t  value;   /* integer value (floats stored as fixed-point * 100) */
} ItemProp;

/* =========================================================================
 * SECTION 3: ITEM AFFORDANCE ENTRY
 *
 * One entry per affordance that this item supports.
 * "What can be done to this item?"
 *
 * The transform_to field is the -> operator:
 *   AFFORD Eat -> 901
 * means transform_to = 901 (def_id of Apple Core).
 * 0 means no transform (action doesn't change the item).
 * ========================================================================= */

#define MAX_ITEM_AFFORDS 8

typedef struct {
    uint32_t  verb_id;        /* VerbID this affordance responds to */
    uint32_t  transform_to;   /* def_id to transform into, or 0 */
    ItemProp  props[MAX_ITEM_PROPS];
    uint32_t  prop_count;
} ItemAfford;

/* =========================================================================
 * SECTION 4: ITEM COMPONENT INIT DATA
 *
 * Static data for initializing entity components when an item is
 * spawned. Example: COMP Durability { max: 100, current: 80 }
 *
 * Component types are identified by enum. Init values are stored as
 * fixed-size arrays of int32 (up to 4 values per component).
 * ========================================================================= */

#define MAX_ITEM_COMPS 4
#define MAX_COMP_VALUES 4

typedef enum {
    ICOMP_NONE       = 0,
    ICOMP_STACK      = 1,  /* values[0] = count */
    ICOMP_QUALITY    = 2,  /* values[0] = value (x100 for float) */
    ICOMP_DURABILITY = 3,  /* values[0] = max (x100), values[1] = current (x100) */
    ICOMP_GROWTH     = 4,  /* values[0] = stage, values[1] = max_stage */
    ICOMP_LIGHT      = 5,  /* values[0] = radius (x100), values[1] = intensity (x100) */
    ICOMP_COUNT
} ItemCompType;

static const char* ICOMP_NAMES[ICOMP_COUNT] = {
    "None", "Stack", "Quality", "Durability", "Growth", "LightSource"
};

typedef struct {
    ItemCompType type;
    int32_t      values[MAX_COMP_VALUES];
} ItemCompInit;

/* =========================================================================
 * SECTION 5: ITEM DEFINITION
 *
 * The complete static definition of an item. Indexed by def_id.
 * This is what the Lua compiler generates from ITEM blocks.
 * ========================================================================= */

typedef struct {
    uint32_t      def_id;         /* unique item definition ID */
    uint32_t      name_id;        /* index into name/string table */
    int32_t       weight;         /* weight x100 (fixed-point) */
    uint32_t      tags;           /* ItemTag bitfield */

    ItemAfford    affords[MAX_ITEM_AFFORDS];
    uint32_t      afford_count;

    ItemCompInit  comps[MAX_ITEM_COMPS];
    uint32_t      comp_count;
} ItemDef;

/* =========================================================================
 * SECTION 6: ITEM DEFINITION TABLE
 *
 * Global lookup table indexed by def_id. In Phase 0.3 this is a
 * linear scan; Phase 1+ will use a hash map or sorted array.
 * ========================================================================= */

#define MAX_ITEM_DEFS 256

typedef struct {
    ItemDef  defs[MAX_ITEM_DEFS];
    uint32_t count;
} ItemDefTable;

static void mc_item_table_init(ItemDefTable* table) {
    table->count = 0;
}

/* Add a definition to the table. Returns 0 on success, -1 if full. */
static int mc_item_table_add(ItemDefTable* table, const ItemDef* def) {
    if (table->count >= MAX_ITEM_DEFS) return -1;
    table->defs[table->count] = *def;
    table->count++;
    return 0;
}

/* Look up a definition by def_id. Returns NULL if not found. */
static const ItemDef* mc_item_table_get(const ItemDefTable* table, uint32_t def_id) {
    uint32_t i;
    for (i = 0; i < table->count; i++) {
        if (table->defs[i].def_id == def_id) return &table->defs[i];
    }
    return NULL;
}

/* =========================================================================
 * SECTION 7: ITEM AFFORDANCE LOOKUP
 *
 * Given an item def and a verb, find the matching affordance entry.
 * Returns NULL if the item doesn't support that verb.
 * This is how the rule system resolves "can I Eat this item?" and
 * "what happens when I do?" (transform_to, properties).
 * ========================================================================= */

static const ItemAfford* mc_item_find_afford(
    const ItemDef* def, uint32_t verb_id
) {
    uint32_t i;
    for (i = 0; i < def->afford_count; i++) {
        if (def->affords[i].verb_id == verb_id) return &def->affords[i];
    }
    return NULL;
}

/* Look up a property value from an affordance entry.
 * Returns the value if found, or default_val if not. */
static int32_t mc_afford_prop(
    const ItemAfford* afford, uint32_t key, int32_t default_val
) {
    uint32_t i;
    if (afford == NULL) return default_val;
    for (i = 0; i < afford->prop_count; i++) {
        if (afford->props[i].key == key) return afford->props[i].value;
    }
    return default_val;
}

/* =========================================================================
 * SECTION 8: ITEM-AWARE COMMAND EMISSION
 *
 * Convenience: given a successful interaction with an item, emit all
 * the commands implied by the affordance entry (transform, feedback,
 * stat modifications based on properties).
 * ========================================================================= */

/* Emit a transform command if the affordance has a -> target. */
static void mc_emit_item_transform(
    CommandBuffer* buf, uint64_t tick,
    EntityID actor, EntityID item_entity,
    const ItemAfford* afford
) {
    if (afford->transform_to != 0) {
        mc_emit_transform(buf, tick, actor, item_entity, afford->transform_to);
    }
}

/* Emit a feedback command if the affordance has a message property. */
static void mc_emit_item_feedback(
    CommandBuffer* buf, uint64_t tick,
    EntityID actor,
    const ItemAfford* afford
) {
    int32_t msg_id = mc_afford_prop(afford, PROP_MESSAGE, -1);
    if (msg_id >= 0) {
        mc_emit_feedback(buf, tick, actor, (uint32_t)msg_id);
    }
}

#endif /* MARBLE_ITEMS_H */