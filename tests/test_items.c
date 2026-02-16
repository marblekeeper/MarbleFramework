/*
 * test_items.c -- Item Definition System Tests
 *
 * Tests the item definition table, affordance lookup, property
 * resolution, and transform chains matching the game design document.
 *
 * BUILD:
 *   gcc -std=c99 -Wall -Wextra -O2 test_items.c -o test_items.exe
 */

#include "marble_cmd.h"
#include "marble_items.h"

/* =========================================================================
 * TEST FRAMEWORK
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

#define ASSERT_NULL(ptr) \
    do { \
        if ((ptr) != NULL) { \
            printf("  FAIL: %s (line %d): %s should be NULL\n", \
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
 * VERB IDs for item tests (these match the game design doc)
 * ========================================================================= */

enum {
    V_EXAMINE = 20,
    V_EAT     = 21,
    V_DRINK   = 22,
    V_DROP    = 23,
    V_PLACE   = 24,
    V_LIGHT   = 25,
    V_EXTINGUISH = 26,
    V_EXTRACT = 27,
    V_PLANT   = 28,
    V_WATER   = 29,
    V_SMELT   = 30,
    V_FORGE   = 31,
    V_SHARPEN = 32,
    V_TAN     = 33,
    V_ETCH    = 34,
    V_READ    = 35,
    V_DISCARD = 36,
    V_THROW   = 37,
    V_CRUMBLE = 38,
    V_TWIST   = 39,
};

/* =========================================================================
 * HELPER: Build item defs matching the game design document
 * ========================================================================= */

static ItemDefTable g_items;

/* Helper to add a property to an affordance */
static void add_prop(ItemAfford* a, uint32_t key, int32_t value) {
    if (a->prop_count < MAX_ITEM_PROPS) {
        a->props[a->prop_count].key   = key;
        a->props[a->prop_count].value = value;
        a->prop_count++;
    }
}

/* Helper to add a component init to a def */
static void add_comp(ItemDef* d, ItemCompType type, int32_t v0, int32_t v1, int32_t v2, int32_t v3) {
    if (d->comp_count < MAX_ITEM_COMPS) {
        d->comps[d->comp_count].type      = type;
        d->comps[d->comp_count].values[0] = v0;
        d->comps[d->comp_count].values[1] = v1;
        d->comps[d->comp_count].values[2] = v2;
        d->comps[d->comp_count].values[3] = v3;
        d->comp_count++;
    }
}

/* Helper to add an affordance to a def */
static ItemAfford* add_afford(ItemDef* d, uint32_t verb_id, uint32_t transform_to) {
    ItemAfford* a;
    if (d->afford_count >= MAX_ITEM_AFFORDS) return NULL;
    a = &d->affords[d->afford_count];
    memset(a, 0, sizeof(*a));
    a->verb_id      = verb_id;
    a->transform_to = transform_to;
    d->afford_count++;
    return a;
}

static void build_item_table(void) {
    ItemDef d;

    mc_item_table_init(&g_items);

    /* ---- 900: Golden JSON Apple ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 900;
    d.weight = 20;  /* 0.2 * 100 */
    d.tags   = TAG_FOOD | TAG_FRUIT | TAG_RARE;
    {
        ItemAfford* a;
        a = add_afford(&d, V_EAT, 901);     /* Eat -> Apple Core */
        add_prop(a, PROP_NUTRITION, 2500);   /* 25.0 * 100 */
        add_prop(a, PROP_MESSAGE, 1);        /* msg_id 1 */
        add_afford(&d, V_EXAMINE, 0);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 901: Apple Core ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 901;
    d.weight = 5;
    d.tags   = TAG_TRASH | TAG_ORGANIC;
    add_afford(&d, V_EXAMINE, 0);
    add_afford(&d, V_DROP, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_EXTRACT, 902);  /* Extract -> Apple Seeds */
        add_prop(a, PROP_MESSAGE, 2);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 902: Apple Seeds ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 902;
    d.weight = 1;
    d.tags   = TAG_SEED | TAG_ORGANIC | TAG_PLANT;
    add_afford(&d, V_EXAMINE, 0);
    add_afford(&d, V_DROP, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_PLANT, 903);    /* Plant -> Apple Sapling */
        add_prop(a, PROP_MESSAGE, 3);
    }
    add_comp(&d, ICOMP_STACK, 5, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 903: Apple Sapling ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 903;
    d.weight = 200;
    d.tags   = TAG_PLANT | TAG_ORGANIC;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_WATER, 0);  /* Water doesn't transform, just grows */
        add_prop(a, PROP_GROWTH_AMOUNT, 1000); /* 10.0 * 100 */
        add_prop(a, PROP_MESSAGE, 4);
    }
    add_comp(&d, ICOMP_GROWTH, 1, 3, 0, 0);  /* stage 1, max_stage 3 */
    mc_item_table_add(&g_items, &d);

    /* ---- 2: Health Potion ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 2;
    d.weight = 10;
    d.tags   = TAG_CONSUMABLE | TAG_LIQUID | TAG_HEALING;
    {
        ItemAfford* a;
        a = add_afford(&d, V_DRINK, 500);    /* Drink -> Empty Vial */
        add_prop(a, PROP_HEAL_AMOUNT, 3000);  /* 30.0 * 100 */
        add_prop(a, PROP_MESSAGE, 5);
    }
    add_afford(&d, V_EXAMINE, 0);
    add_comp(&d, ICOMP_STACK, 3, 0, 0, 0);
    add_comp(&d, ICOMP_QUALITY, 5000, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 500: Empty Glass Vial ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 500;
    d.weight = 10;
    d.tags   = TAG_CONTAINER | TAG_GLASS | TAG_CRAFTING;
    add_afford(&d, V_EXAMINE, 0);
    add_afford(&d, V_DROP, 501);    /* Drop -> Broken Glass (fragile!) */
    add_afford(&d, V_PLACE, 0);     /* Place doesn't break it */
    add_afford(&d, V_THROW, 0);
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 501: Broken Glass ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 501;
    d.weight = 10;
    d.tags   = TAG_TRASH | TAG_SHARP;
    add_afford(&d, V_EXAMINE, 0);
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 700: Torch ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 700;
    d.weight = 80;
    d.tags   = TAG_TOOL | TAG_LIGHT | TAG_FIRE;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_LIGHT, 701);   /* Light -> Lit Torch */
        add_prop(a, PROP_MESSAGE, 10);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    add_comp(&d, ICOMP_DURABILITY, 30000, 30000, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 701: Lit Torch ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 701;
    d.weight = 80;
    d.tags   = TAG_TOOL | TAG_LIGHT | TAG_FIRE | TAG_BURNING;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_EXTINGUISH, 702); /* Extinguish -> Burnt Torch */
        add_prop(a, PROP_MESSAGE, 11);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    add_comp(&d, ICOMP_DURABILITY, 30000, 30000, 0, 0);
    add_comp(&d, ICOMP_LIGHT, 500, 80, 0, 0);  /* radius 5.0, intensity 0.8 */
    mc_item_table_add(&g_items, &d);

    /* ---- 702: Burnt Torch ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 702;
    d.weight = 50;
    d.tags   = TAG_TRASH;
    add_afford(&d, V_EXAMINE, 0);
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 950: Iron Ore ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 950;
    d.weight = 300;
    d.tags   = TAG_MATERIAL | TAG_METAL | TAG_ORE;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_SMELT, 951);   /* Smelt -> Iron Bar */
        add_prop(a, PROP_MESSAGE, 20);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 951: Iron Bar ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 951;
    d.weight = 250;
    d.tags   = TAG_MATERIAL | TAG_METAL | TAG_REFINED;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_FORGE, 1);     /* Forge -> Rusty Iron Sword */
        add_prop(a, PROP_MESSAGE, 21);
    }
    add_comp(&d, ICOMP_STACK, 1, 0, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 1: Rusty Iron Sword ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 1;
    d.weight = 520;
    d.tags   = TAG_WEAPON | TAG_METAL | TAG_BLUNT;
    add_afford(&d, V_EXAMINE, 0);
    {
        ItemAfford* a;
        a = add_afford(&d, V_SHARPEN, 4);   /* Sharpen -> Sharp Iron Sword */
        add_prop(a, PROP_MESSAGE, 22);
    }
    add_comp(&d, ICOMP_QUALITY, 2550, 0, 0, 0);
    add_comp(&d, ICOMP_DURABILITY, 10000, 8000, 0, 0);
    mc_item_table_add(&g_items, &d);

    /* ---- 4: Sharp Iron Sword ---- */
    memset(&d, 0, sizeof(d));
    d.def_id = 4;
    d.weight = 500;
    d.tags   = TAG_WEAPON | TAG_METAL | TAG_SHARP;
    add_afford(&d, V_EXAMINE, 0);
    add_comp(&d, ICOMP_QUALITY, 7500, 0, 0, 0);
    add_comp(&d, ICOMP_DURABILITY, 10000, 10000, 0, 0);
    mc_item_table_add(&g_items, &d);
}

/* =========================================================================
 * SECTION 1: TABLE OPERATION TESTS
 * ========================================================================= */

static void test_item_table_init(void) {
    TEST_BEGIN("item_table: init produces empty table");
    {
        ItemDefTable table;
        mc_item_table_init(&table);
        ASSERT_EQ_U32(table.count, 0);
        ASSERT_NULL(mc_item_table_get(&table, 0));
    }
    TEST_END();
}

static void test_item_table_add_and_get(void) {
    TEST_BEGIN("item_table: add then get returns correct def");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        ASSERT_NOT_NULL(apple);
        ASSERT_EQ_U32(apple->def_id, 900);
        ASSERT_EQ_I32(apple->weight, 20);
        ASSERT(apple->tags & TAG_FOOD);
        ASSERT(apple->tags & TAG_FRUIT);
        ASSERT(apple->tags & TAG_RARE);
    }
    TEST_END();
}

static void test_item_table_get_missing(void) {
    TEST_BEGIN("item_table: get nonexistent def returns NULL");
    build_item_table();
    ASSERT_NULL(mc_item_table_get(&g_items, 99999));
    TEST_END();
}

static void test_item_table_count(void) {
    TEST_BEGIN("item_table: correct count after building all items");
    build_item_table();
    ASSERT_EQ_U32(g_items.count, 14);  /* 14 items defined above */
    TEST_END();
}

/* =========================================================================
 * SECTION 2: AFFORDANCE LOOKUP TESTS
 * ========================================================================= */

static void test_afford_find_eat(void) {
    TEST_BEGIN("afford: find Eat on Golden Apple");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        const ItemAfford* eat = mc_item_find_afford(apple, V_EAT);
        ASSERT_NOT_NULL(eat);
        ASSERT_EQ_U32(eat->verb_id, V_EAT);
        ASSERT_EQ_U32(eat->transform_to, 901);  /* -> Apple Core */
    }
    TEST_END();
}

static void test_afford_find_missing(void) {
    TEST_BEGIN("afford: find nonexistent verb returns NULL");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        const ItemAfford* smelt = mc_item_find_afford(apple, V_SMELT);
        ASSERT_NULL(smelt);  /* can't smelt an apple */
    }
    TEST_END();
}

static void test_afford_no_transform(void) {
    TEST_BEGIN("afford: Examine has no transform (transform_to == 0)");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        const ItemAfford* exam = mc_item_find_afford(apple, V_EXAMINE);
        ASSERT_NOT_NULL(exam);
        ASSERT_EQ_U32(exam->transform_to, 0);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 3: PROPERTY LOOKUP TESTS
 * ========================================================================= */

static void test_prop_nutrition(void) {
    TEST_BEGIN("prop: Golden Apple Eat has nutrition 2500");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        const ItemAfford* eat = mc_item_find_afford(apple, V_EAT);
        int32_t nutr = mc_afford_prop(eat, PROP_NUTRITION, 0);
        ASSERT_EQ_I32(nutr, 2500);
    }
    TEST_END();
}

static void test_prop_heal_amount(void) {
    TEST_BEGIN("prop: Health Potion Drink has heal_amount 3000");
    build_item_table();
    {
        const ItemDef* potion = mc_item_table_get(&g_items, 2);
        const ItemAfford* drink = mc_item_find_afford(potion, V_DRINK);
        int32_t heal = mc_afford_prop(drink, PROP_HEAL_AMOUNT, 0);
        ASSERT_EQ_I32(heal, 3000);
    }
    TEST_END();
}

static void test_prop_missing_returns_default(void) {
    TEST_BEGIN("prop: missing property returns default value");
    build_item_table();
    {
        const ItemDef* apple = mc_item_table_get(&g_items, 900);
        const ItemAfford* eat = mc_item_find_afford(apple, V_EAT);
        int32_t heal = mc_afford_prop(eat, PROP_HEAL_AMOUNT, -1);
        ASSERT_EQ_I32(heal, -1);  /* apple has nutrition, not heal_amount */
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 4: COMPONENT INIT DATA TESTS
 * ========================================================================= */

static void test_comp_stack(void) {
    TEST_BEGIN("comp: Health Potion has Stack count 3");
    build_item_table();
    {
        const ItemDef* potion = mc_item_table_get(&g_items, 2);
        ASSERT(potion->comp_count >= 1);
        ASSERT_EQ_I32(potion->comps[0].type, ICOMP_STACK);
        ASSERT_EQ_I32(potion->comps[0].values[0], 3);
    }
    TEST_END();
}

static void test_comp_durability(void) {
    TEST_BEGIN("comp: Rusty Sword has Durability max=10000 current=8000");
    build_item_table();
    {
        const ItemDef* sword = mc_item_table_get(&g_items, 1);
        /* Find durability comp */
        uint32_t i;
        int found = 0;
        for (i = 0; i < sword->comp_count; i++) {
            if (sword->comps[i].type == ICOMP_DURABILITY) {
                ASSERT_EQ_I32(sword->comps[i].values[0], 10000);
                ASSERT_EQ_I32(sword->comps[i].values[1], 8000);
                found = 1;
            }
        }
        ASSERT(found);
    }
    TEST_END();
}

static void test_comp_growth(void) {
    TEST_BEGIN("comp: Apple Sapling has Growth stage=1 max_stage=3");
    build_item_table();
    {
        const ItemDef* sapling = mc_item_table_get(&g_items, 903);
        ASSERT(sapling->comp_count >= 1);
        ASSERT_EQ_I32(sapling->comps[0].type, ICOMP_GROWTH);
        ASSERT_EQ_I32(sapling->comps[0].values[0], 1);
        ASSERT_EQ_I32(sapling->comps[0].values[1], 3);
    }
    TEST_END();
}

static void test_comp_light(void) {
    TEST_BEGIN("comp: Lit Torch has LightSource radius=500 intensity=80");
    build_item_table();
    {
        const ItemDef* torch = mc_item_table_get(&g_items, 701);
        uint32_t i;
        int found = 0;
        for (i = 0; i < torch->comp_count; i++) {
            if (torch->comps[i].type == ICOMP_LIGHT) {
                ASSERT_EQ_I32(torch->comps[i].values[0], 500);
                ASSERT_EQ_I32(torch->comps[i].values[1], 80);
                found = 1;
            }
        }
        ASSERT(found);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 5: TRANSFORM CHAIN TESTS
 *
 * These trace the full transform chains from the game design doc.
 * Each chain follows the -> arrows through the item table.
 * ========================================================================= */

static void test_chain_apple(void) {
    TEST_BEGIN("chain: Golden Apple -> Core -> Seeds -> Sapling");
    build_item_table();
    {
        const ItemDef* item;
        const ItemAfford* a;

        /* 900: Golden Apple -- Eat -> 901 */
        item = mc_item_table_get(&g_items, 900);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_EAT);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 901);

        /* 901: Apple Core -- Extract -> 902 */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_EXTRACT);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 902);

        /* 902: Apple Seeds -- Plant -> 903 */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_PLANT);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 903);

        /* 903: Apple Sapling -- no further transform, but can Water */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_WATER);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 0); /* water doesn't transform */
    }
    TEST_END();
}

static void test_chain_potion(void) {
    TEST_BEGIN("chain: Health Potion -> Empty Vial -> Broken Glass");
    build_item_table();
    {
        const ItemDef* item;
        const ItemAfford* a;

        /* 2: Health Potion -- Drink -> 500 */
        item = mc_item_table_get(&g_items, 2);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_DRINK);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 500);

        /* 500: Empty Vial -- Drop -> 501 (fragile!) */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_DROP);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 501);

        /* 501: Broken Glass -- terminal node (no transform affords) */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        ASSERT_EQ_U32(item->afford_count, 1); /* only Examine */
    }
    TEST_END();
}

static void test_chain_torch(void) {
    TEST_BEGIN("chain: Torch -> Lit Torch -> Burnt Torch");
    build_item_table();
    {
        const ItemDef* item;
        const ItemAfford* a;

        /* 700: Torch -- Light -> 701 */
        item = mc_item_table_get(&g_items, 700);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_LIGHT);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 701);

        /* 701: Lit Torch -- Extinguish -> 702 */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        ASSERT(item->tags & TAG_BURNING);
        a = mc_item_find_afford(item, V_EXTINGUISH);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 702);

        /* 702: Burnt Torch -- terminal */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        ASSERT(item->tags & TAG_TRASH);
    }
    TEST_END();
}

static void test_chain_smithing(void) {
    TEST_BEGIN("chain: Iron Ore -> Iron Bar -> Rusty Sword -> Sharp Sword");
    build_item_table();
    {
        const ItemDef* item;
        const ItemAfford* a;

        /* 950: Iron Ore -- Smelt -> 951 */
        item = mc_item_table_get(&g_items, 950);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_SMELT);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 951);

        /* 951: Iron Bar -- Forge -> 1 */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_FORGE);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 1);

        /* 1: Rusty Sword -- Sharpen -> 4 */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        a = mc_item_find_afford(item, V_SHARPEN);
        ASSERT_NOT_NULL(a);
        ASSERT_EQ_U32(a->transform_to, 4);

        /* 4: Sharp Sword -- terminal (no transform) */
        item = mc_item_table_get(&g_items, a->transform_to);
        ASSERT_NOT_NULL(item);
        ASSERT(item->tags & TAG_SHARP);
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 6: TRANSFORM VIA COMMAND BUFFER INTEGRATION
 *
 * Proves the full path: item def -> affordance lookup -> emit command
 * -> flush -> entity def_id changes -> new def resolves correctly.
 * ========================================================================= */

static void test_item_transform_via_cmd_buf(void) {
    TEST_BEGIN("integration: eat apple emits transform, flush updates def, new def resolves");
    build_item_table();
    {
        SparseSet pool_item_defs;
        CommandBuffer buf;
        PoolPtrs pools;
        CItemDef entity_def;
        CItemDef* fetched;
        const ItemDef* current_def;
        const ItemAfford* eat;

        mc_sparse_set_init(&pool_item_defs, sizeof(CItemDef));
        mc_cmd_buf_init(&buf);

        /* Spawn entity 50 as a Golden Apple */
        entity_def.def_id = 900;
        mc_sparse_set_add(&pool_item_defs, 50, &entity_def);

        /* Look up the item's Eat affordance */
        current_def = mc_item_table_get(&g_items, 900);
        eat = mc_item_find_afford(current_def, V_EAT);
        ASSERT_NOT_NULL(eat);

        /* Emit transform command */
        mc_emit_item_transform(&buf, 0, 0, 50, eat);
        ASSERT_EQ_U32(buf.count, 1);

        /* Flush */
        pools.layers = NULL;
        pools.item_defs = &pool_item_defs;
        mc_cmd_flush(&buf, &pools);

        /* Entity 50 now has def_id 901 */
        fetched = (CItemDef*)mc_sparse_set_get(&pool_item_defs, 50);
        ASSERT_EQ_U32(fetched->def_id, 901);

        /* Resolve new definition -- it's Apple Core */
        current_def = mc_item_table_get(&g_items, fetched->def_id);
        ASSERT_NOT_NULL(current_def);

        /* Apple Core should have Extract -> 902 */
        {
            const ItemAfford* extract = mc_item_find_afford(current_def, V_EXTRACT);
            ASSERT_NOT_NULL(extract);
            ASSERT_EQ_U32(extract->transform_to, 902);
        }
    }
    TEST_END();
}

/* =========================================================================
 * SECTION 7: TAG FILTERING
 * ========================================================================= */

static void test_tag_filtering(void) {
    TEST_BEGIN("tags: filter items by tag bitmask");
    build_item_table();
    {
        uint32_t food_count = 0;
        uint32_t metal_count = 0;
        uint32_t i;

        for (i = 0; i < g_items.count; i++) {
            if (g_items.defs[i].tags & TAG_FOOD) food_count++;
            if (g_items.defs[i].tags & TAG_METAL) metal_count++;
        }
        ASSERT_EQ_U32(food_count, 1);  /* Golden Apple */
        ASSERT_EQ_U32(metal_count, 4); /* Iron Ore, Iron Bar, Rusty Sword, Sharp Sword */
    }
    TEST_END();
}


/* =========================================================================
 * RUN ALL TESTS
 * ========================================================================= */

int main(void) {
    printf("MarbleEngine Item Definition Tests\n");
    printf("==================================\n\n");

    /* Table Operations */
    printf("[Item Table]\n");
    test_item_table_init();
    test_item_table_add_and_get();
    test_item_table_get_missing();
    test_item_table_count();

    /* Affordance Lookup */
    printf("\n[Affordance Lookup]\n");
    test_afford_find_eat();
    test_afford_find_missing();
    test_afford_no_transform();

    /* Property Lookup */
    printf("\n[Property Lookup]\n");
    test_prop_nutrition();
    test_prop_heal_amount();
    test_prop_missing_returns_default();

    /* Component Init Data */
    printf("\n[Component Init Data]\n");
    test_comp_stack();
    test_comp_durability();
    test_comp_growth();
    test_comp_light();

    /* Transform Chains */
    printf("\n[Transform Chains]\n");
    test_chain_apple();
    test_chain_potion();
    test_chain_torch();
    test_chain_smithing();

    /* Command Buffer Integration */
    printf("\n[Command Buffer Integration]\n");
    test_item_transform_via_cmd_buf();

    /* Tag Filtering */
    printf("\n[Tag Filtering]\n");
    test_tag_filtering();


    /* Summary */
    printf("\n==================================\n");
    printf("TOTAL: %d  PASSED: %d  FAILED: %d\n",
           g_tests_run, g_tests_passed, g_tests_failed);

    if (g_tests_failed == 0) {
        printf("ALL TESTS PASSED\n");
    } else {
        printf("*** FAILURES DETECTED ***\n");
    }

    return (g_tests_failed > 0) ? 1 : 0;
}