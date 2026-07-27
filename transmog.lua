local AIO = AIO or require("AIO")
local TransmogHandlers = AIO.AddHandlers("Transmog", {})

local SLOTS = 10
local CALC = 281

-- Opt in only for legacy realms that want existing equipped and bag items to
-- unlock automatically at login.  Keeping this false prevents login-time
-- account-cache construction; players can use Appearance Buddy's explicit
-- "Scan inventory now" control when a backfill is wanted.
local AUTO_UNLOCK_INVENTORY_ON_LOGIN = false

local VISIBLE_SLOTS = {
    283, 287, 289, 291, 293, 295, 297, 299, 301, 311, 313, 315, 317, 319
}

local VISIBLE_SLOT_SET = {}
for _, slot in ipairs(VISIBLE_SLOTS) do
    VISIBLE_SLOT_SET[slot] = true
end

local UNUSABLE_INVENTORY_TYPES = {[2]=true, [11]=true, [12]=true, [18]=true, [24]=true, [27]=true}

local SLOT_INVENTORY_TYPES = {
    [283] = {[1] = true},
    [287] = {[3] = true},
    [289] = {[4] = true},
    [291] = {[5] = true, [20] = true},
    [293] = {[6] = true},
    [295] = {[7] = true},
    [297] = {[8] = true},
    [299] = {[9] = true},
    [301] = {[10] = true},
    [311] = {[16] = true},
    [313] = {[13] = true, [17] = true, [21] = true},
    [315] = {[13] = true, [14] = true, [17] = true, [22] = true},
    [317] = {[15] = true, [25] = true, [26] = true, [28] = true},
    [319] = {[19] = true},
}

-- Reverse the static slot map once. A cold 38k-row account collection now
-- touches only the one or two compatible slots for each row instead of
-- scanning all fourteen visible slots every time.
local VISIBLE_SLOTS_BY_INVENTORY_TYPE = {}
for _, slot in ipairs(VISIBLE_SLOTS) do
    for inventoryType in pairs(SLOT_INVENTORY_TYPES[slot] or {}) do
        local slots = VISIBLE_SLOTS_BY_INVENTORY_TYPE[inventoryType]
        if not slots then
            slots = {}
            VISIBLE_SLOTS_BY_INVENTORY_TYPE[inventoryType] = slots
        end
        slots[#slots + 1] = slot
    end
end

-- Weapon appearance filters mirror DressMe's item class/subclass buckets, but
-- merge generic one-hand and hand-specific inventory types into one readable
-- choice.  The slot allowlists below are also the server-side validation for
-- the filter key received over AIO.
local WEAPON_FILTER_DEFINITIONS = {
    axe_1h = { itemClass = 2, itemSubclass = 0, inventoryTypes = {[13] = true, [21] = true, [22] = true} },
    mace_1h = { itemClass = 2, itemSubclass = 4, inventoryTypes = {[13] = true, [21] = true, [22] = true} },
    sword_1h = { itemClass = 2, itemSubclass = 7, inventoryTypes = {[13] = true, [21] = true, [22] = true} },
    dagger = { itemClass = 2, itemSubclass = 15, inventoryTypes = {[13] = true, [21] = true, [22] = true} },
    fist = { itemClass = 2, itemSubclass = 13, inventoryTypes = {[13] = true, [21] = true, [22] = true} },
    axe_2h = { itemClass = 2, itemSubclass = 1, inventoryTypes = {[17] = true} },
    mace_2h = { itemClass = 2, itemSubclass = 5, inventoryTypes = {[17] = true} },
    sword_2h = { itemClass = 2, itemSubclass = 8, inventoryTypes = {[17] = true} },
    polearm = { itemClass = 2, itemSubclass = 6, inventoryTypes = {[17] = true} },
    staff = { itemClass = 2, itemSubclass = 10, inventoryTypes = {[17] = true} },
    shield = { itemClass = 4, itemSubclass = 6, inventoryTypes = {[14] = true} },
    relic = { itemClass = 4, itemSubclasses = {[7] = true, [8] = true, [9] = true, [10] = true}, inventoryTypes = {[28] = true} },
    bow = { itemClass = 2, itemSubclass = 2, inventoryTypes = {[15] = true} },
    crossbow = { itemClass = 2, itemSubclass = 18, inventoryTypes = {[26] = true} },
    gun = { itemClass = 2, itemSubclass = 3, inventoryTypes = {[26] = true} },
    wand = { itemClass = 2, itemSubclass = 19, inventoryTypes = {[26] = true} },
    thrown = { itemClass = 2, itemSubclass = 16, inventoryTypes = {[25] = true} },
}

local WEAPON_FILTER_KEYS_BY_SLOT = {
    [313] = {
        all = true, dagger = true, sword_1h = true, axe_1h = true, mace_1h = true, fist = true,
        sword_2h = true, axe_2h = true, mace_2h = true, polearm = true, staff = true,
    },
    [315] = {
        all = true, dagger = true, sword_1h = true, axe_1h = true, mace_1h = true, fist = true,
        sword_2h = true, axe_2h = true, mace_2h = true, shield = true,
    },
    [317] = {
        all = true, bow = true, crossbow = true, gun = true, wand = true, thrown = true, relic = true,
    },
}

local APPEARANCE_SET_SLOTS = {
    { name = "Head", slot = 283 },
    { name = "Shoulder", slot = 287 },
    { name = "Back", slot = 311 },
    { name = "Chest", slot = 291 },
    { name = "Shirt", slot = 289 },
    { name = "Tabard", slot = 319 },
    { name = "Wrist", slot = 299 },
    { name = "Hands", slot = 301 },
    { name = "Waist", slot = 293 },
    { name = "Legs", slot = 295 },
    { name = "Feet", slot = 297 },
    { name = "Main Hand", slot = 313 },
    { name = "Off-hand", slot = 315 },
    { name = "Ranged", slot = 317 },
}

local APPEARANCE_SET_INDEX_BY_SLOT = {}
for index, info in ipairs(APPEARANCE_SET_SLOTS) do
    APPEARANCE_SET_INDEX_BY_SLOT[info.slot] = index
end

local function NewEmptyAppearanceSetItemIds()
    local itemIds = {}
    for index in ipairs(APPEARANCE_SET_SLOTS) do
        itemIds[index] = 0
    end
    return itemIds
end

local function NormalizeAppearanceSetItemIds(itemIds)
    local normalized = NewEmptyAppearanceSetItemIds()
    if type(itemIds) ~= "table" then
        return normalized
    end
    for index in ipairs(APPEARANCE_SET_SLOTS) do
        local itemId = tonumber(itemIds[index])
        if itemId and itemId == itemId and itemId >= 0 and itemId <= 4294967295 then
            normalized[index] = math.floor(itemId)
        end
    end
    return normalized
end

-- One complete AppearanceBuddy outfit contains fourteen visible slots. At the
-- WotLK level cap, fourteen changed occupied slots should cost about 500 gold:
-- 36g each = 504g. A quartic curve keeps this cosmetic service affordable
-- while leveling on a stock 1x economy. Never use vendor price here: custom
-- and zero-price templates would make both quotes and charges inconsistent.
local TRANSMOG_MAX_LEVEL = 80
local TRANSMOG_MAX_SLOT_COST = 360000 -- 36 gold in copper
local TRANSMOG_MIN_SLOT_COST = 100 -- 1 silver in copper
local TRANSMOG_LEVEL_COST_POWER = 4
local EQUIPMENT_SLOT_TO_VISIBLE_SLOT = {
    [15] = 313,
    [16] = 315,
    [17] = 317,
}

-- Equipment inventory slots, not visible-item update fields.
local COSMETIC_WEAPON_ENCHANT_SLOTS = { 15, 16, 17 }
local COSMETIC_WEAPON_ENCHANT_SLOT_SET = { [15] = true, [16] = true, [17] = true }
local COSMETIC_WEAPON_ENCHANT_ID_SET = {
    [0] = true,
    [803] = true, [1894] = true, [1898] = true, [1899] = true, [1900] = true,
    [2671] = true, [2672] = true, [2673] = true, [2674] = true, [2675] = true,
    [3225] = true, [3239] = true, [3241] = true, [3273] = true, [3350] = true,
    [3368] = true, [3369] = true, [3370] = true, [3789] = true, [3790] = true,
    [3869] = true, [3870] = true,
}

local PERMANENT_ENCHANTMENT_SLOT = 0
local TEMPORARY_ENCHANTMENT_SLOT = 1

-- Boolean cache for explicit No Enchantment state. This keeps the spell/aura
-- hooks below from repeatedly querying character DB state for every player.
local NO_ENCHANT_VISUAL_ACTIVE_BY_PLAYER = {}
local NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING = {}
local NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING = {}

-- Stock WotLK temporary Shaman weapon-imbue enchant IDs.  They are checked
-- separately because oils, poisons, and other temporary effects use the same
-- item enchantment slot but must still be hidden by "No Enchantment".
local SHAMAN_IMBUE_ENCHANT_ID_SET = {
    [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
    [12] = true, [29] = true, [283] = true, [284] = true, [503] = true,
    [504] = true, [523] = true, [524] = true, [525] = true, [683] = true,
    [1663] = true, [1664] = true, [1665] = true, [1666] = true,
    [1667] = true, [1668] = true, [1669] = true, [2632] = true,
    [2633] = true, [2634] = true, [2635] = true, [2636] = true,
    [3345] = true, [3346] = true, [3347] = true, [3348] = true,
    [3349] = true, [3350] = true, [3779] = true, [3780] = true,
    [3781] = true, [3782] = true, [3783] = true, [3784] = true,
    [3785] = true, [3786] = true, [3787] = true,
}
for enchantId = 3018, 3044 do
    SHAMAN_IMBUE_ENCHANT_ID_SET[enchantId] = true
end

local ITEM_SET_ICON_SLOT_PRIORITY = {1, 2, 4, 8, 9, 10, 11, 7, 3, 5, 6, 12, 13, 14}

-- These helpers are defined below the account-catalog code, but pricing is
-- declared earlier. Forward declarations keep runtime equipment authoritative
-- without moving the large catalog section.
local CalculateSlotReverse
local GetEquippedItemId
local Transmog_Load
local FilterAppearanceRecords

local INVENTORY_TYPE_TO_SLOT_INDEX = {
    [1] = 1,
    [3] = 2,
    [16] = 3,
    [5] = 4,
    [20] = 4,
    [4] = 5,
    [19] = 6,
    [9] = 7,
    [10] = 8,
    [6] = 9,
    [7] = 10,
    [8] = 11,
    [13] = 12,
    [17] = 12,
    [21] = 12,
    [14] = 13,
    [22] = 13,
    [15] = 14,
    [25] = 14,
    [26] = 14,
    [28] = 14,
}

local function NormalizePage(page)
    page = tonumber(page)
    if not page or page ~= page or page <= -math.huge or page >= math.huge then
        page = 1
    end
    if page < 1 then
        page = 1
    end

    return math.floor(page)
end

local function NormalizePageSize(pageSize)
    pageSize = tonumber(pageSize)
    if not pageSize or pageSize ~= pageSize or pageSize <= -math.huge or pageSize >= math.huge then
        pageSize = SLOTS
    end
    pageSize = math.floor(pageSize)
    if pageSize < 1 then
        pageSize = 1
    elseif pageSize > 50 then
        pageSize = 50
    end

    return pageSize
end

local function NormalizeAppearancePageRequestToken(requestToken)
    local tokenType = type(requestToken)
    if tokenType == "string" then
        if #requestToken > 10 or not requestToken:match("^%d+$") then
            return nil
        end
    elseif tokenType ~= "number" then
        return nil
    end
    requestToken = tonumber(requestToken)
    if not requestToken or requestToken ~= requestToken
        or requestToken < 0 or requestToken >= math.huge
        or requestToken ~= math.floor(requestToken)
        or requestToken > 2147483647 then
        return nil
    end
    return requestToken
end

local function EscapeString(str)
    if not str then return "" end
    return str:gsub("'", "''"):gsub("\\", "\\\\")
end

local function NormalizeVisibleSlot(slot)
    slot = tonumber(slot)
    if not slot or slot ~= slot or slot <= -math.huge or slot >= math.huge then
        return nil
    end

    slot = math.floor(slot)
    if not VISIBLE_SLOT_SET[slot] then
        return nil
    end

    return slot
end

local function NormalizeWeaponFilter(slot, weaponFilter)
    local allowedKeys = WEAPON_FILTER_KEYS_BY_SLOT[slot]
    if not allowedKeys then
        return "all"
    end

    local key = string.lower(tostring(weaponFilter or "all"))
    return allowedKeys[key] and key or "all"
end

-- WotLK 3.3.5a class equipment policy. Weapon families intentionally describe
-- what a class can train, not only what a new character already knows. Hand
-- restrictions remain live because an off-hand weapon or a Titan's Grip look
-- is only valid while the character has the required dual-wield capability.
local AppearanceEligibility = {}
do
local WARRIOR_CLASS_ID = 1
local PALADIN_CLASS_ID = 2
local HUNTER_CLASS_ID = 3
local ROGUE_CLASS_ID = 4
local PRIEST_CLASS_ID = 5
local DEATH_KNIGHT_CLASS_ID = 6
local SHAMAN_CLASS_ID = 7
local MAGE_CLASS_ID = 8
local WARLOCK_CLASS_ID = 9
local DRUID_CLASS_ID = 11

local ARMOR_SUBCLASS_MISC = 0
local ARMOR_SUBCLASS_CLOTH = 1
local ARMOR_SUBCLASS_LEATHER = 2
local ARMOR_SUBCLASS_MAIL = 3
local ARMOR_SUBCLASS_PLATE = 4
local ARMOR_SUBCLASS_SHIELD = 6
local ARMOR_SUBCLASS_LIBRAM = 7
local ARMOR_SUBCLASS_IDOL = 8
local ARMOR_SUBCLASS_TOTEM = 9
local ARMOR_SUBCLASS_SIGIL = 10

local WEAPON_SUBCLASS_BY_CLASS = {
    [WARRIOR_CLASS_ID] = {[0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [2] = true, [3] = true, [16] = true, [18] = true},
    [PALADIN_CLASS_ID] = {[0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true},
    [HUNTER_CLASS_ID] = {[0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [2] = true, [3] = true, [16] = true, [18] = true},
    [ROGUE_CLASS_ID] = {[0] = true, [4] = true, [7] = true, [13] = true, [15] = true, [2] = true, [3] = true, [16] = true, [18] = true},
    [PRIEST_CLASS_ID] = {[4] = true, [10] = true, [15] = true, [19] = true},
    [DEATH_KNIGHT_CLASS_ID] = {[0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true},
    [SHAMAN_CLASS_ID] = {[0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true},
    [MAGE_CLASS_ID] = {[7] = true, [10] = true, [15] = true, [19] = true},
    [WARLOCK_CLASS_ID] = {[7] = true, [10] = true, [15] = true, [19] = true},
    [DRUID_CLASS_ID] = {[4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true},
}

local ARMOR_SUBCLASS_BY_CLASS = {
    [WARRIOR_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true, [ARMOR_SUBCLASS_MAIL] = true, [ARMOR_SUBCLASS_PLATE] = true},
    [PALADIN_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true, [ARMOR_SUBCLASS_MAIL] = true, [ARMOR_SUBCLASS_PLATE] = true},
    [HUNTER_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true, [ARMOR_SUBCLASS_MAIL] = true},
    [ROGUE_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true},
    [PRIEST_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true},
    [DEATH_KNIGHT_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true, [ARMOR_SUBCLASS_MAIL] = true, [ARMOR_SUBCLASS_PLATE] = true},
    [SHAMAN_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true, [ARMOR_SUBCLASS_MAIL] = true},
    [MAGE_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true},
    [WARLOCK_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true},
    [DRUID_CLASS_ID] = {[ARMOR_SUBCLASS_CLOTH] = true, [ARMOR_SUBCLASS_LEATHER] = true},
}

local SHIELD_CLASS_SET = {
    [WARRIOR_CLASS_ID] = true,
    [PALADIN_CLASS_ID] = true,
    [SHAMAN_CLASS_ID] = true,
}

local RELIC_SUBCLASS_BY_CLASS = {
    [PALADIN_CLASS_ID] = ARMOR_SUBCLASS_LIBRAM,
    [DEATH_KNIGHT_CLASS_ID] = ARMOR_SUBCLASS_SIGIL,
    [SHAMAN_CLASS_ID] = ARMOR_SUBCLASS_TOTEM,
    [DRUID_CLASS_ID] = ARMOR_SUBCLASS_IDOL,
}

local SHAMAN_DUAL_WIELD_SPELL = 30798
local TITANS_GRIP_SPELL = 46917
local TITANS_GRIP_WEAPON_SUBCLASS_SET = {[1] = true, [5] = true, [8] = true}

local function GetPlayerAppearanceClass(player)
    if not player or type(player.GetClass) ~= "function" then
        return nil
    end

    local ok, classId = pcall(player.GetClass, player)
    classId = ok and tonumber(classId) or nil
    if not classId or classId ~= math.floor(classId) or not WEAPON_SUBCLASS_BY_CLASS[classId] then
        return nil
    end
    return classId
end

local function GetPlayerAppearanceLevel(player)
    if not player or type(player.GetLevel) ~= "function" then
        return nil
    end

    local ok, level = pcall(player.GetLevel, player)
    level = ok and tonumber(level) or nil
    if not level or level ~= level or level <= -math.huge or level >= math.huge then
        return nil
    end
    return math.max(1, math.floor(level))
end

local function PlayerKnowsAppearanceSpell(player, spellId)
    if not player or type(player.HasSpell) ~= "function" then
        return false
    end

    local ok, known = pcall(player.HasSpell, player, spellId)
    return ok and (known == true or known == 1)
end

local function CanClassDualWield(player, classId, level)
    if classId == ROGUE_CLASS_ID then
        return true
    end
    if classId == DEATH_KNIGHT_CLASS_ID then
        return level >= 55
    end
    if classId == HUNTER_CLASS_ID or classId == WARRIOR_CLASS_ID then
        return level >= 20
    end
    return classId == SHAMAN_CLASS_ID
        and level >= 40
        and PlayerKnowsAppearanceSpell(player, SHAMAN_DUAL_WIELD_SPELL)
end

local function CanUseTitansGrip(player, classId, level)
    return classId == WARRIOR_CLASS_ID
        and level >= 60
        and PlayerKnowsAppearanceSpell(player, TITANS_GRIP_SPELL)
end

local function GetAppearanceEligibilityContext(player)
    local classId = GetPlayerAppearanceClass(player)
    local level = GetPlayerAppearanceLevel(player)
    if not classId or not level then
        return nil
    end

    return {
        classId = classId,
        level = level,
        canDualWield = CanClassDualWield(player, classId, level),
        canUseTitansGrip = CanUseTitansGrip(player, classId, level),
    }
end

local function IsArmorSubclassAllowed(context, itemSubclass)
    local classId = context.classId
    local allowed = ARMOR_SUBCLASS_BY_CLASS[classId]
    if not allowed or not allowed[itemSubclass] then
        return false
    end
    if itemSubclass == ARMOR_SUBCLASS_MAIL
        and (classId == HUNTER_CLASS_ID or classId == SHAMAN_CLASS_ID) then
        return context.level >= 40
    end
    if itemSubclass == ARMOR_SUBCLASS_PLATE
        and (classId == WARRIOR_CLASS_ID or classId == PALADIN_CLASS_ID) then
        return context.level >= 40
    end
    return classId ~= DEATH_KNIGHT_CLASS_ID or context.level >= 55
end

local function IsAppearanceAllowedForPlayer(player, visibleSlot, itemTemplate, context)
    visibleSlot = NormalizeVisibleSlot(visibleSlot)
    if not visibleSlot or type(itemTemplate) ~= "table" then
        return false
    end

    context = context or GetAppearanceEligibilityContext(player)
    if not context then
        return false
    end

    -- An account-wide unlock is not an entitlement to use an appearance before
    -- this character could equip its source item.  Keep this gate central so
    -- catalog pages, saved outfits, direct AIO calls, and state reconciliation
    -- all apply the same item_template.RequiredLevel rule.
    local requiredLevel = tonumber(itemTemplate.requiredLevel)
    if requiredLevel == nil then
        requiredLevel = 0
    end
    if requiredLevel ~= requiredLevel
        or requiredLevel <= -math.huge or requiredLevel >= math.huge
        or requiredLevel < 0 or requiredLevel ~= math.floor(requiredLevel)
        or context.level < requiredLevel then
        return false
    end

    local inventoryType = tonumber(itemTemplate.inventoryType)
    local itemClass = tonumber(itemTemplate.itemClass)
    local itemSubclass = tonumber(itemTemplate.itemSubclass)
    local allowedInventoryTypes = SLOT_INVENTORY_TYPES[visibleSlot]
    if not inventoryType or not itemClass or not itemSubclass
        or not allowedInventoryTypes or not allowedInventoryTypes[inventoryType] then
        return false
    end

    if itemClass == 4 then
        if visibleSlot == 311 then
            return inventoryType == 16 -- cloaks are usable by every class
        end
        if visibleSlot == 289 then
            return inventoryType == 4 and itemSubclass == 0 -- shirts
        end
        if visibleSlot == 319 then
            return inventoryType == 19 and itemSubclass == 0 -- tabards
        end
        if visibleSlot == 315 then
            return inventoryType == 14
                and itemSubclass == ARMOR_SUBCLASS_SHIELD
                and SHIELD_CLASS_SET[context.classId] == true
        end
        if visibleSlot == 317 then
            return inventoryType == 28
                and RELIC_SUBCLASS_BY_CLASS[context.classId] == itemSubclass
        end
        -- Imported cosmetic armor uses the WotLK miscellaneous armor subclass.
        -- Shield and relic slots have already been restricted above.
        if itemSubclass == ARMOR_SUBCLASS_MISC then
            return true
        end
        return IsArmorSubclassAllowed(context, itemSubclass)
    end

    if itemClass ~= 2 or not (WEAPON_SUBCLASS_BY_CLASS[context.classId] or {})[itemSubclass] then
        return false
    end
    if visibleSlot == 313 then
        return inventoryType == 13 or inventoryType == 17 or inventoryType == 21
    end
    if visibleSlot == 315 then
        if inventoryType == 17 then
            return context.canUseTitansGrip and TITANS_GRIP_WEAPON_SUBCLASS_SET[itemSubclass] == true
        end
        return (inventoryType == 13 or inventoryType == 22) and context.canDualWield
    end
    return visibleSlot == 317
        and (inventoryType == 15 or inventoryType == 25 or inventoryType == 26)
end

local function GetAppearanceEligibilityCacheKey(context)
    if not context then
        return nil
    end
    return table.concat({
        tostring(context.classId),
        tostring(context.level),
        context.canDualWield and "dw" or "nodw",
        context.canUseTitansGrip and "tg" or "notg",
    }, ":")
end

AppearanceEligibility.ShamanClassId = SHAMAN_CLASS_ID
AppearanceEligibility.GetContext = GetAppearanceEligibilityContext
AppearanceEligibility.Allows = IsAppearanceAllowedForPlayer
AppearanceEligibility.GetCacheKey = GetAppearanceEligibilityCacheKey
end

-- Bootstrap only the absent persistence tables while the script loads. This
-- makes a missing or failed packaged migration recover on the next startup
-- without touching data in an existing table. Non-additive legacy repairs
-- remain an offline operation so a gameplay script never rewrites player data.
local CHARACTER_SCHEMA_MIGRATION_FILE = "migrations/2026_07_20_appearancebuddy_characters.sql"
local AUTH_SCHEMA_MIGRATION_FILE = "migrations/2026_07_20_appearancebuddy_auth.sql"
local TRANSMOG_SCHEMA_AUTO_BOOTSTRAP_ENABLED = true
local TRANSMOG_PERSISTENCE_SCHEMA_READY = false
local REQUIRED_TRANSMOG_TABLE_COLUMNS = {
    account_transmog = {
        account_id = { kind = "unsigned_integer", minBits = 32, nullable = false },
        unlocked_item_id = { kind = "unsigned_integer", minBits = 32, nullable = false },
        display_id = { kind = "unsigned_integer", minBits = 32, nullable = false },
        inventory_type = { kind = "unsigned_integer", minBits = 8 },
        item_name = { kind = "string", minLength = 255 },
    },
    account_transmog_removed_appearance = {
        account_id = { kind = "unsigned_integer", minBits = 32, nullable = false },
        display_id = { kind = "unsigned_integer", minBits = 32, nullable = false },
    },
    character_transmog = {
        player_guid = { kind = "unsigned_integer", minBits = 32, nullable = false },
        slot = { kind = "unsigned_integer", minBits = 16, nullable = false },
        item = { kind = "unsigned_integer", minBits = 32, nullable = true },
        real_item = { kind = "unsigned_integer", minBits = 32 },
    },
    character_transmog_weapon_enchant = {
        player_guid = { kind = "unsigned_integer", minBits = 32, nullable = false },
        equipment_slot = { kind = "unsigned_integer", minBits = 8, nullable = false },
        enchant_id = { kind = "unsigned_integer", minBits = 16, nullable = false },
    },
}
local MYSQL_UNSIGNED_INTEGER_BITS = {
    tinyint = 8,
    smallint = 16,
    mediumint = 24,
    int = 32,
    integer = 32,
    bigint = 64,
}
local MYSQL_TEXT_TYPES = {
    tinytext = true,
    text = true,
    mediumtext = true,
    longtext = true,
}
local TRANSMOG_PERSISTENCE_TABLES = {
    {
        databaseLabel = "auth",
        queryFunction = AuthDBQuery,
        sentinelTableName = "account",
        tableName = "account_transmog",
        firstKeyColumn = "account_id",
        secondKeyColumn = "unlocked_item_id",
        createStatement = [[
CREATE TABLE IF NOT EXISTS `account_transmog` (
    `account_id` INT UNSIGNED NOT NULL,
    `unlocked_item_id` INT UNSIGNED NOT NULL,
    `display_id` INT UNSIGNED NOT NULL,
    `inventory_type` INT UNSIGNED NULL,
    `item_name` VARCHAR(255) NULL,
    PRIMARY KEY (`account_id`, `unlocked_item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
    },
    {
        databaseLabel = "auth",
        queryFunction = AuthDBQuery,
        sentinelTableName = "account",
        tableName = "account_transmog_removed_appearance",
        firstKeyColumn = "account_id",
        secondKeyColumn = "display_id",
        createStatement = [[
CREATE TABLE IF NOT EXISTS `account_transmog_removed_appearance` (
    `account_id` INT UNSIGNED NOT NULL,
    `display_id` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `display_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
    },
    {
        databaseLabel = "characters",
        queryFunction = CharDBQuery,
        sentinelTableName = "characters",
        tableName = "character_transmog",
        firstKeyColumn = "player_guid",
        secondKeyColumn = "slot",
        createStatement = [[
CREATE TABLE IF NOT EXISTS `character_transmog` (
    `player_guid` INT UNSIGNED NOT NULL,
    `slot` SMALLINT UNSIGNED NOT NULL,
    `item` INT UNSIGNED NULL,
    `real_item` INT UNSIGNED NULL,
    PRIMARY KEY (`player_guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
    },
    {
        databaseLabel = "characters",
        queryFunction = CharDBQuery,
        sentinelTableName = "characters",
        tableName = "character_transmog_weapon_enchant",
        firstKeyColumn = "player_guid",
        secondKeyColumn = "equipment_slot",
        createStatement = [[
CREATE TABLE IF NOT EXISTS `character_transmog_weapon_enchant` (
    `player_guid` INT UNSIGNED NOT NULL,
    `equipment_slot` TINYINT UNSIGNED NOT NULL,
    `enchant_id` SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (`player_guid`, `equipment_slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]],
    },
}

local function DatabaseTableExists(queryFunction, tableName)
    if type(queryFunction) ~= "function" then
        return false
    end
    local ok, query = pcall(queryFunction,
        "SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '"
        .. tableName .. "' LIMIT 1"
    )
    return ok and query ~= nil
end

local function DatabaseColumnMatchesRequirement(column, requirement)
    if not column or not requirement then
        return false
    end
    local columnType = string.lower(tostring(column.columnType or ""))
    local isNullable = column.isNullable == true
    if requirement.nullable ~= nil and isNullable ~= requirement.nullable then
        return false
    end
    if requirement.kind == "unsigned_integer" then
        local integerType = columnType:match("^([a-z]+)") or ""
        local typeBits = MYSQL_UNSIGNED_INTEGER_BITS[integerType] or 0
        return typeBits >= (tonumber(requirement.minBits) or 1)
            and columnType:find("unsigned", 1, true) ~= nil
    end
    if requirement.kind == "string" then
        local stringType = columnType:match("^([a-z]+)") or ""
        if MYSQL_TEXT_TYPES[stringType] then
            return true
        end
        local length = 0
        if stringType == "varchar" or stringType == "char" then
            length = tonumber(columnType:match("^[a-z]+%((%d+)%)")) or 0
        end
        return length >= (tonumber(requirement.minLength) or 1)
    end
    return false
end

local function DatabaseTableHasRequiredColumns(queryFunction, tableName)
    local requirements = REQUIRED_TRANSMOG_TABLE_COLUMNS[tableName]
    if not requirements or not DatabaseTableExists(queryFunction, tableName) then
        return false
    end
    local ok, query = pcall(queryFunction,
        "SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE FROM information_schema.COLUMNS "
        .. "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '" .. tableName .. "'"
    )
    if not ok or not query then
        return false
    end

    local columns = {}
    repeat
        local columnName = query:GetString(0) or ""
        if columnName ~= "" then
            columns[columnName] = {
                columnType = query:GetString(1) or "",
                isNullable = string.upper(query:GetString(2) or "") == "YES",
            }
        end
    until not query:NextRow()

    for columnName, requirement in pairs(requirements) do
        if not DatabaseColumnMatchesRequirement(columns[columnName], requirement) then
            return false
        end
    end
    return true
end

local function DatabaseTableHasUniqueKey(queryFunction, tableName, firstColumn, secondColumn)
    if not REQUIRED_TRANSMOG_TABLE_COLUMNS[tableName] or not DatabaseTableExists(queryFunction, tableName) then
        return false
    end
    local ok, query = pcall(queryFunction,
        "SELECT NON_UNIQUE, INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME FROM information_schema.STATISTICS "
        .. "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '" .. tableName .. "'"
    )
    if not ok or not query then
        return false
    end

    local indexes = {}
    repeat
        local nonUnique = tonumber(query:GetUInt32(0)) or 1
        local keyName = query:GetString(1) or ""
        local sequence = tonumber(query:GetUInt32(2)) or 0
        local columnName = query:GetString(3) or ""
        if nonUnique == 0 and keyName ~= "" and sequence > 0 then
            indexes[keyName] = indexes[keyName] or {}
            indexes[keyName][sequence] = columnName
        end
    until not query:NextRow()

    for _, columns in pairs(indexes) do
        if columns[1] == firstColumn and columns[2] == secondColumn and columns[3] == nil then
            return true
        end
    end
    return false
end

local function GetTransmogPersistenceSchemaHealth()
    local missingTables = {}
    local incompatible = {}
    local missingKeys = {}
    for _, definition in ipairs(TRANSMOG_PERSISTENCE_TABLES) do
        if not DatabaseTableExists(definition.queryFunction, definition.tableName) then
            missingTables[#missingTables + 1] = definition.databaseLabel .. "." .. definition.tableName
        elseif not DatabaseTableHasRequiredColumns(definition.queryFunction, definition.tableName) then
            incompatible[#incompatible + 1] = definition.databaseLabel .. "." .. definition.tableName
        elseif not DatabaseTableHasUniqueKey(
            definition.queryFunction,
            definition.tableName,
            definition.firstKeyColumn,
            definition.secondKeyColumn
        ) then
            missingKeys[#missingKeys + 1] = definition.databaseLabel .. "." .. definition.tableName
        end
    end
    return missingTables, incompatible, missingKeys
end

local function RunTransmogSchemaBootstrap()
    if not TRANSMOG_SCHEMA_AUTO_BOOTSTRAP_ENABLED then
        return false
    end

    local attempted = false
    for _, definition in ipairs(TRANSMOG_PERSISTENCE_TABLES) do
        local isMissing = not DatabaseTableExists(definition.queryFunction, definition.tableName)
        if not isMissing then
            -- Existing legacy tables are deliberately untouched. The offline
            -- migration retains its backup/rebuild path for those cases.
        elseif type(definition.queryFunction) ~= "function" then
            print(string.format(
                "[AppearanceBuddy Transmog] ERROR: %s database query API is unavailable; cannot auto-create %s.",
                definition.databaseLabel,
                definition.tableName
            ))
        elseif not DatabaseTableExists(definition.queryFunction, definition.sentinelTableName) then
            print(string.format(
                "[AppearanceBuddy Transmog] ERROR: %s database is missing its `%s` sentinel; refusing to auto-create %s there.",
                definition.databaseLabel,
                definition.sentinelTableName,
                definition.tableName
            ))
        else
            attempted = true
            local ok, errorMessage = pcall(definition.queryFunction, definition.createStatement)
            if not ok then
                print(string.format(
                    "[AppearanceBuddy Transmog] ERROR: automatic creation of %s.%s failed: %s",
                    definition.databaseLabel,
                    definition.tableName,
                    tostring(errorMessage)
                ))
            end
        end
    end
    return attempted
end

local function RefreshTransmogPersistenceSchemaReadiness()
    local missingTables, incompatible, missingKeys = GetTransmogPersistenceSchemaHealth()
    if #missingTables > 0 or #incompatible > 0 or #missingKeys > 0 then
        RunTransmogSchemaBootstrap()
        missingTables, incompatible, missingKeys = GetTransmogPersistenceSchemaHealth()
    end

    TRANSMOG_PERSISTENCE_SCHEMA_READY = #missingTables == 0 and #incompatible == 0 and #missingKeys == 0
    if #missingTables > 0 then
        print(string.format(
            "[AppearanceBuddy Transmog] ERROR: required tables are still missing (%s). Automatic setup could not verify them; check database routing and CREATE TABLE permission, or apply %s and %s offline.",
            table.concat(missingTables, ", "),
            AUTH_SCHEMA_MIGRATION_FILE,
            CHARACTER_SCHEMA_MIGRATION_FILE
        ))
    elseif #incompatible > 0 then
        print(string.format(
            "[AppearanceBuddy Transmog] ERROR: required tables are unavailable or have incompatible columns (%s). Automatic setup creates only missing tables; apply %s offline to repair existing legacy tables.",
            table.concat(incompatible, ", "),
            AUTH_SCHEMA_MIGRATION_FILE .. " and " .. CHARACTER_SCHEMA_MIGRATION_FILE
        ))
    elseif #missingKeys > 0 then
        print(string.format(
            "[AppearanceBuddy Transmog] WARNING: required composite unique keys are missing from %s. Automatic setup does not alter existing tables; paid mutations are disabled. Apply %s and %s offline.",
            table.concat(missingKeys, ", "),
            AUTH_SCHEMA_MIGRATION_FILE,
            CHARACTER_SCHEMA_MIGRATION_FILE
        ))
    end
    return TRANSMOG_PERSISTENCE_SCHEMA_READY
end

RefreshTransmogPersistenceSchemaReadiness()

local ITEM_TEMPLATE_CACHE = {}
local ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER = {}
local ITEM_TEMPLATE_NEGATIVE_CACHE_MAX = 2048
local ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR = 1
local ITEM_SET_TEMPLATE_CACHE = {}
local VIRTUAL_SET_TEMPLATE_CACHE = {}
local ACCOUNT_APPEARANCE_CACHE = {}
local ITEM_SET_CATALOG_SERVICE
local ACCOUNT_REMOVED_APPEARANCE_CACHE = {}
local RANDOM_PREVIEW_NEXT_ALLOWED_BY_PLAYER = {}
local RANDOM_PREVIEW_MIN_INTERVAL_SECONDS = 0.75
local APPEARANCE_MUTATION_ACTIVE_BY_PLAYER = {}
local APPEARANCE_MUTATION_NEXT_ALLOWED_BY_PLAYER = {}
local APPEARANCE_MUTATION_MIN_INTERVAL_SECONDS = 0.25
local INVENTORY_SCAN_NEXT_ALLOWED_BY_PLAYER = {}
local INVENTORY_SCAN_MIN_INTERVAL_SECONDS = 5
local COSMETIC_WEAPON_ENCHANT_CACHE_BY_PLAYER = {}
local EXPENSIVE_REQUEST_BUDGET_BY_PLAYER = {}
local FREE_TRANSMOG_ENABLED_BY_PLAYER = {}
local PLAYER_TRANSMOG_HYDRATED = {}
local LOGIN_TRANSMOG_RESTORE_PENDING = {}
local ONLINE_PLAYER_GUIDS_BY_ACCOUNT = {}
local EXPENSIVE_REQUEST_BUDGET_CAPACITY = 12
local EXPENSIVE_REQUEST_BUDGET_REFILL_PER_SECOND = 4
local APPEARANCE_PAGE_ERROR_RATE_LIMITED = "RATE_LIMITED"

local function CacheMissingItemTemplate(itemId)
    itemId = tonumber(itemId)
    if not itemId or ITEM_TEMPLATE_CACHE[itemId] ~= nil then
        return
    end

    if #ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER < ITEM_TEMPLATE_NEGATIVE_CACHE_MAX then
        ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER[#ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER + 1] = itemId
    else
        local evicted = ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER[ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR]
        if ITEM_TEMPLATE_CACHE[evicted] == false then
            ITEM_TEMPLATE_CACHE[evicted] = nil
        end
        ITEM_TEMPLATE_NEGATIVE_CACHE_ORDER[ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR] = itemId
        ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR = ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR + 1
        if ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR > ITEM_TEMPLATE_NEGATIVE_CACHE_MAX then
            ITEM_TEMPLATE_NEGATIVE_CACHE_CURSOR = 1
        end
    end
    ITEM_TEMPLATE_CACHE[itemId] = false
end

-- Playerbots do not have an AppearanceBuddy client and must not hydrate or
-- mutate cosmetic state. IsBot is optional on older cores, so absence (or an
-- engine-side exception) preserves normal-player compatibility.
local function IsAppearanceBuddyPlayer(player)
    if not player then
        return false
    end

    if type(player.IsBot) == "function" then
        local ok, isBot = pcall(player.IsBot, player)
        if ok and (isBot == true or tonumber(isBot) == 1) then
            return false
        end
    end

    return true
end

local function GetServerTimestamp()
    -- GetCurrTime is the millisecond timer exposed by the server Lua engine.
    -- Fall back to game time only if that API is unavailable.
    if type(GetCurrTime) == "function" then
        local ok, value = pcall(GetCurrTime)
        value = ok and tonumber(value) or nil
        if value and value > 0 then
            return value / 1000, "uptime"
        end
    end

    if type(GetGameTime) == "function" then
        local ok, value = pcall(GetGameTime)
        value = ok and tonumber(value) or nil
        if value and value > 0 then
            return value, "game"
        end
    end

    if os and type(os.time) == "function" then
        return tonumber(os.time()) or 0, "wall"
    end

    return 0, nil
end

local function ConsumeExpensiveRequestBudget(player, cost)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow then
        return false, 0
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    if not playerGUID then
        return false, 0
    end

    cost = math.max(1, math.floor(tonumber(cost) or 1))
    local now = GetServerTimestamp()
    if now <= 0 then
        -- A missing clock must not permanently lock a legitimate client out.
        return true, 0
    end

    local budget = EXPENSIVE_REQUEST_BUDGET_BY_PLAYER[playerGUID]
    if not budget then
        budget = { tokens = EXPENSIVE_REQUEST_BUDGET_CAPACITY, updatedAt = now }
        EXPENSIVE_REQUEST_BUDGET_BY_PLAYER[playerGUID] = budget
    else
        local elapsed = math.max(0, math.min(60, now - (tonumber(budget.updatedAt) or now)))
        budget.tokens = math.min(
            EXPENSIVE_REQUEST_BUDGET_CAPACITY,
            (tonumber(budget.tokens) or 0) + elapsed * EXPENSIVE_REQUEST_BUDGET_REFILL_PER_SECOND
        )
        budget.updatedAt = now
    end

    if budget.tokens < cost then
        return false, (cost - budget.tokens) / EXPENSIVE_REQUEST_BUDGET_REFILL_PER_SECOND
    end

    budget.tokens = budget.tokens - cost
    return true, 0
end

local function BeginRandomAppearancePreview(player)
    if not player or not player.GetGUIDLow then
        return false, 0
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    if not playerGUID then
        return false, 0
    end

    local now = GetServerTimestamp()
    if now <= 0 then
        -- Do not turn a missing timer API into a permanent lockout.
        return true, 0
    end

    local nextAllowed = tonumber(RANDOM_PREVIEW_NEXT_ALLOWED_BY_PLAYER[playerGUID]) or 0
    if now < nextAllowed then
        local retryAfter = nextAllowed - now
        -- The millisecond clock can wrap or be reset by a server restart.
        -- Never turn that discontinuity into a long-lived player lockout.
        if retryAfter <= RANDOM_PREVIEW_MIN_INTERVAL_SECONDS * 2 then
            return false, retryAfter
        end
    end

    RANDOM_PREVIEW_NEXT_ALLOWED_BY_PLAYER[playerGUID] = now + RANDOM_PREVIEW_MIN_INTERVAL_SECONDS
    return true, 0
end

local function InvalidateAccountCaches(accountGUID, includeRemovedAppearances)
    accountGUID = tonumber(accountGUID)
    if not accountGUID then
        return
    end

    ACCOUNT_APPEARANCE_CACHE[accountGUID] = nil
    if ITEM_SET_CATALOG_SERVICE then
        ITEM_SET_CATALOG_SERVICE.Invalidate(
            accountGUID,
            "The item-set collection changed while it was loading. Please try again."
        )
    end
    if includeRemovedAppearances then
        ACCOUNT_REMOVED_APPEARANCE_CACHE[accountGUID] = nil
    end
end

local function TrackAppearanceBuddyPlayerOnline(player)
    if not IsAppearanceBuddyPlayer(player) or not player.GetAccountId
        or not player.GetGUIDLow or not player.GetGUID then
        return
    end
    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    local guidLowOK, playerGUIDLow = pcall(player.GetGUIDLow, player)
    local guidOK, playerGUID = pcall(player.GetGUID, player)
    accountGUID = accountOK and tonumber(accountGUID) or nil
    playerGUIDLow = guidLowOK and tonumber(playerGUIDLow) or nil
    playerGUID = guidOK and playerGUID or nil
    if not accountGUID or not playerGUIDLow or playerGUID == nil then
        return
    end
    local onlineGUIDs = ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID]
    if not onlineGUIDs then
        onlineGUIDs = {}
        ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID] = onlineGUIDs
    end
    -- GetPlayerByGUID expects the full ObjectGuid, while logout/cache keys use
    -- the database GUIDLow. Keep both identities instead of conflating them.
    onlineGUIDs[playerGUIDLow] = playerGUID
end

local function EvictAccountCachesIfUnused(accountGUID, playerGUID)
    accountGUID = tonumber(accountGUID)
    playerGUID = tonumber(playerGUID)
    if not accountGUID or accountGUID <= 0 then
        return
    end

    local onlineGUIDs = ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID]
    if onlineGUIDs and playerGUID then
        onlineGUIDs[playerGUID] = nil
        if next(onlineGUIDs) ~= nil then
            return
        end
    end

    ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID] = nil
    InvalidateAccountCaches(accountGUID, true)
end

local function GetAccountRemovedAppearanceCache(accountGUID)
    accountGUID = tonumber(accountGUID)
    if not accountGUID or accountGUID <= 0 then
        return {}, false
    end

    local cached = ACCOUNT_REMOVED_APPEARANCE_CACHE[accountGUID]
    if cached then
        return cached, true
    end

    local removed = {}
    local query = AuthDBQuery(string.format(
        "SELECT display_id FROM account_transmog_removed_appearance WHERE account_id = %u",
        accountGUID
    ))
    if query then
        repeat
            local displayId = tonumber(query:GetUInt32(0)) or 0
            if displayId > 0 then
                removed[displayId] = true
            end
        until not query:NextRow()
    else
        -- A result-less SELECT is also how Eluna represents an empty set.
        -- Confirm the table is reachable before caching "no tombstones";
        -- otherwise a transient auth DB failure could resurrect a revoked look.
        local countQuery = AuthDBQuery(string.format(
            "SELECT COUNT(*) FROM account_transmog_removed_appearance WHERE account_id = %u",
            accountGUID
        ))
        if not countQuery or (tonumber(countQuery:GetUInt32(0)) or -1) ~= 0 then
            return removed, false
        end
    end

    ACCOUNT_REMOVED_APPEARANCE_CACHE[accountGUID] = removed
    return removed, true
end

local function IsAccountAppearanceRemoved(accountGUID, displayId)
    displayId = tonumber(displayId)
    if not displayId or displayId ~= math.floor(displayId) or displayId <= 0 then
        return false, true
    end

    local removed, loadSucceeded = GetAccountRemovedAppearanceCache(accountGUID)
    if not loadSucceeded then
        return nil, false
    end
    return removed[displayId] == true, true
end

local function CreateAccountAppearanceCache(accountGUID)
    local cache = {
        accountId = tonumber(accountGUID) or 0,
        all = {},
        byItemId = {},
        bySlot = {},
        bySlotIndex = {},
        bySlotDisplay = {},
        bySlotFilter = {},
        itemMetadataLoadedBySlot = {},
        eligibleRecordsByPolicy = {},
        eligibleRecordPolicyOrder = {},
        loadSucceeded = false,
    }

    for _, slot in ipairs(VISIBLE_SLOTS) do
        cache.bySlot[slot] = {}
        cache.bySlotIndex[slot] = {}
        cache.bySlotDisplay[slot] = {}
        cache.bySlotFilter[slot] = {}
    end

    return cache
end

local function AddAccountAppearanceRecord(cache, record)
    table.insert(cache.all, record)
    cache.byItemId[record.itemId] = true

    for _, slot in ipairs(VISIBLE_SLOTS_BY_INVENTORY_TYPE[record.inventoryType] or {}) do
        local slotRecords = cache.bySlot[slot]
        table.insert(slotRecords, record)
        cache.bySlotIndex[slot][record.itemId] = #slotRecords

        if record.displayId > 0 then
            local displayBucket = cache.bySlotDisplay[slot][record.displayId]
            if not displayBucket then
                displayBucket = {
                    firstItemId = record.itemId,
                    items = {},
                }
                cache.bySlotDisplay[slot][record.displayId] = displayBucket
            elseif record.itemId < displayBucket.firstItemId then
                displayBucket.firstItemId = record.itemId
            end

            displayBucket.items[record.itemId] = true
        end
    end
end

local function GetAccountAppearanceCache(accountGUID)
    accountGUID = tonumber(accountGUID)
    if not accountGUID or accountGUID <= 0 then
        return CreateAccountAppearanceCache(0)
    end

    local cached = ACCOUNT_APPEARANCE_CACHE[accountGUID]
    if cached then
        return cached
    end

    local cache = CreateAccountAppearanceCache(accountGUID)
    local removedAppearances, removedLoadSucceeded = GetAccountRemovedAppearanceCache(accountGUID)
    if not removedLoadSucceeded then
        return cache
    end
    local unlockedItems = AuthDBQuery(string.format(
        "SELECT unlocked_item_id, display_id, COALESCE(inventory_type, 0), COALESCE(item_name, '') FROM account_transmog WHERE account_id = %d ORDER BY unlocked_item_id",
        accountGUID
    ))

    if unlockedItems then
        repeat
            local itemId = tonumber(unlockedItems:GetUInt32(0)) or 0
            local displayId = tonumber(unlockedItems:GetUInt32(1)) or 0
            local inventoryType = tonumber(unlockedItems:GetUInt32(2)) or 0
            local itemName = unlockedItems:GetString(3) or ""

            if itemId > 0 and not removedAppearances[displayId] then
                cache.byItemId[itemId] = true
            end

            if itemId > 0 and inventoryType > 0 and not removedAppearances[displayId] then
                AddAccountAppearanceRecord(cache, {
                    itemId = itemId,
                    displayId = displayId,
                    inventoryType = inventoryType,
                    itemName = itemName,
                    lowerName = string.lower(itemName),
                })
            end
        until not unlockedItems:NextRow()
    else
        local countQuery = AuthDBQuery(string.format(
            "SELECT COUNT(*) FROM account_transmog WHERE account_id = %u",
            accountGUID
        ))
        if not countQuery or (tonumber(countQuery:GetUInt32(0)) or -1) ~= 0 then
            return cache
        end
    end

    cache.loadSucceeded = true
    ACCOUNT_APPEARANCE_CACHE[accountGUID] = cache
    return cache
end

local function IsArmorSetSlotIndex(slotIndex)
    return slotIndex and slotIndex >= 1 and slotIndex <= 11
end

local function GetVirtualSetBaseName(itemName)
    itemName = tostring(itemName or ""):gsub("%s+$", "")
    if itemName == "" then
        return nil
    end

    local baseName = itemName:gsub("%s+[^%s]+$", "")
    if baseName == "" or baseName == itemName then
        return nil
    end

    return baseName
end

local function GetVirtualSetId(baseName)
    local hash = 0
    for index = 1, #baseName do
        hash = (hash * 33 + string.byte(baseName, index)) % 2147483647
    end

    if hash == 0 then
        hash = 1
    end

    return -hash
end

local function NormalizeStoredItemValue(value)
    if value == nil or value == '' then
        return nil
    end
    return tonumber(value) or 0
end

-- One snapshot is the persistence boundary for state hydration and mutation.
-- Duplicate legacy rows are tolerated only when their values agree; conflicting
-- rows fail closed until the manual schema migration has repaired them.
local function LoadStoredTransmogStates(playerGUID)
    playerGUID = tonumber(playerGUID)
    if not playerGUID or playerGUID <= 0 then
        return {}, false
    end

    local queryOK, result = pcall(CharDBQuery, string.format(
        "SELECT slot, item, real_item FROM character_transmog WHERE player_guid = %u",
        playerGUID
    ))
    if not queryOK then
        return {}, false
    end

    local states = {}
    if result then
        repeat
            local row = result:GetRow()
            local slot = NormalizeVisibleSlot(row and row["slot"])
            if slot then
                local item = NormalizeStoredItemValue(row["item"])
                local realItemId = tonumber(row["real_item"]) or 0
                local existing = states[slot]
                if existing then
                    existing.rowCount = existing.rowCount + 1
                    if existing.item ~= item or existing.realItemId ~= realItemId then
                        return states, false
                    end
                else
                    states[slot] = {
                        item = item,
                        realItemId = realItemId,
                        rowCount = 1,
                    }
                end
            end
        until not result:NextRow()
        return states, true
    end

    -- Eluna represents both an empty SELECT and a failed SELECT as nil. A
    -- bounded count distinguishes a new character from transient DB failure.
    local countOK, countQuery = pcall(CharDBQuery, string.format(
        "SELECT COUNT(*) FROM character_transmog WHERE player_guid = %u",
        playerGUID
    ))
    if not countOK or not countQuery or (tonumber(countQuery:GetUInt32(0)) or -1) ~= 0 then
        return states, false
    end
    return states, true
end

local function BuildTransmogStateUpdateSQL(playerGUID, statesBySlot)
    local itemCases = {}
    local realItemCases = {}
    local slots = {}
    for _, slot in ipairs(VISIBLE_SLOTS) do
        local state = statesBySlot and statesBySlot[slot]
        if state then
            local itemValue = state.item == nil and "NULL" or tostring(tonumber(state.item) or 0)
            slots[#slots + 1] = tostring(slot)
            itemCases[#itemCases + 1] = string.format("WHEN %u THEN %s", slot, itemValue)
            realItemCases[#realItemCases + 1] = string.format(
                "WHEN %u THEN %u",
                slot,
                math.max(0, math.floor(tonumber(state.realItemId) or 0))
            )
        end
    end
    if #slots == 0 then
        return nil
    end

    return string.format(
        "UPDATE character_transmog SET item = CASE slot %s ELSE item END, real_item = CASE slot %s ELSE real_item END WHERE player_guid = %u AND slot IN (%s)",
        table.concat(itemCases, " "),
        table.concat(realItemCases, " "),
        tonumber(playerGUID) or 0,
        table.concat(slots, ",")
    )
end

local function VerifyTransmogStates(playerGUID, expectedBySlot)
    local states, loadSucceeded = LoadStoredTransmogStates(playerGUID)
    if not loadSucceeded then
        return states, false
    end
    for slot, expected in pairs(expectedBySlot or {}) do
        local actual = states[slot]
        if not actual
            or actual.item ~= expected.item
            or actual.realItemId ~= math.max(0, math.floor(tonumber(expected.realItemId) or 0)) then
            return states, false
        end
    end
    return states, true
end

local function WriteTransmogStates(playerGUID, statesBySlot)
    local sql = BuildTransmogStateUpdateSQL(playerGUID, statesBySlot)
    if not sql then
        return true
    end
    local writeOK = pcall(CharDBQuery, sql)
    if not writeOK then
        return false
    end
    local _, verified = VerifyTransmogStates(playerGUID, statesBySlot)
    return verified
end

local function GetItemTemplateInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId
        or itemId ~= itemId
        or itemId <= 0
        or itemId >= math.huge
        or itemId ~= math.floor(itemId)
        or itemId > 4294967295 then
        return nil, true
    end

    local cached = ITEM_TEMPLATE_CACHE[itemId]
    if cached ~= nil then
        return cached or nil, true
    end

    local query = WorldDBQuery(string.format(
        "SELECT itemset, InventoryType, name, displayid, SellPrice, `class`, subclass, RequiredLevel FROM item_template WHERE entry = %u LIMIT 1",
        itemId
    ))
    if not query then
        -- Eluna returns nil both for no row and for a failed query. Confirm an
        -- actual miss before negative-caching it; callers that reconcile saved
        -- state can then distinguish invalid data from transient DB uncertainty.
        local countQuery = WorldDBQuery(string.format(
            "SELECT COUNT(*) FROM item_template WHERE entry = %u",
            itemId
        ))
        if not countQuery then
            return nil, false
        end
        local count = tonumber(countQuery:GetUInt32(0)) or 0
        if count == 0 then
            CacheMissingItemTemplate(itemId)
            return nil, true
        end
        return nil, false
    end

    cached = {
        itemset = tonumber(query:GetUInt32(0)) or 0,
        inventoryType = tonumber(query:GetUInt32(1)) or 0,
        name = query:GetString(2) or "",
        displayId = tonumber(query:GetUInt32(3)) or 0,
        sellPrice = tonumber(query:GetUInt32(4)) or 0,
        itemClass = tonumber(query:GetUInt32(5)) or 0,
        itemSubclass = tonumber(query:GetUInt32(6)) or 0,
        requiredLevel = tonumber(query:GetUInt32(7)) or 0,
    }

    ITEM_TEMPLATE_CACHE[itemId] = cached
    return cached, true
end

local function PreloadItemTemplateInfos(itemIds)
    local pending = {}
    local pendingLookup = {}
    local loadSucceeded = true

    for _, itemId in ipairs(itemIds or {}) do
        itemId = tonumber(itemId)
        if itemId and itemId > 0 and ITEM_TEMPLATE_CACHE[itemId] == nil and not pendingLookup[itemId] then
            pendingLookup[itemId] = true
            table.insert(pending, itemId)
        end
    end

    -- 1,500 numeric IDs keep each query well below common packet limits while
    -- cutting a 38k-appearance cold catalog from about 96 template queries to 26.
    local chunkSize = 1500
    for first = 1, #pending, chunkSize do
        local requested = {}
        local values = {}
        local last = math.min(first + chunkSize - 1, #pending)

        for index = first, last do
            local itemId = pending[index]
            requested[itemId] = true
            table.insert(values, tostring(itemId))
        end

        local query = WorldDBQuery(
            "SELECT entry, itemset, InventoryType, name, displayid, SellPrice, `class`, subclass, RequiredLevel FROM item_template WHERE entry IN (" .. table.concat(values, ",") .. ")"
        )

        if query then
            repeat
                local itemId = tonumber(query:GetUInt32(0)) or 0
                if requested[itemId] then
                    ITEM_TEMPLATE_CACHE[itemId] = {
                        itemset = tonumber(query:GetUInt32(1)) or 0,
                        inventoryType = tonumber(query:GetUInt32(2)) or 0,
                        name = query:GetString(3) or "",
                        displayId = tonumber(query:GetUInt32(4)) or 0,
                        sellPrice = tonumber(query:GetUInt32(5)) or 0,
                        itemClass = tonumber(query:GetUInt32(6)) or 0,
                        itemSubclass = tonumber(query:GetUInt32(7)) or 0,
                        requiredLevel = tonumber(query:GetUInt32(8)) or 0,
                    }
                    requested[itemId] = nil
                end
            until not query:NextRow()
            -- The batch query itself succeeded, so omitted IDs are confirmed
            -- misses and are safe to negative-cache.
            for itemId in pairs(requested) do
                CacheMissingItemTemplate(itemId)
            end
        else
            local countQuery = WorldDBQuery(
                "SELECT COUNT(*) FROM item_template WHERE entry IN (" .. table.concat(values, ",") .. ")"
            )
            if countQuery and (tonumber(countQuery:GetUInt32(0)) or -1) == 0 then
                for itemId in pairs(requested) do
                    CacheMissingItemTemplate(itemId)
                end
            else
                loadSucceeded = false
            end
        end
    end
    return loadSucceeded
end

local function GetFreeTransmogPlayerGUID(player)
    if not player or type(player.GetGUIDLow) ~= "function" then
        return nil
    end

    local ok, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = ok and tonumber(playerGUID) or nil
    if not playerGUID or playerGUID ~= math.floor(playerGUID) or playerGUID <= 0 then
        return nil
    end

    return playerGUID
end

local function IsAppearanceBuddyGameMaster(player)
    if not player or type(player.GetGMRank) ~= "function" then
        return false
    end

    local ok, rank = pcall(player.GetGMRank, player)
    return ok and (tonumber(rank) or 0) > 0
end

local function IsFreeTransmogEnabled(player)
    local playerGUID = GetFreeTransmogPlayerGUID(player)
    if not playerGUID or not FREE_TRANSMOG_ENABLED_BY_PLAYER[playerGUID] then
        return false
    end

    if not IsAppearanceBuddyGameMaster(player) then
        FREE_TRANSMOG_ENABLED_BY_PLAYER[playerGUID] = nil
        return false
    end

    return true
end

local function SetFreeTransmogEnabled(player, enabled)
    local playerGUID = GetFreeTransmogPlayerGUID(player)
    if not playerGUID or not IsAppearanceBuddyGameMaster(player) then
        return false
    end

    if enabled then
        FREE_TRANSMOG_ENABLED_BY_PLAYER[playerGUID] = true
    else
        FREE_TRANSMOG_ENABLED_BY_PLAYER[playerGUID] = nil
    end
    return true
end

local function GetTransmogBaseSlotCost(player)
    if IsFreeTransmogEnabled(player) then
        return 0
    end

    -- Missing/broken level APIs fail closed to the cap instead of creating a
    -- cheap-price exploit. Stock WotLK levels are then clamped to 1..80.
    local level = TRANSMOG_MAX_LEVEL
    if player and player.GetLevel then
        local ok, value = pcall(player.GetLevel, player)
        value = ok and tonumber(value) or nil
        if value and value == value and value > -math.huge and value < math.huge then
            level = math.floor(value)
        end
    end
    level = math.max(1, math.min(TRANSMOG_MAX_LEVEL, level))

    local levelRatio = level / TRANSMOG_MAX_LEVEL
    local scaledCost = math.floor(
        TRANSMOG_MAX_SLOT_COST * (levelRatio ^ TRANSMOG_LEVEL_COST_POWER) + 0.5
    )
    return math.max(TRANSMOG_MIN_SLOT_COST, scaledCost)
end

local function GetTransmogSlotCost(player, visibleSlot, baseSlotCost)
    visibleSlot = NormalizeVisibleSlot(visibleSlot)
    if not player or not visibleSlot or not CalculateSlotReverse or not GetEquippedItemId then
        return 0
    end

    local equipSlot = math.floor(CalculateSlotReverse(visibleSlot))
    if GetEquippedItemId(player, equipSlot) <= 0 then
        return 0
    end

    return math.max(0, math.floor(tonumber(baseSlotCost) or GetTransmogBaseSlotCost(player)))
end

local function BuildTransmogSlotCosts(player)
    local costs = {}
    if not player then return costs end

    local baseSlotCost = GetTransmogBaseSlotCost(player)
    for _, visibleSlot in ipairs(VISIBLE_SLOTS) do
        costs[visibleSlot] = GetTransmogSlotCost(player, visibleSlot, baseSlotCost)
    end
    return costs
end

local function GetPlayerCoinage(player)
    if not player or not player.GetCoinage then return 0 end
    local ok, money = pcall(player.GetCoinage, player)
    return ok and math.max(0, math.floor(tonumber(money) or 0)) or 0
end

local function SyncTransmogCostState(player, requestToken)
    if player then
        AIO.Handle(player, "Transmog", "SetTransmogCostStateClient", BuildTransmogSlotCosts(player), GetPlayerCoinage(player), requestToken)
    end
end

local function ChargeTransmogCost(player, cost)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if cost == 0 then return true, false end
    local before = GetPlayerCoinage(player)
    if before < cost then return false, false end
    local ok, result = pcall(player.ModifyMoney, player, -cost)
    local after = GetPlayerCoinage(player)
    if ok and result ~= false and after == before - cost then
        return true, false
    end

    -- Money-change hooks can alter the requested delta. Restore the verified
    -- pre-charge balance before reporting failure so a rejected transaction
    -- cannot silently retain a partial fee.
    local compensation = before - after
    if compensation ~= 0 then
        pcall(player.ModifyMoney, player, compensation)
    end
    local compensationFailed = GetPlayerCoinage(player) ~= before
    if compensationFailed then
        print(string.format(
            "[AppearanceBuddy Transmog] CRITICAL: failed charge compensation for player %s (before=%d, after=%d)",
            tostring(player and player.GetGUIDLow and player:GetGUIDLow() or "unknown"),
            before,
            GetPlayerCoinage(player)
        ))
    end
    return false, compensationFailed
end

local function RefundTransmogCost(player, cost)
    cost = math.max(0, math.floor(tonumber(cost) or 0))
    if cost == 0 then return true end
    local before = GetPlayerCoinage(player)
    local ok, result = pcall(player.ModifyMoney, player, cost)
    return ok and result ~= false and GetPlayerCoinage(player) == before + cost
end

local function DeriveItemSetName(names)
    local prefixWords = nil

    for _, itemName in ipairs(names) do
        local words = {}
        for word in tostring(itemName or ""):gmatch("%S+") do
            table.insert(words, word)
        end

        if not prefixWords then
            prefixWords = words
        else
            local nextPrefix = {}
            for index = 1, math.min(#prefixWords, #words) do
                if prefixWords[index] ~= words[index] then
                    break
                end
                table.insert(nextPrefix, prefixWords[index])
            end
            prefixWords = nextPrefix
        end

        if not prefixWords or #prefixWords == 0 then
            break
        end
    end

    if prefixWords and #prefixWords > 0 then
        local name = table.concat(prefixWords, " ")
        name = name:gsub("[%s%-:]+$", "")
        if name ~= "" then
            return name
        end
    end

    return names[1] or "Unnamed Set"
end

local function EscapeLikePrefix(value)
    return EscapeString(value):gsub("%%", "\\%%"):gsub("_", "\\_")
end

-- Destructive operations require the exact collection item to be present, so
-- an unowned alias with the same display cannot revoke another item silently.
local function GetExactUnlockedAppearanceBucket(accountGUID, slot, itemId)
    itemId = tonumber(itemId)
    slot = NormalizeVisibleSlot(slot)
    if not itemId
        or itemId ~= itemId
        or itemId <= 0
        or itemId >= math.huge
        or itemId ~= math.floor(itemId)
        or itemId > 4294967295
        or not slot then
        return nil
    end

    local inventoryTypes = SLOT_INVENTORY_TYPES[slot]
    local itemTemplate, templateLoadSucceeded = GetItemTemplateInfo(itemId)
    if not templateLoadSucceeded or not inventoryTypes or not itemTemplate
        or not inventoryTypes[itemTemplate.inventoryType] then
        return nil
    end

    local displayId = tonumber(itemTemplate.displayId) or 0
    local removed, removedLoadSucceeded = IsAccountAppearanceRemoved(accountGUID, displayId)
    if not removedLoadSucceeded or displayId <= 0 or removed then
        return nil
    end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    if not appearanceCache.loadSucceeded then
        return nil
    end
    local displayBucket = appearanceCache.bySlotDisplay[slot][displayId]
    if not displayBucket or not displayBucket.items[itemId] then
        return nil
    end

    return displayId, displayBucket
end

-- Login/state hydration validates only the at-most-fourteen stored looks. It
-- deliberately avoids constructing a potentially 38k-row account collection.
local function ResolveStoredAppearanceItems(player, requestedBySlot)
    if not player or type(player.GetAccountId) ~= "function" then
        return {}, false
    end

    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    accountGUID = accountOK and tonumber(accountGUID) or nil
    if not accountGUID or accountGUID <= 0 then
        return {}, false
    end

    local itemIds = {}
    local seenItemIds = {}
    for slot, itemId in pairs(requestedBySlot or {}) do
        slot = NormalizeVisibleSlot(slot)
        itemId = tonumber(itemId)
        if slot and itemId and itemId > 0 and itemId == math.floor(itemId)
            and itemId <= 4294967295 and not seenItemIds[itemId] then
            seenItemIds[itemId] = true
            itemIds[#itemIds + 1] = itemId
        end
    end
    if #itemIds == 0 then
        return {}, true
    end
    local context = AppearanceEligibility.GetContext(player)
    if not context then
        return {}, false
    end
    if not PreloadItemTemplateInfos(itemIds) then
        return {}, false
    end

    local removedAppearances, removedLoadSucceeded = GetAccountRemovedAppearanceCache(accountGUID)
    if not removedLoadSucceeded then
        return {}, false
    end

    local displaySlots = {}
    local displayIds = {}
    local seenDisplayIds = {}
    for slot, itemId in pairs(requestedBySlot or {}) do
        slot = NormalizeVisibleSlot(slot)
        itemId = tonumber(itemId)
        local itemTemplate, templateLoadSucceeded = GetItemTemplateInfo(itemId)
        if not templateLoadSucceeded then
            return {}, false
        end
        local allowedTypes = slot and SLOT_INVENTORY_TYPES[slot] or nil
        if itemTemplate and allowedTypes and allowedTypes[itemTemplate.inventoryType]
            and AppearanceEligibility.Allows(player, slot, itemTemplate, context) then
            local displayId = tonumber(itemTemplate.displayId) or 0
            if displayId > 0 and not removedAppearances[displayId] then
                displaySlots[displayId] = displaySlots[displayId] or {}
                displaySlots[displayId][#displaySlots[displayId] + 1] = slot
                if not seenDisplayIds[displayId] then
                    seenDisplayIds[displayId] = true
                    displayIds[#displayIds + 1] = tostring(displayId)
                end
            end
        end
    end

    local resolved = {}
    if #displayIds == 0 then
        return resolved, true
    end

    local whereClause = string.format(
        "account_id = %u AND display_id IN (%s)",
        accountGUID,
        table.concat(displayIds, ",")
    )
    local queryOK, query = pcall(AuthDBQuery,
        "SELECT unlocked_item_id, display_id, COALESCE(inventory_type, 0) FROM account_transmog WHERE "
        .. whereClause .. " ORDER BY unlocked_item_id"
    )
    if not queryOK then
        return resolved, false
    end

    if query then
        local candidateItemIds = {}
        local candidateItemIdSet = {}
        local candidatesBySlot = {}
        repeat
            local unlockedItemId = tonumber(query:GetUInt32(0)) or 0
            local displayId = tonumber(query:GetUInt32(1)) or 0
            for _, slot in ipairs(displaySlots[displayId] or {}) do
                if unlockedItemId > 0 then
                    local candidates = candidatesBySlot[slot]
                    if not candidates then
                        candidates = {}
                        candidatesBySlot[slot] = candidates
                    end
                    candidates[#candidates + 1] = unlockedItemId
                    if not candidateItemIdSet[unlockedItemId] then
                        candidateItemIdSet[unlockedItemId] = true
                        candidateItemIds[#candidateItemIds + 1] = unlockedItemId
                    end
                end
            end
        until not query:NextRow()

        if not PreloadItemTemplateInfos(candidateItemIds) then
            return resolved, false
        end
        for slot, candidates in pairs(candidatesBySlot) do
            for _, unlockedItemId in ipairs(candidates) do
                local itemTemplate, templateLoadSucceeded = GetItemTemplateInfo(unlockedItemId)
                if not templateLoadSucceeded then
                    return resolved, false
                end
                if itemTemplate and AppearanceEligibility.Allows(player, slot, itemTemplate, context)
                    and (not resolved[slot] or unlockedItemId < resolved[slot]) then
                    resolved[slot] = unlockedItemId
                end
            end
        end
        return resolved, true
    end

    local countOK, countQuery = pcall(AuthDBQuery,
        "SELECT COUNT(*) FROM account_transmog WHERE " .. whereClause
    )
    if not countOK or not countQuery or (tonumber(countQuery:GetUInt32(0)) or -1) ~= 0 then
        return resolved, false
    end
    return resolved, true
end

ITEM_SET_CATALOG_SERVICE = (function()
    local ACCOUNT_ITEM_SET_CATALOG_INDEX_CACHE = {}
    local ACCOUNT_ITEM_SET_CATALOG_BY_ID_CACHE = {}
    local ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT = {}
    local ITEM_SET_CATALOG_BUILD_WORK_QUEUE = {}
    local ITEM_SET_CATALOG_WORKER_EVENT_ID = nil
    local ITEM_SET_CATALOG_SCAN_BATCH_SIZE = 1500
    local ITEM_SET_CATALOG_TEMPLATE_SET_BATCH_SIZE = 128
    local ITEM_SET_CATALOG_VIRTUAL_NAME_BATCH_SIZE = 128
    local ITEM_SET_CATALOG_TEMPLATE_ROW_LIMIT = 1500
    local ITEM_SET_CATALOG_TEMPLATE_INVENTORY_TYPES = "1,3,4,5,6,7,8,9,10,13,14,15,16,17,19,20,21,22,25,26,28"
    local ITEM_SET_CATALOG_TEMPLATE_SLOT_CASE = "CASE InventoryType "
        .. "WHEN 1 THEN 1 WHEN 3 THEN 2 WHEN 16 THEN 3 "
        .. "WHEN 5 THEN 4 WHEN 20 THEN 4 WHEN 4 THEN 5 WHEN 19 THEN 6 "
        .. "WHEN 9 THEN 7 WHEN 10 THEN 8 WHEN 6 THEN 9 WHEN 7 THEN 10 "
        .. "WHEN 8 THEN 11 WHEN 13 THEN 12 WHEN 17 THEN 12 WHEN 21 THEN 12 "
        .. "WHEN 14 THEN 13 WHEN 22 THEN 13 "
        .. "WHEN 15 THEN 14 WHEN 25 THEN 14 WHEN 26 THEN 14 WHEN 28 THEN 14 END"
    local ITEM_SET_CATALOG_MAX_ACTIVE_BUILDS = 4
    local ITEM_SET_CATALOG_MAX_PENDING_PLAYERS = 8
    local ITEM_SET_CATALOG_MAX_BUILD_SLICES = 512
    local ITEM_SET_CATALOG_MAX_BUILD_SECONDS = 14
    local ITEM_SET_CATALOG_EVENT_DELAY_MS = 1
    local ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT = 0
    local SendItemSetCatalogPage

    local function QueryOrConfirmEmpty(queryFunction, selectSQL, countSQL)
        local queryOK, query = pcall(queryFunction, selectSQL)
        if not queryOK then
            return nil, false
        end
        if query then
            return query, true
        end

        local countOK, countQuery = pcall(queryFunction, countSQL)
        if not countOK or not countQuery then
            return nil, false
        end
        return nil, (tonumber(countQuery:GetUInt32(0)) or -1) == 0
    end

    local function NewAccountItemSetCatalogGroup(id, name, isVirtual)
        return {
            id = tonumber(id) or 0,
            name = tostring(name or ""),
            isVirtual = isVirtual == true,
            hasExactTotal = false,
            -- Provisional groups stay sparse while the account scan runs.
            -- Dense fourteen-slot arrays are allocated only for eligible sets.
            fullItems = {},
            unlockedItems = {},
            unlockedCount = 0,
            totalCount = 0,
        }
    end

    local function AddUnlockedCatalogItem(build, itemId, itemsetId, inventoryType, itemName)
        local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[tonumber(inventoryType) or 0]
        if not slotIndex then
            return
        end

        local group
        itemsetId = tonumber(itemsetId) or 0
        if itemsetId > 0 then
            group = build.officialGroups[itemsetId]
            if not group then
                group = NewAccountItemSetCatalogGroup(itemsetId, "", false)
                build.officialGroups[itemsetId] = group
            end
        elseif IsArmorSetSlotIndex(slotIndex) then
            local baseName = GetVirtualSetBaseName(itemName)
            if not baseName then
                return
            end
            group = build.virtualGroups[baseName]
            if not group then
                group = NewAccountItemSetCatalogGroup(0, baseName, true)
                group.baseName = baseName
                build.virtualGroups[baseName] = group
            end
        end

        if not group then
            return
        end

        itemId = math.max(0, math.floor(tonumber(itemId) or 0))
        local currentItemId = tonumber(group.unlockedItems[slotIndex]) or 0
        if itemId > 0 and (currentItemId == 0 or itemId < currentItemId) then
            if currentItemId == 0 then
                group.unlockedCount = group.unlockedCount + 1
            end
            group.unlockedItems[slotIndex] = itemId
        end
    end

    local function GetItemSetCatalogIconItemId(setData)
        for _, slotIndex in ipairs(ITEM_SET_ICON_SLOT_PRIORITY) do
            local unlockedItemId = tonumber(setData.unlockedItems and setData.unlockedItems[slotIndex]) or 0
            if unlockedItemId > 0 then
                return unlockedItemId
            end

            local previewItemId = tonumber(setData.fullItems and setData.fullItems[slotIndex]) or 0
            if previewItemId > 0 then
                return previewItemId
            end
        end

        return 0
    end

    local function ApplyOfficialCatalogTemplate(group, template)
        if not group then
            return
        end
        if not template then
            group.invalid = true
            return
        end

        group.name = tostring(template.name or "Unlocked Item Set")
        group.fullItems = NormalizeAppearanceSetItemIds(template.fullItems)
        group.totalCount = math.max(0, math.floor(tonumber(template.totalCount) or 0))
        group.hasExactTotal = true
        group.invalid = group.totalCount == 0
    end

    local function ApplyVirtualCatalogTemplate(group, template)
        if not group then
            return
        end

        if template then
            group.name = tostring(template.name or group.baseName or "Unlocked Item Set")
            group.fullItems = NormalizeAppearanceSetItemIds(template.fullItems)
            group.totalCount = math.max(0, math.floor(tonumber(template.totalCount) or 0))
            group.hasExactTotal = group.totalCount > 0
        else
            group.name = tostring(group.baseName or "Unlocked Item Set")
            group.fullItems = NormalizeAppearanceSetItemIds(group.unlockedItems)
            group.totalCount = group.unlockedCount
            group.hasExactTotal = false
        end
    end

    local function ResolveCatalogRequestPlayer(request, accountGUID)
        if type(request) ~= "table" or type(GetPlayersInWorld) ~= "function" then
            return nil
        end

        local expectedAccountId = tonumber(accountGUID)
        local expectedGUIDLow = tonumber(request.playerGUIDLow)
        if not expectedAccountId or expectedAccountId <= 0
            or not expectedGUIDLow or expectedGUIDLow <= 0 then
            return nil
        end

        -- mod-ale's Object:GetGUID binding pushes an unregistered GUID64
        -- userdata. Reacquire a fresh player wrapper instead of retaining a
        -- Player or GUID object across the catalog worker's timed callbacks.
        local playersOK, players = pcall(GetPlayersInWorld)
        if not playersOK or type(players) ~= "table" then
            return nil
        end
        for _, player in ipairs(players) do
            if IsAppearanceBuddyPlayer(player)
                and player.GetAccountId and player.GetGUIDLow then
                local accountOK, currentAccountId = pcall(player.GetAccountId, player)
                local guidLowOK, currentGUIDLow = pcall(player.GetGUIDLow, player)
                if accountOK and tonumber(currentAccountId) == expectedAccountId
                    and guidLowOK and tonumber(currentGUIDLow) == expectedGUIDLow then
                    return player
                end
            end
        end
        return nil
    end

    local function EmitCatalogBuildFailure(player, request, message)
        if not player or type(request) ~= "table" then
            return
        end
        AIO.Handle(
            player,
            "Transmog",
            "InitItemSets",
            {},
            request.requestToken,
            request.page,
            false,
            0,
            request.search,
            false,
            tostring(message or "Item sets could not be loaded. Please try again.")
        )
    end

    local function SendCatalogResponseSafely(callback, accountGUID, ...)
        local responseOK, responseError = pcall(callback, ...)
        if not responseOK then
            print(string.format(
                "[AppearanceBuddy Transmog] item-set catalog response failed for account %s: %s",
                tostring(accountGUID),
                tostring(responseError)
            ))
        end
    end

    local function RemoveCatalogBuildFromWorkQueue(build)
        if not build or not build.queued then
            return
        end
        for index = #ITEM_SET_CATALOG_BUILD_WORK_QUEUE, 1, -1 do
            if ITEM_SET_CATALOG_BUILD_WORK_QUEUE[index] == build then
                table.remove(ITEM_SET_CATALOG_BUILD_WORK_QUEUE, index)
                break
            end
        end
        build.queued = false
    end

    local function FinishAccountItemSetCatalogBuildLifecycle(build)
        if not build or not build.active then
            return
        end

        build.active = false
        RemoveCatalogBuildFromWorkQueue(build)
        if ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[build.accountId] == build then
            ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[build.accountId] = nil
        end
        ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT = math.max(
            0,
            ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT - 1
        )
    end

    local FailAccountItemSetCatalogBuild
    FailAccountItemSetCatalogBuild = function(build, message, logDetail)
        if not build or not build.active then
            return
        end

        local pending = build.pendingByPlayer or {}
        FinishAccountItemSetCatalogBuildLifecycle(build)
        if logDetail then
            print(string.format(
                "[AppearanceBuddy Transmog] item-set catalog build failed for account %s: %s",
                tostring(build.accountId),
                tostring(logDetail)
            ))
        end

        for _, request in pairs(pending) do
            local player = ResolveCatalogRequestPlayer(request, build.accountId)
            if player then
                SendCatalogResponseSafely(
                    EmitCatalogBuildFailure,
                    build.accountId,
                    player,
                    request,
                    message
                )
            end
        end
    end

    local function CancelAccountItemSetCatalogBuild(accountGUID, message)
        accountGUID = tonumber(accountGUID)
        if accountGUID then
            ACCOUNT_ITEM_SET_CATALOG_INDEX_CACHE[accountGUID] = nil
            ACCOUNT_ITEM_SET_CATALOG_BY_ID_CACHE[accountGUID] = nil
        end
        local build = accountGUID and ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[accountGUID] or nil
        if build then
            FailAccountItemSetCatalogBuild(
                build,
                message or "The item-set catalog was invalidated. Please try again."
            )
        end
    end

    local RunAccountItemSetCatalogBuildStep
    local ArmAccountItemSetCatalogWorker

    local function FailQueuedAccountItemSetCatalogBuilds(message, detail)
        local queued = ITEM_SET_CATALOG_BUILD_WORK_QUEUE
        ITEM_SET_CATALOG_BUILD_WORK_QUEUE = {}
        for _, build in ipairs(queued) do
            build.queued = false
            if build.active then
                FailAccountItemSetCatalogBuild(build, message, detail)
            end
        end
    end

    ArmAccountItemSetCatalogWorker = function()
        if ITEM_SET_CATALOG_WORKER_EVENT_ID ~= nil then
            return true
        end
        if #ITEM_SET_CATALOG_BUILD_WORK_QUEUE == 0 then
            return true
        end
        if type(CreateLuaEvent) ~= "function" then
            return false
        end

        local scheduledOK, eventId = pcall(CreateLuaEvent, function()
            ITEM_SET_CATALOG_WORKER_EVENT_ID = nil

            local build
            while #ITEM_SET_CATALOG_BUILD_WORK_QUEUE > 0 and not build do
                local candidate = table.remove(ITEM_SET_CATALOG_BUILD_WORK_QUEUE, 1)
                candidate.queued = false
                if candidate.active
                    and ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[candidate.accountId] == candidate then
                    build = candidate
                end
            end

            if build then
                local stepOK, stepError = pcall(RunAccountItemSetCatalogBuildStep, build)
                if not stepOK then
                    FailAccountItemSetCatalogBuild(
                        build,
                        "Item sets could not be loaded. Please try again.",
                        stepError
                    )
                end
            end

            if ITEM_SET_CATALOG_WORKER_EVENT_ID == nil
                and #ITEM_SET_CATALOG_BUILD_WORK_QUEUE > 0
                and not ArmAccountItemSetCatalogWorker() then
                FailQueuedAccountItemSetCatalogBuilds(
                    "The item-set catalog worker is unavailable. Please try again.",
                    "CreateLuaEvent failed while continuing the shared worker"
                )
            end
        end, ITEM_SET_CATALOG_EVENT_DELAY_MS, 1)

        if not scheduledOK or eventId == nil or eventId == false then
            return false
        end
        ITEM_SET_CATALOG_WORKER_EVENT_ID = eventId
        return true
    end

    local function QueueAccountItemSetCatalogBuildStep(build)
        if not build or not build.active
            or ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[build.accountId] ~= build then
            return false
        end
        if not build.queued then
            build.queued = true
            ITEM_SET_CATALOG_BUILD_WORK_QUEUE[#ITEM_SET_CATALOG_BUILD_WORK_QUEUE + 1] = build
        end
        if ArmAccountItemSetCatalogWorker() then
            return true
        end

        FailQueuedAccountItemSetCatalogBuilds(
            "The item-set catalog worker is unavailable. Please try again.",
            "CreateLuaEvent was unavailable or rejected the shared worker"
        )
        return false
    end

    local function PrepareAccountItemSetCatalogTemplates(build)
        build.officialSetIds = {}
        for itemsetId, group in pairs(build.officialGroups) do
            if group.unlockedCount > 0 then
                local cached = ITEM_SET_TEMPLATE_CACHE[itemsetId]
                if cached ~= nil then
                    ApplyOfficialCatalogTemplate(group, cached or nil)
                else
                    build.officialSetIds[#build.officialSetIds + 1] = itemsetId
                end
            end
        end
        table.sort(build.officialSetIds)

        build.eligibleVirtualBaseNames = {}
        build.virtualBaseNames = {}
        for baseName, group in pairs(build.virtualGroups) do
            if group.unlockedCount >= 3 then
                build.eligibleVirtualBaseNames[#build.eligibleVirtualBaseNames + 1] = baseName
                local cached = VIRTUAL_SET_TEMPLATE_CACHE[baseName]
                if cached ~= nil then
                    ApplyVirtualCatalogTemplate(group, cached or nil)
                else
                    -- Virtual sets are inferred from item-name prefixes. A full
                    -- template sweep uses broad LIKE scans over item_template
                    -- and can make the catalog miss its response deadline for
                    -- large collections. The supported fallback intentionally
                    -- shows the unlocked pieces without claiming an exact total.
                    ApplyVirtualCatalogTemplate(group, nil)
                end
            end
        end
        table.sort(build.eligibleVirtualBaseNames)
        table.sort(build.virtualBaseNames)

        build.officialFirst = 1
        build.virtualFirst = 1
        build.phase = "official_templates"
    end

    local function CacheCatalogItemTemplate(
        itemId,
        itemsetId,
        inventoryType,
        itemName,
        displayId,
        sellPrice,
        itemClass,
        itemSubclass,
        requiredLevel
    )
        itemId = tonumber(itemId)
        if not itemId or itemId ~= math.floor(itemId) or itemId <= 0 or itemId > 4294967295 then
            return
        end
        ITEM_TEMPLATE_CACHE[itemId] = {
            itemset = tonumber(itemsetId) or 0,
            inventoryType = tonumber(inventoryType) or 0,
            name = tostring(itemName or ""),
            displayId = tonumber(displayId) or 0,
            sellPrice = tonumber(sellPrice) or 0,
            itemClass = tonumber(itemClass) or 0,
            itemSubclass = tonumber(itemSubclass) or 0,
            requiredLevel = tonumber(requiredLevel) or 0,
        }
    end

    local function ScanNextAccountItemSetCatalogBatch(build)
        if build.scanCursor >= build.snapshotMaxItemId then
            PrepareAccountItemSetCatalogTemplates(build)
            return
        end

        local previousCursor = build.scanCursor
        local whereRange = string.format(
            "t.account_id = %u AND t.unlocked_item_id > %u AND t.unlocked_item_id <= %u",
            build.accountId,
            build.scanCursor,
            build.snapshotMaxItemId
        )
        local query, loadSucceeded = QueryOrConfirmEmpty(
            AuthDBQuery,
            "SELECT t.unlocked_item_id, t.display_id, COALESCE(t.inventory_type, 0), "
                .. "COALESCE(t.item_name, ''), (removed.display_id IS NOT NULL) "
                .. "FROM account_transmog t "
                .. "LEFT JOIN account_transmog_removed_appearance removed "
                .. "ON removed.account_id = t.account_id AND removed.display_id = t.display_id "
                .. "WHERE " .. whereRange
                .. " ORDER BY t.unlocked_item_id LIMIT " .. ITEM_SET_CATALOG_SCAN_BATCH_SIZE,
            "SELECT COUNT(*) FROM account_transmog t WHERE " .. whereRange
        )
        if not loadSucceeded then
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "account collection keyset page was uncertain"
            )
            return
        end
        if not query then
            build.scanCursor = build.snapshotMaxItemId
            PrepareAccountItemSetCatalogTemplates(build)
            return
        end

        local rowsByItemId = {}
        local itemIds = {}
        repeat
            local itemId = tonumber(query:GetUInt32(0)) or 0
            build.scanCursor = math.max(build.scanCursor, itemId)
            local removed = (tonumber(query:GetUInt32(4)) or 0) ~= 0
            if itemId > 0 and not removed and not rowsByItemId[itemId] then
                rowsByItemId[itemId] = {
                    itemName = query:GetString(3) or "",
                }
                itemIds[#itemIds + 1] = itemId
            end
        until not query:NextRow()

        if build.scanCursor <= previousCursor then
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "account collection keyset page did not advance"
            )
            return
        end

        if #itemIds > 0 then
            local itemIdStrings = {}
            for index, itemId in ipairs(itemIds) do
                itemIdStrings[index] = tostring(itemId)
            end
            local idList = table.concat(itemIdStrings, ",")
            local templateQuery, templatesLoaded = QueryOrConfirmEmpty(
                WorldDBQuery,
                "SELECT entry, itemset, InventoryType, name, displayid, SellPrice, `class`, subclass, RequiredLevel FROM item_template WHERE entry IN ("
                    .. idList .. ") ORDER BY entry",
                "SELECT COUNT(*) FROM item_template WHERE entry IN (" .. idList .. ")"
            )
            if not templatesLoaded then
                FailAccountItemSetCatalogBuild(
                    build,
                    "Item sets could not be loaded. Please try again.",
                    "item metadata page was uncertain"
                )
                return
            end

            if templateQuery then
                repeat
                    local itemId = tonumber(templateQuery:GetUInt32(0)) or 0
                    local accountRow = rowsByItemId[itemId]
                    if accountRow then
                        local itemName = accountRow.itemName
                        if itemName == "" then
                            itemName = templateQuery:GetString(3) or ""
                        end
                        AddUnlockedCatalogItem(
                            build,
                            itemId,
                            templateQuery:GetUInt32(1),
                            templateQuery:GetUInt32(2),
                            itemName
                        )
                        CacheCatalogItemTemplate(
                            itemId,
                            templateQuery:GetUInt32(1),
                            templateQuery:GetUInt32(2),
                            itemName,
                            templateQuery:GetUInt32(4),
                            templateQuery:GetUInt32(5),
                            templateQuery:GetUInt32(6),
                            templateQuery:GetUInt32(7),
                            templateQuery:GetUInt32(8)
                        )
                    end
                until not templateQuery:NextRow()
            end
        end

        if build.scanCursor >= build.snapshotMaxItemId then
            PrepareAccountItemSetCatalogTemplates(build)
        end
    end

    local function BeginOfficialTemplateChunk(build)
        if build.officialFirst > #build.officialSetIds then
            build.phase = "virtual_templates"
            return nil
        end

        local last = math.min(
            #build.officialSetIds,
            build.officialFirst + ITEM_SET_CATALOG_TEMPLATE_SET_BATCH_SIZE - 1
        )
        local ids = {}
        local requested = {}
        for index = build.officialFirst, last do
            local itemsetId = build.officialSetIds[index]
            ids[#ids + 1] = itemsetId
            requested[itemsetId] = true
            local group = build.officialGroups[itemsetId]
            group.templateFullItems = NewEmptyAppearanceSetItemIds()
            group.templateNames = {}
            group.templateTotalCount = 0
        end

        build.officialChunk = {
            ids = ids,
            idList = table.concat(ids, ","),
            requested = requested,
            first = build.officialFirst,
            last = last,
        }
        return build.officialChunk
    end

    local function FinalizeOfficialTemplateChunk(build, chunk)
        for itemsetId in pairs(chunk.requested) do
            local group = build.officialGroups[itemsetId]
            local template = nil
            if group and group.templateTotalCount > 0 then
                template = {
                    id = itemsetId,
                    name = DeriveItemSetName(group.templateNames),
                    fullItems = NormalizeAppearanceSetItemIds(group.templateFullItems),
                    totalCount = group.templateTotalCount,
                }
            end
            ITEM_SET_TEMPLATE_CACHE[itemsetId] = template or false
            ApplyOfficialCatalogTemplate(group, template)
            if group then
                group.templateFullItems = nil
                group.templateNames = nil
                group.templateTotalCount = nil
            end
        end

        build.officialFirst = chunk.last + 1
        build.officialChunk = nil
    end

    local function LoadNextOfficialTemplatePage(build)
        local chunk = build.officialChunk or BeginOfficialTemplateChunk(build)
        if not chunk then
            return
        end

        -- Choose the same first item per visible slot as the old ordered
        -- keyset scan, but collapse duplicate variants in SQL. This turns a
        -- large account's many item_template pages into one compact request per
        -- set chunk without changing the generated preview items or set names.
        local whereClause = "itemset IN (" .. chunk.idList .. ") AND InventoryType IN ("
            .. ITEM_SET_CATALOG_TEMPLATE_INVENTORY_TYPES .. ")"
        local query, loadSucceeded = QueryOrConfirmEmpty(
            WorldDBQuery,
            "SELECT item_template.itemset, item_template.entry, item_template.name, item_template.InventoryType, "
                .. "item_template.displayid, item_template.SellPrice, item_template.`class`, item_template.subclass, item_template.RequiredLevel "
                .. "FROM item_template INNER JOIN (SELECT itemset, MIN(entry) AS entry "
                .. "FROM item_template WHERE " .. whereClause
                .. " GROUP BY itemset, " .. ITEM_SET_CATALOG_TEMPLATE_SLOT_CASE
                .. ") AS first_slot_item ON first_slot_item.itemset = item_template.itemset "
                .. "AND first_slot_item.entry = item_template.entry "
                .. "ORDER BY item_template.itemset, item_template.entry",
            "SELECT COUNT(*) FROM item_template WHERE " .. whereClause
        )
        if not loadSucceeded then
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "standard set template page was uncertain"
            )
            return
        end
        if not query then
            FinalizeOfficialTemplateChunk(build, chunk)
            return
        end

        repeat
            local itemsetId = tonumber(query:GetUInt32(0)) or 0
            local entry = tonumber(query:GetUInt32(1)) or 0
            local group = chunk.requested[itemsetId] and build.officialGroups[itemsetId] or nil
            local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[tonumber(query:GetUInt32(3)) or 0]
            CacheCatalogItemTemplate(
                entry,
                itemsetId,
                query:GetUInt32(3),
                query:GetString(2),
                query:GetUInt32(4),
                query:GetUInt32(5),
                query:GetUInt32(6),
                query:GetUInt32(7),
                query:GetUInt32(8)
            )
            if group and slotIndex and (tonumber(group.templateFullItems[slotIndex]) or 0) == 0 then
                group.templateFullItems[slotIndex] = entry
                group.templateTotalCount = group.templateTotalCount + 1
                group.templateNames[#group.templateNames + 1] = query:GetString(2) or ""
            end
        until not query:NextRow()
        FinalizeOfficialTemplateChunk(build, chunk)
    end

    local function BeginVirtualTemplateChunk(build)
        if build.virtualFirst > #build.virtualBaseNames then
            build.phase = "finalize"
            return nil
        end

        local last = math.min(
            #build.virtualBaseNames,
            build.virtualFirst + ITEM_SET_CATALOG_VIRTUAL_NAME_BATCH_SIZE - 1
        )
        local baseNames = {}
        local requested = {}
        local conditions = {}
        for index = build.virtualFirst, last do
            local baseName = build.virtualBaseNames[index]
            baseNames[#baseNames + 1] = baseName
            requested[baseName] = true
            conditions[#conditions + 1] = "name LIKE '" .. EscapeLikePrefix(baseName) .. " %'"
            local group = build.virtualGroups[baseName]
            group.templateFullItems = NewEmptyAppearanceSetItemIds()
            group.templateNames = {}
            group.templateTotalCount = 0
        end

        build.virtualChunk = {
            baseNames = baseNames,
            requested = requested,
            conditions = table.concat(conditions, " OR "),
            first = build.virtualFirst,
            last = last,
            cursorEntry = 0,
        }
        return build.virtualChunk
    end

    local function FinalizeVirtualTemplateChunk(build, chunk)
        for _, baseName in ipairs(chunk.baseNames) do
            local group = build.virtualGroups[baseName]
            local template = nil
            if group and group.templateTotalCount > 0 then
                template = {
                    id = GetVirtualSetId(baseName),
                    name = DeriveItemSetName(group.templateNames),
                    fullItems = NormalizeAppearanceSetItemIds(group.templateFullItems),
                    totalCount = group.templateTotalCount,
                }
            end
            VIRTUAL_SET_TEMPLATE_CACHE[baseName] = template or false
            ApplyVirtualCatalogTemplate(group, template)
            if group then
                group.templateFullItems = nil
                group.templateNames = nil
                group.templateTotalCount = nil
            end
        end

        build.virtualFirst = chunk.last + 1
        build.virtualChunk = nil
    end

    local function LoadNextVirtualTemplatePage(build)
        local chunk = build.virtualChunk or BeginVirtualTemplateChunk(build)
        if not chunk then
            return
        end

        local previousEntry = chunk.cursorEntry
        local whereClause = string.format(
            "InventoryType IN (1,3,4,5,6,7,8,9,10,16,19,20) AND entry > %u AND (%s)",
            chunk.cursorEntry,
            chunk.conditions
        )
        local query, loadSucceeded = QueryOrConfirmEmpty(
            WorldDBQuery,
            "SELECT entry, name, InventoryType, displayid, SellPrice, `class`, subclass, RequiredLevel FROM item_template WHERE "
                .. whereClause .. " ORDER BY entry LIMIT "
                .. (ITEM_SET_CATALOG_TEMPLATE_ROW_LIMIT + 1),
            "SELECT COUNT(*) FROM item_template WHERE " .. whereClause
        )
        if not loadSucceeded then
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "virtual set template page was uncertain"
            )
            return
        end
        if not query then
            FinalizeVirtualTemplateChunk(build, chunk)
            return
        end

        local rowNumber = 0
        local hasMore = false
        repeat
            rowNumber = rowNumber + 1
            if rowNumber <= ITEM_SET_CATALOG_TEMPLATE_ROW_LIMIT then
                local entry = tonumber(query:GetUInt32(0)) or 0
                local name = query:GetString(1) or ""
                local baseName = GetVirtualSetBaseName(name)
                local group = baseName and chunk.requested[baseName] and build.virtualGroups[baseName] or nil
                local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[tonumber(query:GetUInt32(2)) or 0]
                CacheCatalogItemTemplate(
                    entry,
                    0,
                    query:GetUInt32(2),
                    name,
                    query:GetUInt32(3),
                    query:GetUInt32(4),
                    query:GetUInt32(5),
                    query:GetUInt32(6),
                    query:GetUInt32(7)
                )
                chunk.cursorEntry = entry

                if group and slotIndex and IsArmorSetSlotIndex(slotIndex)
                    and (tonumber(group.templateFullItems[slotIndex]) or 0) == 0 then
                    group.templateFullItems[slotIndex] = entry
                    group.templateTotalCount = group.templateTotalCount + 1
                    group.templateNames[#group.templateNames + 1] = name
                end
            else
                hasMore = true
            end
        until not query:NextRow()

        if hasMore and chunk.cursorEntry <= previousEntry then
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "virtual set template keyset page did not advance"
            )
            return
        end
        if not hasMore then
            FinalizeVirtualTemplateChunk(build, chunk)
        end
    end

    local function AssignVirtualCatalogIds(build)
        local usedIds = {}
        local idsByBaseName = {}
        for _, baseName in ipairs(build.eligibleVirtualBaseNames) do
            local group = build.virtualGroups[baseName]
            if group and group.unlockedCount >= 3 then
                local itemSetId = GetVirtualSetId(baseName)
                while usedIds[itemSetId] do
                    itemSetId = itemSetId - 1
                    if itemSetId < -2147483647 then
                        itemSetId = -1
                    end
                end
                usedIds[itemSetId] = true
                idsByBaseName[baseName] = itemSetId
            end
        end
        return idsByBaseName
    end

    local function NewPublicCatalogRecord(group, itemSetId)
        local name = tostring(group.name or "Unlocked Item Set")
        local unlockedCount = math.max(0, math.floor(tonumber(group.unlockedCount) or 0))
        local totalCount = math.max(0, math.floor(tonumber(group.totalCount) or 0))
        local displayName
        if group.isVirtual and not group.hasExactTotal then
            displayName = string.format("%s (%d pieces)", name, unlockedCount)
        else
            displayName = string.format("%s (%d/%d)", name, unlockedCount, totalCount)
        end

        return {
            id = tonumber(itemSetId) or 0,
            name = name,
            displayName = displayName,
            fullItems = NormalizeAppearanceSetItemIds(group.fullItems),
            unlockedItems = NormalizeAppearanceSetItemIds(group.unlockedItems),
            unlockedCount = unlockedCount,
            totalCount = totalCount,
            isVirtual = group.isVirtual == true,
            hasExactTotal = group.hasExactTotal == true,
        }
    end

    local function CompleteAccountItemSetCatalogBuild(build)
        local catalog = {}
        for itemsetId, group in pairs(build.officialGroups) do
            if not group.invalid and group.unlockedCount > 0 and group.totalCount > 0 then
                catalog[#catalog + 1] = NewPublicCatalogRecord(group, itemsetId)
            end
        end

        local virtualIdsByBaseName = AssignVirtualCatalogIds(build)
        for baseName, itemSetId in pairs(virtualIdsByBaseName) do
            local group = build.virtualGroups[baseName]
            if group and group.unlockedCount >= 3 and group.totalCount > 0 then
                catalog[#catalog + 1] = NewPublicCatalogRecord(group, itemSetId)
            end
        end

        table.sort(catalog, function(left, right)
            if left.name == right.name then
                return tonumber(left.id) < tonumber(right.id)
            end
            return tostring(left.name) < tostring(right.name)
        end)

        local index = {}
        local byId = {}
        for _, setData in ipairs(catalog) do
            setData.iconItemId = GetItemSetCatalogIconItemId(setData)
            byId[setData.id] = setData
            index[#index + 1] = {
                id = setData.id,
                name = setData.name,
                displayName = setData.displayName,
                unlockedCount = setData.unlockedCount,
                totalCount = setData.totalCount,
                isVirtual = setData.isVirtual,
                hasExactTotal = setData.hasExactTotal,
                iconItemId = setData.iconItemId,
            }
        end

        local pending = build.pendingByPlayer or {}
        ACCOUNT_ITEM_SET_CATALOG_INDEX_CACHE[build.accountId] = index
        ACCOUNT_ITEM_SET_CATALOG_BY_ID_CACHE[build.accountId] = byId
        FinishAccountItemSetCatalogBuildLifecycle(build)

        for _, request in pairs(pending) do
            local player = ResolveCatalogRequestPlayer(request, build.accountId)
            if player and SendItemSetCatalogPage then
                SendCatalogResponseSafely(
                    SendItemSetCatalogPage,
                    build.accountId,
                    player,
                    index,
                    request
                )
            end
        end
    end

    RunAccountItemSetCatalogBuildStep = function(build)
        if not build or not build.active
            or ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[build.accountId] ~= build then
            return
        end

        build.sliceCount = (tonumber(build.sliceCount) or 0) + 1
        if build.sliceCount > ITEM_SET_CATALOG_MAX_BUILD_SLICES then
            FailAccountItemSetCatalogBuild(
                build,
                "The item-set catalog is too large to load safely.",
                "catalog build exceeded its bounded slice limit"
            )
            return
        end

        local now, clockKind = GetServerTimestamp()
        local clockDiscontinuity = build.deadlineAt and (
            now <= 0
            or clockKind ~= build.deadlineClockKind
            or now < build.startedAt
        )
        if build.deadlineAt and (clockDiscontinuity or now >= build.deadlineAt) then
            FailAccountItemSetCatalogBuild(
                build,
                "The item-set catalog took too long to load. Please try again.",
                clockDiscontinuity
                    and "catalog build clock changed while enforcing its deadline"
                    or "catalog build exceeded its wall-clock deadline"
            )
            return
        end

        if build.phase == "snapshot" then
            local queryOK, query = pcall(AuthDBQuery, string.format(
                "SELECT COALESCE(MAX(unlocked_item_id), 0) FROM account_transmog WHERE account_id = %u",
                build.accountId
            ))
            if not queryOK or not query then
                FailAccountItemSetCatalogBuild(
                    build,
                    "Item sets could not be loaded. Please try again.",
                    "account collection snapshot was uncertain"
                )
                return
            end
            build.snapshotMaxItemId = tonumber(query:GetUInt32(0)) or 0
            build.scanCursor = 0
            build.phase = "scan"
        elseif build.phase == "scan" then
            ScanNextAccountItemSetCatalogBatch(build)
        elseif build.phase == "official_templates" then
            LoadNextOfficialTemplatePage(build)
        elseif build.phase == "virtual_templates" then
            LoadNextVirtualTemplatePage(build)
        elseif build.phase == "finalize" then
            CompleteAccountItemSetCatalogBuild(build)
            return
        else
            FailAccountItemSetCatalogBuild(
                build,
                "Item sets could not be loaded. Please try again.",
                "unknown catalog build phase"
            )
            return
        end

        if build.active then
            QueueAccountItemSetCatalogBuildStep(build)
        end
    end

    local function NewAccountItemSetCatalogBuild(accountGUID)
        accountGUID = tonumber(accountGUID)
        if not accountGUID or accountGUID <= 0 then
            return nil, "Invalid account."
        end
        if ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT >= ITEM_SET_CATALOG_MAX_ACTIVE_BUILDS then
            return nil, "The item-set catalog service is busy. Please try again in a moment."
        end

        local startedAt, deadlineClockKind = GetServerTimestamp()
        local build = {
            accountId = accountGUID,
            phase = "snapshot",
            active = true,
            queued = false,
            snapshotMaxItemId = 0,
            scanCursor = 0,
            officialGroups = {},
            virtualGroups = {},
            pendingByPlayer = {},
            pendingPlayerCount = 0,
            sliceCount = 0,
            startedAt = startedAt,
            deadlineClockKind = deadlineClockKind,
            deadlineAt = startedAt > 0 and (startedAt + ITEM_SET_CATALOG_MAX_BUILD_SECONDS) or nil,
        }
        ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[accountGUID] = build
        ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT = ACTIVE_ACCOUNT_ITEM_SET_CATALOG_BUILD_COUNT + 1
        return build
    end

    local function CaptureCatalogPageRequest(player, requestToken, page, pageSize, search)
        if not IsAppearanceBuddyPlayer(player)
            or not player.GetAccountId or not player.GetGUIDLow then
            return nil
        end

        local accountOK, accountGUID = pcall(player.GetAccountId, player)
        local guidLowOK, playerGUIDLow = pcall(player.GetGUIDLow, player)
        accountGUID = accountOK and tonumber(accountGUID) or nil
        playerGUIDLow = guidLowOK and tonumber(playerGUIDLow) or nil
        if not accountGUID or accountGUID <= 0 or not playerGUIDLow or playerGUIDLow <= 0 then
            return nil
        end

        requestToken = tonumber(requestToken)
        if not requestToken or requestToken ~= requestToken
            or requestToken < 0 or requestToken > 2147483647 then
            requestToken = 0
        end

        return {
            accountId = accountGUID,
            playerGUIDLow = playerGUIDLow,
            requestToken = math.floor(requestToken),
            page = page,
            pageSize = pageSize,
            search = search,
        }
    end

    local function QueueAccountItemSetCatalogPageRequest(player, requestToken, page, pageSize, search)
        local request = CaptureCatalogPageRequest(player, requestToken, page, pageSize, search)
        if not request then
            return false, "The item-set request could not be identified. Please try again."
        end

        local build = ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[request.accountId]
        local created = false
        if not build then
            local errorMessage
            build, errorMessage = NewAccountItemSetCatalogBuild(request.accountId)
            if not build then
                return false, errorMessage
            end
            created = true
        end

        local requestKey = tostring(request.accountId) .. ":" .. tostring(request.playerGUIDLow)
        if not build.pendingByPlayer[requestKey] then
            if build.pendingPlayerCount >= ITEM_SET_CATALOG_MAX_PENDING_PLAYERS then
                if created then
                    FinishAccountItemSetCatalogBuildLifecycle(build)
                end
                return false, "Too many players are waiting for this item-set catalog. Please try again."
            end
            build.pendingPlayerCount = build.pendingPlayerCount + 1
        end
        -- A client timeout, search debounce, or explicit refresh supersedes the old
        -- context for this character. Only the newest token can receive a response.
        build.pendingByPlayer[requestKey] = request

        if created and not QueueAccountItemSetCatalogBuildStep(build) then
            -- The shared scheduler failure already emitted a deterministic failure
            -- to every queued request, including this one.
            return true
        end
        return true
    end

    local function EnsureAccountItemSetCatalogBuild(accountGUID)
        accountGUID = tonumber(accountGUID)
        if not accountGUID or accountGUID <= 0 then
            return false, "Invalid account."
        end
        if ACCOUNT_ITEM_SET_CATALOG_INDEX_CACHE[accountGUID] then
            return true
        end
        if ACCOUNT_ITEM_SET_CATALOG_BUILD_BY_ACCOUNT[accountGUID] then
            return false, "The item-set catalog is still loading. Please try again."
        end

        local build, errorMessage = NewAccountItemSetCatalogBuild(accountGUID)
        if not build then
            return false, errorMessage
        end
        if not QueueAccountItemSetCatalogBuildStep(build) then
            return false, "The item-set catalog worker is unavailable. Please try again."
        end
        return false, "The item-set catalog is loading. Please try again."
    end

    local function BuildAccountItemSetCatalogIndex(accountGUID)
        accountGUID = tonumber(accountGUID)
        local index = accountGUID and ACCOUNT_ITEM_SET_CATALOG_INDEX_CACHE[accountGUID] or nil
        return index or {}, index ~= nil
    end

    local function GetCachedAccountItemSetById(accountGUID, itemSetId)
        accountGUID = tonumber(accountGUID)
        itemSetId = tonumber(itemSetId)
        local byId = accountGUID and ACCOUNT_ITEM_SET_CATALOG_BY_ID_CACHE[accountGUID] or nil
        return byId and byId[itemSetId] or nil
    end

    local function GetCatalogPlayerAccountId(player)
        if not player or type(player.GetAccountId) ~= "function" then
            return nil
        end
        local accountOK, accountGUID = pcall(player.GetAccountId, player)
        accountGUID = accountOK and tonumber(accountGUID) or nil
        if not accountGUID or accountGUID ~= math.floor(accountGUID) or accountGUID <= 0 then
            return nil
        end
        return accountGUID
    end

    local function CollectItemSetTemplateIds(setData, itemIds, seenItemIds)
        if type(setData) ~= "table" then
            return
        end

        local function collect(items)
            for index in ipairs(APPEARANCE_SET_SLOTS) do
                local itemId = tonumber(items and items[index])
                if itemId and itemId == math.floor(itemId) and itemId > 0
                    and itemId <= 4294967295 and not seenItemIds[itemId] then
                    seenItemIds[itemId] = true
                    itemIds[#itemIds + 1] = itemId
                end
            end
        end

        collect(setData.fullItems)
        collect(setData.unlockedItems)
    end

    local function BuildPlayerEligibleItemSetRecord(player, setData, context)
        if type(setData) ~= "table" or not context then
            return nil
        end

        local sourceFullItems = NormalizeAppearanceSetItemIds(setData.fullItems)
        local sourceUnlockedItems = NormalizeAppearanceSetItemIds(setData.unlockedItems)
        local fullItems = NewEmptyAppearanceSetItemIds()
        local unlockedItems = NewEmptyAppearanceSetItemIds()
        local unlockedCount = 0
        local totalCount = 0

        for index, slotInfo in ipairs(APPEARANCE_SET_SLOTS) do
            local fullItemId = sourceFullItems[index]
            local unlockedItemId = sourceUnlockedItems[index]
            local fullTemplate = fullItemId > 0 and ITEM_TEMPLATE_CACHE[fullItemId] or nil
            local unlockedTemplate = unlockedItemId > 0 and ITEM_TEMPLATE_CACHE[unlockedItemId] or nil
            local fullAllowed = type(fullTemplate) == "table"
                and AppearanceEligibility.Allows(player, slotInfo.slot, fullTemplate, context)
            local unlockedAllowed = type(unlockedTemplate) == "table"
                and AppearanceEligibility.Allows(player, slotInfo.slot, unlockedTemplate, context)

            -- A complete set can include an inaccessible source item while the
            -- player owns a lower-level look for that same slot.  Show that
            -- eligible unlocked look instead; never send the gated source ID
            -- to the client as a preview or an icon candidate.
            if fullAllowed then
                fullItems[index] = fullItemId
            elseif unlockedAllowed then
                fullItems[index] = unlockedItemId
            end

            if unlockedAllowed and fullItems[index] > 0 then
                unlockedItems[index] = unlockedItemId
                unlockedCount = unlockedCount + 1
            end
            if fullItems[index] > 0 then
                totalCount = totalCount + 1
            end
        end

        -- A set that contains no usable owned appearance should not expose a
        -- high-level preview just because another character unlocked it.
        if unlockedCount == 0 then
            return nil
        end

        local name = tostring(setData.name or "Unlocked Item Set")
        local isVirtual = setData.isVirtual == true
        local hasExactTotal = setData.hasExactTotal == true
        local displayName
        if isVirtual and not hasExactTotal then
            displayName = string.format("%s (%d pieces)", name, unlockedCount)
        else
            displayName = string.format("%s (%d/%d)", name, unlockedCount, totalCount)
        end

        local record = {
            id = tonumber(setData.id) or 0,
            name = name,
            displayName = displayName,
            fullItems = fullItems,
            unlockedItems = unlockedItems,
            unlockedCount = unlockedCount,
            totalCount = totalCount,
            isVirtual = isVirtual,
            hasExactTotal = hasExactTotal,
        }
        record.iconItemId = GetItemSetCatalogIconItemId(record)
        return record
    end

    local function GetPlayerEligibleItemSetRecord(player, setData)
        local context = AppearanceEligibility.GetContext(player)
        if not context then
            return nil, false
        end

        local itemIds = {}
        CollectItemSetTemplateIds(setData, itemIds, {})
        if not PreloadItemTemplateInfos(itemIds) then
            return nil, false
        end
        return BuildPlayerEligibleItemSetRecord(player, setData, context), true
    end

    local function GetPlayerEligibleItemSetIndex(player, index)
        local accountGUID = GetCatalogPlayerAccountId(player)
        local context = AppearanceEligibility.GetContext(player)
        if not accountGUID or not context then
            return {}, false
        end

        local sourceSets = {}
        local itemIds = {}
        local seenItemIds = {}
        for _, indexRecord in ipairs(index or {}) do
            local setData = GetCachedAccountItemSetById(accountGUID, indexRecord.id)
            if setData then
                sourceSets[#sourceSets + 1] = setData
                CollectItemSetTemplateIds(setData, itemIds, seenItemIds)
            end
        end
        if not PreloadItemTemplateInfos(itemIds) then
            return {}, false
        end

        local eligibleIndex = {}
        for _, setData in ipairs(sourceSets) do
            local record = BuildPlayerEligibleItemSetRecord(player, setData, context)
            if record then
                eligibleIndex[#eligibleIndex + 1] = record
            end
        end
        return eligibleIndex, true
    end

    return {
        GetIndex = BuildAccountItemSetCatalogIndex,
        GetById = GetCachedAccountItemSetById,
        GetEligibleIndexForPlayer = GetPlayerEligibleItemSetIndex,
        GetEligibleSetForPlayer = GetPlayerEligibleItemSetRecord,
        QueuePage = QueueAccountItemSetCatalogPageRequest,
        EnsureBuild = EnsureAccountItemSetCatalogBuild,
        Invalidate = CancelAccountItemSetCatalogBuild,
        SetPageResponder = function(sendPage)
            SendItemSetCatalogPage = sendPage
        end,
    }
end)()

local function CalculateSlot(slot)
    if slot == 0 then
        slot = 1
    elseif slot >= 2 then
        slot = slot + 1
    end
    return CALC + (slot * 2)
end

CalculateSlotReverse = function(slot)
    local reverseSlot = (slot - CALC) / 2
    if reverseSlot == 1 then
        return 0
    elseif reverseSlot >= 3 then
        return reverseSlot - 1
    end
    return reverseSlot
end

local function InitializePlayerTransmog(playerGUID)
    playerGUID = tonumber(playerGUID)
    if not playerGUID or playerGUID <= 0 then
        return false
    end

    local states, loadSucceeded = LoadStoredTransmogStates(playerGUID)
    if not loadSucceeded then
        return false
    end
    local values = {}
    for _, slot in ipairs(VISIBLE_SLOTS) do
        if not states[slot] then
            table.insert(values, string.format("(%u, %u, NULL, 0)", playerGUID, slot))
        end
    end
    if #values == 0 then
        return true
    end

    local insertOK = pcall(CharDBQuery,
        "INSERT INTO character_transmog (player_guid, slot, item, real_item) VALUES " .. table.concat(values, ", ")
    )
    if not insertOK then
        return false
    end

    local verifiedStates, verified = LoadStoredTransmogStates(playerGUID)
    if not verified then
        return false
    end
    for _, slot in ipairs(VISIBLE_SLOTS) do
        if not verifiedStates[slot] then
            return false
        end
    end
    return true
end

local function HasUnlockedAppearance(accountGUID, itemId)
    return AuthDBQuery(string.format(
        "SELECT 1 FROM account_transmog WHERE account_id = %u AND unlocked_item_id = %u LIMIT 1",
        tonumber(accountGUID) or 0,
        tonumber(itemId) or 0
    )) ~= nil
end

local function AddTransmogToAccount(player, itemTemplate)
    if not TRANSMOG_PERSISTENCE_SCHEMA_READY then
        return false
    end
    local accountGUID = player:GetAccountId()
    local itemId = tonumber(itemTemplate:GetItemId()) or 0
    if itemId <= 0 then
        return false
    end

    -- Loot hooks must not build the whole account cache just to decide whether
    -- one item is already unlocked.  A primary-key lookup is bounded; the full
    -- cache remains a UI-time concern.
    local appearanceCache = ACCOUNT_APPEARANCE_CACHE[accountGUID]
    if appearanceCache and appearanceCache.byItemId[itemId] then
        return false
    end
    if not appearanceCache and HasUnlockedAppearance(accountGUID, itemId) then
        return false
    end

    local displayId = itemTemplate:GetDisplayId()
    local inventoryType = itemTemplate:GetInventoryType()
    local appearanceRemoved, removedLoadSucceeded = IsAccountAppearanceRemoved(accountGUID, displayId)
    if not removedLoadSucceeded or appearanceRemoved then
        return false
    end
    local itemName = EscapeString(itemTemplate:GetName())
    
    local query = string.format(
        "INSERT IGNORE INTO account_transmog (account_id, unlocked_item_id, display_id, inventory_type, item_name) " ..
        "VALUES (%d, %d, %d, %d, '%s')",
        accountGUID, itemId, displayId, inventoryType, itemName
    )
    local writeOK = pcall(AuthDBQuery, query)
    local verifyOK, persisted = false, nil
    if writeOK then
        verifyOK, persisted = pcall(AuthDBQuery, string.format(
            "SELECT 1 FROM account_transmog WHERE account_id = %u AND unlocked_item_id = %u LIMIT 1",
            accountGUID,
            itemId
        ))
    end
    if not verifyOK or not persisted then
        return false
    end
    InvalidateAccountCaches(accountGUID)
    AIO.Handle(player, "Transmog", "ItemSetCatalogInvalidated")
    return true
end

local function IsTransmoggableItem(class, inventoryType)
    return (class == 2 or class == 4)
        and INVENTORY_TYPE_TO_SLOT_INDEX[tonumber(inventoryType)] ~= nil
        and not UNUSABLE_INVENTORY_TYPES[inventoryType]
end

local function SafeGetItemByPos(player, bag, slot)
    if not player or not player.GetItemByPos then
        return nil
    end

    local ok, item = pcall(player.GetItemByPos, player, bag, slot)
    if not ok then
        return nil
    end

    return item
end

GetEquippedItemId = function(player, equipSlot)
    local item = SafeGetItemByPos(player, 255, equipSlot)
    if not item then
        return 0
    end

    if item.GetEntry then
        local ok, itemId = pcall(item.GetEntry, item)
        itemId = ok and tonumber(itemId) or 0
        if itemId and itemId > 0 then
            return math.floor(itemId)
        end
    end

    if item.GetItemTemplate then
        local okTemplate, itemTemplate = pcall(item.GetItemTemplate, item)
        if okTemplate and itemTemplate and itemTemplate.GetItemId then
            local okItemId, itemId = pcall(itemTemplate.GetItemId, itemTemplate)
            itemId = okItemId and tonumber(itemId) or 0
            if itemId and itemId > 0 then
                return math.floor(itemId)
            end
        end
    end

    return 0
end

-- The visible fields can contain transmog display entries, so the inventory is
-- the only authoritative source for whether an equipment slot is actually
-- occupied. Reconcile all slots together to survive missed equip events,
-- script reloads, and characters that were already geared when this script was
-- installed.
local function RefreshStoredEquippedItems(player)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow then
        return {}, false
    end

    local playerGUID = tonumber(player:GetGUIDLow())
    local states, loadSucceeded = LoadStoredTransmogStates(playerGUID)
    if not loadSucceeded then
        return states, false
    end

    local inserts = {}
    local changed = {}
    local expected = {}
    for _, visibleSlot in ipairs(VISIBLE_SLOTS) do
        local equipSlot = math.floor(CalculateSlotReverse(visibleSlot))
        local itemId = GetEquippedItemId(player, equipSlot)
        local state = states[visibleSlot]
        if not state then
            inserts[#inserts + 1] = string.format("(%u, %u, NULL, %u)", playerGUID, visibleSlot, itemId)
            expected[visibleSlot] = { item = nil, realItemId = itemId }
        elseif state.realItemId ~= itemId then
            changed[visibleSlot] = { item = state.item, realItemId = itemId }
            expected[visibleSlot] = changed[visibleSlot]
        end
    end

    if #inserts > 0 then
        local insertOK = pcall(CharDBQuery,
            "INSERT INTO character_transmog (`player_guid`, `slot`, `item`, `real_item`) VALUES "
            .. table.concat(inserts, ", ")
        )
        if not insertOK then
            return states, false
        end
    end

    local updateSQL = BuildTransmogStateUpdateSQL(playerGUID, changed)
    if updateSQL and not pcall(CharDBQuery, updateSQL) then
        return states, false
    end

    if next(expected) == nil then
        return states, true
    end

    local refreshed, verified = VerifyTransmogStates(playerGUID, expected)
    return refreshed, verified
end

local function NormalizeCosmeticWeaponEnchantSlot(equipSlot)
    equipSlot = tonumber(equipSlot)
    if not equipSlot or equipSlot ~= math.floor(equipSlot) then
        return nil
    end

    equipSlot = math.floor(equipSlot)
    if not COSMETIC_WEAPON_ENCHANT_SLOT_SET[equipSlot] then
        return nil
    end

    return equipSlot
end

local function NormalizeCosmeticWeaponEnchantId(enchantId)
    enchantId = tonumber(enchantId)
    if not enchantId or enchantId ~= enchantId or enchantId ~= math.floor(enchantId) then
        return nil
    end

    enchantId = math.floor(enchantId)
    if not COSMETIC_WEAPON_ENCHANT_ID_SET[enchantId] then
        return nil
    end

    return enchantId
end

local function LoadCosmeticWeaponEnchantCache(playerGUID, forceReload)
    playerGUID = tonumber(playerGUID)
    if not playerGUID or playerGUID <= 0 then
        return nil, false
    end

    local cached = COSMETIC_WEAPON_ENCHANT_CACHE_BY_PLAYER[playerGUID]
    if cached and not forceReload then
        return cached, true
    end

    local state = { [15] = 0, [16] = 0, [17] = 0 }
    local stored = { [15] = false, [16] = false, [17] = false }
    local queryOK, result = pcall(CharDBQuery, string.format(
        "SELECT equipment_slot, enchant_id FROM character_transmog_weapon_enchant WHERE player_guid = %u",
        playerGUID
    ))
    if not queryOK then
        return nil, false
    end

    if result then
        repeat
            local equipSlot = NormalizeCosmeticWeaponEnchantSlot(result:GetUInt32(0))
            local enchantId = NormalizeCosmeticWeaponEnchantId(result:GetUInt32(1))
            if equipSlot and enchantId ~= nil then
                if stored[equipSlot] and state[equipSlot] ~= enchantId then
                    return nil, false
                end
                state[equipSlot] = enchantId
                stored[equipSlot] = true
            end
        until not result:NextRow()
    else
        local countOK, countQuery = pcall(CharDBQuery, string.format(
            "SELECT COUNT(*) FROM character_transmog_weapon_enchant WHERE player_guid = %u",
            playerGUID
        ))
        if not countOK or not countQuery or (tonumber(countQuery:GetUInt32(0)) or -1) ~= 0 then
            return nil, false
        end
    end

    cached = { state = state, stored = stored }
    COSMETIC_WEAPON_ENCHANT_CACHE_BY_PLAYER[playerGUID] = cached
    return cached, true
end

local function GetStoredCosmeticWeaponEnchant(playerGUID, equipSlot)
    equipSlot = NormalizeCosmeticWeaponEnchantSlot(equipSlot)
    local cached, loadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUID, false)
    if not equipSlot or not loadSucceeded then
        return 0, false, false
    end
    return cached.state[equipSlot] or 0, cached.stored[equipSlot] == true, true
end

local function WriteCosmeticWeaponEnchantPlans(playerGUID, plans, restorePrevious)
    local deleteSlots = {}
    local values = {}
    local expected = {}
    for _, plan in ipairs(plans or {}) do
        local equipSlot = NormalizeCosmeticWeaponEnchantSlot(plan.equipSlot)
        if equipSlot then
            local shouldStore = restorePrevious and plan.previousEnchantStored or not plan.clear
            local enchantId = restorePrevious and plan.previousEnchantId or plan.enchantId
            if shouldStore then
                enchantId = NormalizeCosmeticWeaponEnchantId(enchantId)
                if enchantId == nil then
                    return false
                end
                values[#values + 1] = string.format("(%u, %u, %u)", playerGUID, equipSlot, enchantId)
                expected[equipSlot] = { stored = true, enchantId = enchantId }
            else
                deleteSlots[#deleteSlots + 1] = tostring(equipSlot)
                expected[equipSlot] = { stored = false, enchantId = 0 }
            end
        end
    end

    if #deleteSlots > 0 then
        local deleteOK = pcall(CharDBQuery, string.format(
            "DELETE FROM character_transmog_weapon_enchant WHERE player_guid = %u AND equipment_slot IN (%s)",
            tonumber(playerGUID) or 0,
            table.concat(deleteSlots, ",")
        ))
        if not deleteOK then
            return false
        end
    end
    if #values > 0 then
        local insertOK = pcall(CharDBQuery,
            "INSERT INTO character_transmog_weapon_enchant (`player_guid`, `equipment_slot`, `enchant_id`) VALUES "
            .. table.concat(values, ",")
            .. " ON DUPLICATE KEY UPDATE enchant_id = VALUES(enchant_id)"
        )
        if not insertOK then
            return false
        end
    end

    local cached, loadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUID, true)
    if not loadSucceeded then
        return false
    end
    for equipSlot, wanted in pairs(expected) do
        if cached.stored[equipSlot] ~= wanted.stored
            or (wanted.stored and cached.state[equipSlot] ~= wanted.enchantId) then
            return false
        end
    end
    return true
end

local function IsWeaponItem(item)
    if not item or not item.GetClass then
        return false
    end

    local ok, itemClass = pcall(item.GetClass, item)
    return ok and tonumber(itemClass) == 2
end

-- Main-hand and off-hand cosmetic enchants accept weapons.  The ranged slot is
-- deliberately stricter: only wands use weapon enchant visuals there.
local function IsCosmeticWeaponEnchantEligibleItem(equipSlot, item)
    if not IsWeaponItem(item) then
        return false
    end

    if equipSlot ~= 17 then
        return true
    end

    if not item.GetSubClass then
        return false
    end

    local ok, itemSubclass = pcall(item.GetSubClass, item)
    return ok and tonumber(itemSubclass) == 19
end

local function NormalizeVisibleWeaponEnchantId(enchantId)
    enchantId = tonumber(enchantId)
    if not enchantId or enchantId ~= enchantId then
        return nil
    end

    enchantId = math.floor(enchantId)
    if enchantId < 0 or enchantId > 65535 then
        return nil
    end

    return enchantId
end

local function GetItemEnchantId(item, enchantSlot)
    if not item or not item.GetEnchantmentId then
        return 0
    end

    enchantSlot = tonumber(enchantSlot)
    if not enchantSlot or enchantSlot ~= math.floor(enchantSlot) or enchantSlot < 0 or enchantSlot > 6 then
        return 0
    end

    local ok, enchantId = pcall(item.GetEnchantmentId, item, enchantSlot)
    if not ok then
        return 0
    end

    return NormalizeVisibleWeaponEnchantId(enchantId) or 0
end

local function GetPermanentEnchantId(item)
    return GetItemEnchantId(item, PERMANENT_ENCHANTMENT_SLOT)
end

local function IsShaman(player)
    if not player or not player.GetClass then
        return false
    end

    local ok, class = pcall(player.GetClass, player)
    return ok and tonumber(class) == AppearanceEligibility.ShamanClassId
end

local function GetVisibleShamanImbueEnchantId(player, item)
    if not IsShaman(player) then
        return 0
    end

    local enchantId = GetItemEnchantId(item, TEMPORARY_ENCHANTMENT_SLOT)
    return SHAMAN_IMBUE_ENCHANT_ID_SET[enchantId] and enchantId or 0
end

local function SetVisibleWeaponEnchant(player, equipSlot, enchantId, temporaryEnchantId)
    equipSlot = NormalizeCosmeticWeaponEnchantSlot(equipSlot)
    enchantId = NormalizeVisibleWeaponEnchantId(enchantId)
    if not player or not equipSlot or enchantId == nil
        or not player.SetUInt32Value or not player.GetUInt32Value then
        return false
    end

    local visibleEnchantField = CalculateSlot(equipSlot) + 1
    if temporaryEnchantId == nil then
        local readOK, currentValue = pcall(player.GetUInt32Value, player, visibleEnchantField)
        currentValue = readOK and tonumber(currentValue) or 0
        temporaryEnchantId = math.floor(currentValue / 65536) % 65536
    else
        temporaryEnchantId = NormalizeVisibleWeaponEnchantId(temporaryEnchantId)
        if temporaryEnchantId == nil then
            return false
        end
    end

    -- PLAYER_VISIBLE_ITEM_*_ENCHANTMENT packs permanent and temporary visual
    -- enchant IDs into one uint32.  Write and verify the complete field so a
    -- core update cannot leave a stale half behind.
    local packedEnchant = enchantId + (temporaryEnchantId * 65536)
    local writeOK = pcall(player.SetUInt32Value, player, visibleEnchantField, packedEnchant)
    if not writeOK then
        return false
    end

    local readOK, visibleEnchant = pcall(player.GetUInt32Value, player, visibleEnchantField)
    return readOK and tonumber(visibleEnchant) == packedEnchant
end

local function ApplyStoredCosmeticWeaponEnchant(player, equipSlot, equippedItem)
    if not player then
        return false
    end

    equipSlot = NormalizeCosmeticWeaponEnchantSlot(equipSlot)
    if not equipSlot then
        return false
    end

    local item = equippedItem or SafeGetItemByPos(player, 255, equipSlot)
    local cosmeticEnchantId, hasStoredEnchant = GetStoredCosmeticWeaponEnchant(player:GetGUIDLow(), equipSlot)
    local temporaryEnchantId = GetItemEnchantId(item, TEMPORARY_ENCHANTMENT_SLOT)
    if cosmeticEnchantId > 0 and IsCosmeticWeaponEnchantEligibleItem(equipSlot, item) then
        return SetVisibleWeaponEnchant(player, equipSlot, cosmeticEnchantId, temporaryEnchantId)
    end

    if hasStoredEnchant and cosmeticEnchantId == 0 then
        -- Only an active Shaman imbue remains visible when the player chose
        -- "No Enchantment".  The item itself is never altered.
        return SetVisibleWeaponEnchant(player, equipSlot, 0, GetVisibleShamanImbueEnchantId(player, item))
    end

    -- Restore the item's real enchant visuals without modifying the item itself.
    return SetVisibleWeaponEnchant(player, equipSlot, GetPermanentEnchantId(item), temporaryEnchantId)
end

local function ApplyStoredCosmeticWeaponEnchants(player)
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        ApplyStoredCosmeticWeaponEnchant(player, equipSlot)
    end
end

local function RefreshNoEnchantVisualActivity(player)
    if not player or not player.GetGUIDLow then
        return false
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    if not playerGUID then
        return false
    end

    local cached, loadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUID, false)
    if not loadSucceeded then
        -- Preserve unknown state. Combat hooks only read this cache, so a
        -- transient character-DB failure cannot become a durable false value.
        return nil, false
    end

    local active = false
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        if cached.stored[equipSlot] == true and (cached.state[equipSlot] or 0) == 0 then
            active = true
            break
        end
    end

    NO_ENCHANT_VISUAL_ACTIVE_BY_PLAYER[playerGUID] = active
    return active, true
end

-- Some core item updates are emitted just after an equip or item change and
-- can overwrite PLAYER_VISIBLE_ITEM_*_ENCHANTMENT. Reapply an explicit
-- no-enchant choice once those updates have settled.
local function ScheduleNoEnchantVisualReapply(player, equipSlot)
    equipSlot = NormalizeCosmeticWeaponEnchantSlot(equipSlot)
    if not player or not equipSlot or not CreateLuaEvent or not GetPlayerByGUID
        or not player.GetGUID or not player.GetGUIDLow then
        return
    end

    local guidLowOK, playerGUIDLow = pcall(player.GetGUIDLow, player)
    playerGUIDLow = guidLowOK and tonumber(playerGUIDLow) or nil
    if not playerGUIDLow then
        return
    end
    local enchantId, hasStoredEnchant = GetStoredCosmeticWeaponEnchant(playerGUIDLow, equipSlot)
    if not hasStoredEnchant or enchantId ~= 0 then
        return
    end

    local pendingBySlot = NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUIDLow]
    if pendingBySlot and pendingBySlot[equipSlot] then
        return
    end

    local ok, playerGUID = pcall(player.GetGUID, player)
    if not ok or not playerGUID then
        return
    end

    if not pendingBySlot then
        pendingBySlot = {}
        NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUIDLow] = pendingBySlot
    end
    pendingBySlot[equipSlot] = true
    local pendingTimers = 0
    local function reapply()
        pcall(function()
            local playerOK, livePlayer = pcall(GetPlayerByGUID, playerGUID)
            if playerOK and livePlayer then
                ApplyStoredCosmeticWeaponEnchant(livePlayer, equipSlot)
            end
        end)

        pendingTimers = pendingTimers - 1
        if pendingTimers <= 0 then
            local activeBySlot = NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUIDLow]
            if activeBySlot then
                activeBySlot[equipSlot] = nil
                if next(activeBySlot) == nil then
                    NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUIDLow] = nil
                end
            end
        end
    end

    for _, delay in ipairs({50, 250}) do
        local scheduled, eventId = pcall(CreateLuaEvent, reapply, delay, 1)
        if scheduled and eventId then
            pendingTimers = pendingTimers + 1
        end
    end
    if pendingTimers == 0 then
        pendingBySlot[equipSlot] = nil
        if next(pendingBySlot) == nil then
            NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUIDLow] = nil
        end
    end
end

local function ScheduleAllNoEnchantVisualReapply(player)
    if not player then return end
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        ScheduleNoEnchantVisualReapply(player, equipSlot)
    end
end

local function ApplyNoEnchantVisualsForPlayer(player)
    local active, loadSucceeded = RefreshNoEnchantVisualActivity(player)
    if not loadSucceeded then
        return false
    end
    if not active then
        return true
    end

    local applied = true
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        local enchantId, hasStoredEnchant = GetStoredCosmeticWeaponEnchant(player:GetGUIDLow(), equipSlot)
        if hasStoredEnchant and enchantId == 0 then
            if ApplyStoredCosmeticWeaponEnchant(player, equipSlot) then
                ScheduleNoEnchantVisualReapply(player, equipSlot)
            else
                applied = false
            end
        end
    end
    return applied
end

local function ScheduleNoEnchantVisualLoadRetry(player)
    if not player or type(CreateLuaEvent) ~= "function" or type(GetPlayerByGUID) ~= "function"
        or not player.GetGUIDLow or not player.GetGUID then
        return false
    end

    local guidLowOK, playerGUIDLow = pcall(player.GetGUIDLow, player)
    local guidOK, playerGUID = pcall(player.GetGUID, player)
    playerGUIDLow = guidLowOK and tonumber(playerGUIDLow) or nil
    if not playerGUIDLow or not guidOK or playerGUID == nil then
        return false
    end
    if NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUIDLow] then
        return true
    end

    local retryToken = {}
    local playerGUIDText = tostring(playerGUID)
    NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUIDLow] = retryToken
    local scheduledOK, eventId = pcall(CreateLuaEvent, function()
        if NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUIDLow] ~= retryToken then
            return
        end
        NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUIDLow] = nil

        local lookupOK, onlinePlayer = pcall(GetPlayerByGUID, playerGUID)
        if not lookupOK or not IsAppearanceBuddyPlayer(onlinePlayer)
            or not onlinePlayer.GetGUIDLow or not onlinePlayer.GetGUID then
            return
        end
        local currentLowOK, currentGUIDLow = pcall(onlinePlayer.GetGUIDLow, onlinePlayer)
        local currentGUIDOK, currentGUID = pcall(onlinePlayer.GetGUID, onlinePlayer)
        if not currentLowOK or tonumber(currentGUIDLow) ~= playerGUIDLow
            or not currentGUIDOK or tostring(currentGUID) ~= playerGUIDText then
            return
        end

        local _, loadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUIDLow, true)
        if loadSucceeded then
            ApplyNoEnchantVisualsForPlayer(onlinePlayer)
        end
    end, 1000, 1)
    if not scheduledOK or eventId == nil or eventId == false then
        NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUIDLow] = nil
        return false
    end
    return true
end

local function ReapplyNoEnchantVisualsForOnlinePlayers()
    if not GetPlayersInWorld then
        return
    end

    local playersOK, players = pcall(GetPlayersInWorld)
    if not playersOK or type(players) ~= "table" then
        return
    end

    for _, player in ipairs(players) do
        if IsAppearanceBuddyPlayer(player) then
            TrackAppearanceBuddyPlayerOnline(player)

            -- `.reload ale` does not fire a player login. Re-run the full
            -- appearance resolver before declaring the character hydrated so
            -- a newly introduced eligibility rule (including RequiredLevel)
            -- immediately restores an ineligible stored look to real gear.
            -- Transmog_Load also reapplies and schedules cosmetic enchants.
            local loadOK, loaded = pcall(Transmog_Load, player)
            if not loadOK or loaded ~= true then
                -- Keep the prior best-effort no-enchant recovery for a
                -- transient transmog-state failure, but never mark the player
                -- hydrated until the authoritative load has succeeded.
                if player.GetGUIDLow then
                    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
                    if guidOK and tonumber(playerGUID) then
                        PLAYER_TRANSMOG_HYDRATED[tonumber(playerGUID)] = nil
                    end
                end
                local applyOK, applied = pcall(ApplyNoEnchantVisualsForPlayer, player)
                if not applyOK or applied ~= true then
                    ScheduleNoEnchantVisualLoadRetry(player)
                end
            end
        end
    end
end

local function GetCosmeticWeaponEnchantState(player)
    local state = { [15] = 0, [16] = 0, [17] = 0 }
    local explicitNoSlots = { [15] = false, [16] = false, [17] = false }
    if not player then
        return state, explicitNoSlots, false
    end

    local cached, loadSucceeded = LoadCosmeticWeaponEnchantCache(player:GetGUIDLow(), false)
    if not loadSucceeded then
        return state, explicitNoSlots, false
    end

    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        state[equipSlot] = cached.state[equipSlot] or 0
        explicitNoSlots[equipSlot] = cached.stored[equipSlot] == true and state[equipSlot] == 0
    end
    return state, explicitNoSlots, true
end

local function GetCosmeticWeaponEnchantEligibleSlots(player)
    local eligibleSlots = {}
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        eligibleSlots[equipSlot] = player
            and IsCosmeticWeaponEnchantEligibleItem(equipSlot, SafeGetItemByPos(player, 255, equipSlot))
            or false
    end

    return eligibleSlots
end

local function SyncCosmeticWeaponEnchantState(player)
    if player then
        local enchantState, explicitNoSlots, loadSucceeded = GetCosmeticWeaponEnchantState(player)
        if not loadSucceeded then return end
        AIO.Handle(
            player,
            "Transmog",
            "SetWeaponEnchantStateClient",
            enchantState,
            GetCosmeticWeaponEnchantEligibleSlots(player),
            explicitNoSlots
        )
    end
end

local function GetBagSlotCount(player, bag)
    if not player then
        return 0
    end

    if bag == 0 then
        if player.GetBagSize then
            local ok, size = pcall(player.GetBagSize, player, bag)
            if ok and size and size > 0 then
                return size
            end
        end
        return 16
    end

    local bagItem = SafeGetItemByPos(player, 255, bag)
    if not bagItem or not bagItem.GetBagSize then
        return 0
    end

    local ok, size = pcall(bagItem.GetBagSize, bagItem)
    if ok and size and size > 0 then
        return size
    end

    return 0
end

local function QueueTransmogToAccount(player, itemTemplate, values, seenItemIds, knownItemIds)
    if not player or not itemTemplate or type(values) ~= "table" then
        return false
    end

    local accountGUID = player:GetAccountId()
    local itemId = itemTemplate:GetItemId()
    if seenItemIds and seenItemIds[itemId] then
        return false
    end

    if knownItemIds and knownItemIds[itemId] then
        return false
    end

    local displayId = itemTemplate:GetDisplayId()
    local inventoryType = itemTemplate:GetInventoryType()
    local appearanceRemoved, removedLoadSucceeded = IsAccountAppearanceRemoved(accountGUID, displayId)
    if not removedLoadSucceeded or appearanceRemoved then
        return false
    end
    local itemName = EscapeString(itemTemplate:GetName())
    values[#values + 1] = string.format("(%d, %d, %d, %d, '%s')", accountGUID, itemId, displayId, inventoryType, itemName)

    if seenItemIds then
        seenItemIds[itemId] = true
    end

    return true
end

local function TryUnlockAppearanceFromItem(player, item, values, seenItemIds, knownItemIds)
    if not player or not item or not item.GetItemTemplate then
        return false
    end

    local okTemplate, itemTemplate = pcall(item.GetItemTemplate, item)
    if not okTemplate or not itemTemplate then
        return false
    end

    local okClass, class = pcall(itemTemplate.GetClass, itemTemplate)
    local okInventoryType, inventoryType = pcall(itemTemplate.GetInventoryType, itemTemplate)
    if not okClass or not okInventoryType then
        return false
    end

    if not IsTransmoggableItem(class, inventoryType) then
        return false
    end

    if values then
        return QueueTransmogToAccount(player, itemTemplate, values, seenItemIds, knownItemIds)
    end

    return AddTransmogToAccount(player, itemTemplate)
end

local function ScanPlayerInventoryForTransmogUnlocks(player)
    if not player then
        return 0
    end

    local accountGUID = player:GetAccountId()
    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    if not appearanceCache.loadSucceeded then
        error("appearance collection could not be read")
    end
    local knownItemIds = appearanceCache.byItemId
    local values = {}
    local seen = {}
    local seenItemIds = {}
    local function visitItem(item)
        if not item then
            return
        end

        local guidLow = item.GetGUIDLow and item:GetGUIDLow() or nil
        if guidLow then
            if seen[guidLow] then
                return
            end
            seen[guidLow] = true
        end

        TryUnlockAppearanceFromItem(player, item, values, seenItemIds, knownItemIds)
    end

    for slot = 0, 18 do
        visitItem(SafeGetItemByPos(player, 255, slot))
    end

    local backpackSlots = GetBagSlotCount(player, 0)
    for slot = 23, 22 + backpackSlots do
        visitItem(SafeGetItemByPos(player, 255, slot))
    end

    for bagSlot = 19, 22 do
        local bagItem = SafeGetItemByPos(player, 255, bagSlot)
        if bagItem then
            visitItem(bagItem)

            local bagSize = GetBagSlotCount(player, bagSlot)
            for slot = 0, bagSize - 1 do
                visitItem(SafeGetItemByPos(player, bagSlot, slot))
            end
        end
    end

    if #values > 0 then
        local writeOK = pcall(AuthDBQuery,
            "INSERT IGNORE INTO account_transmog (account_id, unlocked_item_id, display_id, inventory_type, item_name) VALUES "
            .. table.concat(values, ", ")
        )
        local itemIds = {}
        for itemId in pairs(seenItemIds) do
            itemIds[#itemIds + 1] = tostring(tonumber(itemId) or 0)
        end
        local verifyOK, persisted = false, nil
        if writeOK and #itemIds > 0 then
            verifyOK, persisted = pcall(AuthDBQuery, string.format(
                "SELECT COUNT(*) FROM account_transmog WHERE account_id = %u AND unlocked_item_id IN (%s)",
                accountGUID,
                table.concat(itemIds, ",")
            ))
        end
        if not verifyOK or not persisted or (tonumber(persisted:GetUInt32(0)) or -1) ~= #itemIds then
            error("inventory unlock persistence could not be verified")
        end
        InvalidateAccountCaches(accountGUID)
        AIO.Handle(player, "Transmog", "ItemSetCatalogInvalidated")
    end
    return #values
end

local function Transmog_OnCharacterCreate(event, player)
    if IsAppearanceBuddyPlayer(player) then
        InitializePlayerTransmog(player:GetGUIDLow())
    end
end

local function Transmog_OnCharacterDelete(event, guid)
    guid = tonumber(guid)
    if guid and guid > 0 and guid == math.floor(guid) then
        pcall(CharDBQuery, string.format("DELETE FROM character_transmog WHERE player_guid = %u", guid))
        pcall(CharDBQuery, string.format("DELETE FROM character_transmog_weapon_enchant WHERE player_guid = %u", guid))
        local stateVerified, remainingState = pcall(CharDBQuery, string.format(
            "SELECT COUNT(*) FROM character_transmog WHERE player_guid = %u",
            guid
        ))
        local enchantVerified, remainingEnchants = pcall(CharDBQuery, string.format(
            "SELECT COUNT(*) FROM character_transmog_weapon_enchant WHERE player_guid = %u",
            guid
        ))
        if not stateVerified or not remainingState
            or (tonumber(remainingState:GetUInt32(0)) or -1) ~= 0
            or not enchantVerified or not remainingEnchants
            or (tonumber(remainingEnchants:GetUInt32(0)) or -1) ~= 0 then
            print(string.format(
                "[AppearanceBuddy Transmog] WARNING: character-delete cleanup could not be verified for guid %u",
                guid
            ))
        end
        NO_ENCHANT_VISUAL_ACTIVE_BY_PLAYER[guid] = nil
        NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[guid] = nil
        NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[guid] = nil
        RANDOM_PREVIEW_NEXT_ALLOWED_BY_PLAYER[guid] = nil
        APPEARANCE_MUTATION_ACTIVE_BY_PLAYER[guid] = nil
        APPEARANCE_MUTATION_NEXT_ALLOWED_BY_PLAYER[guid] = nil
        INVENTORY_SCAN_NEXT_ALLOWED_BY_PLAYER[guid] = nil
        COSMETIC_WEAPON_ENCHANT_CACHE_BY_PLAYER[guid] = nil
        EXPENSIVE_REQUEST_BUDGET_BY_PLAYER[guid] = nil
        FREE_TRANSMOG_ENABLED_BY_PLAYER[guid] = nil
        PLAYER_TRANSMOG_HYDRATED[guid] = nil
        LOGIN_TRANSMOG_RESTORE_PENDING[guid] = nil
    end
end

local function FindOnlineAppearanceBuddyPlayer(playerGUID, accountGUID)
    if type(GetPlayersInWorld) ~= "function" then
        return nil
    end

    local playersOK, players = pcall(GetPlayersInWorld)
    if not playersOK or type(players) ~= "table" then
        return nil
    end

    for _, candidate in ipairs(players) do
        if IsAppearanceBuddyPlayer(candidate)
            and candidate.GetGUIDLow and candidate.GetAccountId then
            local guidOK, candidateGUID = pcall(candidate.GetGUIDLow, candidate)
            local accountOK, candidateAccount = pcall(candidate.GetAccountId, candidate)
            if guidOK and accountOK
                and tonumber(candidateGUID) == playerGUID
                and tonumber(candidateAccount) == accountGUID then
                return candidate
            end
        end
    end

    return nil
end

-- Player inventory and visible-item fields can finish loading shortly after
-- PLAYER_EVENT_ON_LOGIN. Rehydrate twice from a freshly acquired Player wrapper
-- so a timing race cannot leave a valid saved look appearing to vanish.
local function ScheduleLoginTransmogRestore(player)
    if not IsAppearanceBuddyPlayer(player) or type(CreateLuaEvent) ~= "function"
        or type(GetPlayersInWorld) ~= "function" or not player.GetGUIDLow or not player.GetAccountId then
        return false
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    accountGUID = accountOK and tonumber(accountGUID) or nil
    if not playerGUID or playerGUID <= 0 or not accountGUID or accountGUID <= 0 then
        return false
    end

    if LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] then
        return true
    end

    local restoreToken = {}
    local remainingCalls = 2
    LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] = restoreToken
    local scheduledOK, eventId = pcall(CreateLuaEvent, function()
        if LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] ~= restoreToken then
            return
        end

        local onlinePlayer = FindOnlineAppearanceBuddyPlayer(playerGUID, accountGUID)
        if onlinePlayer and type(Transmog_Load) == "function" then
            pcall(Transmog_Load, onlinePlayer)
        end

        remainingCalls = remainingCalls - 1
        if remainingCalls <= 0 then
            LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] = nil
        end
    end, 750, 2)
    if not scheduledOK or not eventId then
        LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] = nil
        return false
    end
    return true
end

local function Transmog_OnLogout(event, player)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow then
        return
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    local accountOK, accountGUID = false, nil
    if player.GetAccountId then
        accountOK, accountGUID = pcall(player.GetAccountId, player)
    end
    accountGUID = accountOK and tonumber(accountGUID) or nil
    if playerGUID then
        NO_ENCHANT_VISUAL_ACTIVE_BY_PLAYER[playerGUID] = nil
        NO_ENCHANT_VISUAL_SLOT_REAPPLY_PENDING[playerGUID] = nil
        NO_ENCHANT_VISUAL_LOAD_RETRY_PENDING[playerGUID] = nil
        RANDOM_PREVIEW_NEXT_ALLOWED_BY_PLAYER[playerGUID] = nil
        APPEARANCE_MUTATION_ACTIVE_BY_PLAYER[playerGUID] = nil
        APPEARANCE_MUTATION_NEXT_ALLOWED_BY_PLAYER[playerGUID] = nil
        INVENTORY_SCAN_NEXT_ALLOWED_BY_PLAYER[playerGUID] = nil
        COSMETIC_WEAPON_ENCHANT_CACHE_BY_PLAYER[playerGUID] = nil
        EXPENSIVE_REQUEST_BUDGET_BY_PLAYER[playerGUID] = nil
        FREE_TRANSMOG_ENABLED_BY_PLAYER[playerGUID] = nil
        PLAYER_TRANSMOG_HYDRATED[playerGUID] = nil
        LOGIN_TRANSMOG_RESTORE_PENDING[playerGUID] = nil
    end
    EvictAccountCachesIfUnused(accountGUID, playerGUID)
end

local function Transmog_OnWeaponEnchantVisualUpdate(event, player)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow then
        return
    end
    local guidOK, playerGUIDLow = pcall(player.GetGUIDLow, player)
    playerGUIDLow = guidOK and tonumber(playerGUIDLow) or nil
    if playerGUIDLow and NO_ENCHANT_VISUAL_ACTIVE_BY_PLAYER[playerGUIDLow] == true then
        ScheduleAllNoEnchantVisualReapply(player)
    end
end

local function Transmog_OnLogin(event, player)
    if not IsAppearanceBuddyPlayer(player) then
        return
    end
    TrackAppearanceBuddyPlayerOnline(player)
    local restored = Transmog_Load(player)
    ScheduleLoginTransmogRestore(player)
    if restored ~= true then
        ScheduleNoEnchantVisualLoadRetry(player)
    end
    if AUTO_UNLOCK_INVENTORY_ON_LOGIN then
        ScanPlayerInventoryForTransmogUnlocks(player)
    end
end

local function Transmog_OnLootItem(event, player, item, count)
    if event ~= 51 and event ~= 52 and event ~= 53 and event ~= 56 then return end
    if not IsAppearanceBuddyPlayer(player) or not item or not item.GetItemTemplate then return end

    local okTpl, tpl = pcall(item.GetItemTemplate, item)
    if not okTpl or not tpl then return end

    local okClass, class       = pcall(tpl.GetClass, tpl)
    local okType,  inventoryType = pcall(tpl.GetInventoryType, tpl)
    if not okClass or not okType then return end

    if IsTransmoggableItem(class, inventoryType) then
        AddTransmogToAccount(player, tpl)
    end
end

local function Transmog_OnEquipItem(event, player, item, bag, slot)
    if not IsAppearanceBuddyPlayer(player) or not item then return end

    -- Event 29 fires after an item is equipped, so reapply any saved illusion.
    local cosmeticEquipSlot = NormalizeCosmeticWeaponEnchantSlot(slot)
    if cosmeticEquipSlot then
        ApplyStoredCosmeticWeaponEnchant(player, cosmeticEquipSlot, item)
        ScheduleNoEnchantVisualReapply(player, cosmeticEquipSlot)
    end

    local playerGUID   = player:GetGUIDLow()
    local itemTemplate = item:GetItemTemplate()
    local class        = item:GetClass()
    local inventoryType = itemTemplate:GetInventoryType()

    if not IsTransmoggableItem(class, inventoryType) then return end

    AddTransmogToAccount(player, itemTemplate)

    local constSlot = CalculateSlot(slot)
    local itemId    = itemTemplate:GetItemId()
    local states, loadSucceeded = RefreshStoredEquippedItems(player)
    local state = loadSucceeded and states[constSlot] or nil
    if not state then return end

    local transmogItem = state.item
    if transmogItem and transmogItem > 0 then
        local resolvedItems, resolutionCertain = ResolveStoredAppearanceItems(
            player,
            { [constSlot] = transmogItem }
        )
        local resolvedItem = resolvedItems[constSlot]
        if not resolutionCertain then
            return
        elseif not resolvedItem then
            -- An unresolved entry can be a legacy look that a newer policy no
            -- longer permits, or a temporarily unavailable collection lookup.
            -- Never turn either condition into an irreversible character-row
            -- deletion merely because the player equipped an item.
            player:SetUInt32Value(constSlot, itemId)
            return
        end

        if resolvedItem ~= transmogItem then
            if not WriteTransmogStates(playerGUID, {
                [constSlot] = { item = resolvedItem, realItemId = itemId },
            }) then
                return
            end
            transmogItem = resolvedItem
        end
    end
    if transmogItem == nil or (transmogItem == 0 and not PLAYER_TRANSMOG_HYDRATED[playerGUID]) then return end

    player:SetUInt32Value(constSlot, transmogItem)
end

function TransmogHandlers.OnUnequipItem(player)
    if not IsAppearanceBuddyPlayer(player) then return end
    if not ConsumeExpensiveRequestBudget(player, 2) then return end
    Transmog_Load(player)
end

Transmog_Load = function(player)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow or not player.GetAccountId then
        return false
    end

    local playerGUID = tonumber(player:GetGUIDLow())
    local states, loadSucceeded = RefreshStoredEquippedItems(player)
    if not loadSucceeded then
        return false
    end

    local requestedBySlot = {}
    for slot, state in pairs(states) do
        if state.item and state.item > 0 then
            requestedBySlot[slot] = state.item
        end
    end
    local resolvedBySlot, resolutionSucceeded = ResolveStoredAppearanceItems(
        player,
        requestedBySlot
    )
    if not resolutionSucceeded then
        return false
    end

    local corrected = {}
    for _, slot in ipairs(VISIBLE_SLOTS) do
        local state = states[slot]
        if not state then
            return false
        end
        if state.item and state.item > 0 then
            local resolvedItem = resolvedBySlot[slot]
            if not resolvedItem then
                -- Resolution is a runtime permission check, not ownership of
                -- the stored selection. Preserve unresolved values so a policy
                -- change, delayed collection read, or explicit user action can
                -- recover them; render the real item below in the meantime.
            elseif resolvedItem ~= state.item then
                state.item = resolvedItem
                corrected[slot] = { item = resolvedItem, realItemId = state.realItemId }
            end
        end
    end
    if next(corrected) ~= nil and not WriteTransmogStates(playerGUID, corrected) then
        return false
    end

    for _, slot in ipairs(VISIBLE_SLOTS) do
        local state = states[slot]
        local visibleItemId = 0
        if state.realItemId > 0 then
            local resolvedItem = resolvedBySlot[slot]
            if state.item == 0 then
                visibleItemId = 0
            elseif state.item and state.item > 0 and resolvedItem then
                visibleItemId = state.item
            else
                visibleItemId = state.realItemId
            end
        end
        player:SetUInt32Value(slot, visibleItemId)
    end

    local _, enchantLoadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUID, false)
    if not enchantLoadSucceeded then
        return false
    end
    RefreshNoEnchantVisualActivity(player)
    ApplyStoredCosmeticWeaponEnchants(player)
    for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
        ScheduleNoEnchantVisualReapply(player, equipSlot)
    end
    PLAYER_TRANSMOG_HYDRATED[playerGUID] = true
    return true
end

function TransmogHandlers.LoadPlayer(player)
    -- Compatibility for pre-V2 clients: login already restored authoritative
    -- server state, so this legacy message must not repeat database hydration.
    if IsAppearanceBuddyPlayer(player) then
        AIO.Handle(player, "Transmog", "LoadTransmogsAfterSave")
    end
end

function TransmogHandlers.ScanInventoryUnlocks(player, requestToken)
    local token = tonumber(requestToken) or 0
    if not IsAppearanceBuddyPlayer(player) then
        return
    end
    if not TRANSMOG_PERSISTENCE_SCHEMA_READY then
        AIO.Handle(player, "Transmog", "ScanInventoryUnlocksResult", token, 0, "Inventory scan is disabled until the server database migration is applied.")
        return
    end
    local playerGUID = player and player.GetGUIDLow and tonumber(player:GetGUIDLow()) or nil
    if not playerGUID then
        AIO.Handle(player, "Transmog", "ScanInventoryUnlocksResult", token, 0, "Inventory scan could not start.")
        return
    end

    local now = GetServerTimestamp()
    local nextAllowed = tonumber(INVENTORY_SCAN_NEXT_ALLOWED_BY_PLAYER[playerGUID]) or 0
    if now > 0 and now < nextAllowed then
        AIO.Handle(player, "Transmog", "ScanInventoryUnlocksResult", token, 0, "Inventory scan is cooling down. Please wait a few seconds.")
        return
    end
    if now > 0 then
        INVENTORY_SCAN_NEXT_ALLOWED_BY_PLAYER[playerGUID] = now + INVENTORY_SCAN_MIN_INTERVAL_SECONDS
    end

    local ok, addedCount = pcall(ScanPlayerInventoryForTransmogUnlocks, player)
    if not ok then
        print(string.format(
            "[AppearanceBuddy Transmog] inventory scan failed for player %s: %s",
            tostring(playerGUID),
            tostring(addedCount)
        ))
        AIO.Handle(player, "Transmog", "ScanInventoryUnlocksResult", token, 0, "Inventory scan failed. Please try again.")
        return
    end
    AIO.Handle(player, "Transmog", "ScanInventoryUnlocksResult", token, tonumber(addedCount) or 0, "")
end

function TransmogHandlers.GetWeaponEnchantState(player)
    if not IsAppearanceBuddyPlayer(player) then return end
    if not ConsumeExpensiveRequestBudget(player, 1) then return end
    ApplyNoEnchantVisualsForPlayer(player)
    SyncCosmeticWeaponEnchantState(player)
end

function TransmogHandlers.GetTransmogCostState(player, requestToken)
    if not IsAppearanceBuddyPlayer(player) then return end
    SyncTransmogCostState(player, requestToken)
end

local function BuildTransmogStateV2(player)
    if not IsAppearanceBuddyPlayer(player) then return nil end

    local playerGUID = player:GetGUIDLow()
    local states, loadSucceeded = RefreshStoredEquippedItems(player)
    if not loadSucceeded then
        return nil
    end
    local slots = {}
    local requestedBySlot = {}
    for slot, state in pairs(states) do
        if state.item and state.item > 0 then
            requestedBySlot[slot] = state.item
        end
    end
    local resolvedBySlot, resolutionSucceeded = ResolveStoredAppearanceItems(
        player,
        requestedBySlot
    )
    if not resolutionSucceeded then
        return nil
    end

    local corrected = {}
    for _, slot in ipairs(VISIBLE_SLOTS) do
        local state = states[slot]
        if not state then
            return nil
        end
        local item = state.item
        if item and item > 0 then
            local resolvedItem = resolvedBySlot[slot]
            if not resolvedItem then
                -- Keep the stored request intact. The V2 snapshot describes
                -- what can render now, so expose the equipped item until this
                -- appearance can be resolved again.
                item = nil
            elseif resolvedItem ~= item then
                item = resolvedItem
                corrected[slot] = { item = item, realItemId = state.realItemId }
            end
        end

        local mode = "original"
        if item == 0 then
            mode = "hidden"
        elseif item and item > 0 then
            mode = "appearance"
        end
        slots[slot] = {
            mode = mode,
            itemId = tonumber(item) or 0,
            realItemId = math.max(0, math.floor(state.realItemId)),
        }
    end
    if next(corrected) ~= nil and not WriteTransmogStates(playerGUID, corrected) then
        return nil
    end

    if not PLAYER_TRANSMOG_HYDRATED[playerGUID] then
        for _, slot in ipairs(VISIBLE_SLOTS) do
            local state = slots[slot]
            local visibleItemId = 0
            if state.realItemId > 0 then
                visibleItemId = state.mode == "original" and state.realItemId or state.itemId
            end
            player:SetUInt32Value(slot, visibleItemId)
        end
    end
    PLAYER_TRANSMOG_HYDRATED[playerGUID] = true

    return slots
end

function TransmogHandlers.GetTransmogStateV2(player, requestToken)
    local token = tonumber(requestToken)
    if not token or token ~= token or token <= -math.huge or token >= math.huge then
        token = 0
    else
        token = math.floor(token)
    end

    if not IsAppearanceBuddyPlayer(player) then
        return
    end
    if not ConsumeExpensiveRequestBudget(player, 1) then
        AIO.Handle(
            player,
            "Transmog",
            "TransmogStateV2Failed",
            token,
            2,
            "Transmog state is temporarily rate-limited. Close and reopen this window to retry."
        )
        return
    end
    local slots = BuildTransmogStateV2(player)
    if not slots then
        AIO.Handle(
            player,
            "Transmog",
            "TransmogStateV2Failed",
            token,
            2,
            "Transmog state could not be loaded. Close and reopen this window to retry."
        )
        return
    end

    local enchantState, explicitNoSlots, enchantLoadSucceeded = GetCosmeticWeaponEnchantState(player)
    if not enchantLoadSucceeded then
        AIO.Handle(
            player,
            "Transmog",
            "TransmogStateV2Failed",
            token,
            2,
            "Transmog state could not be loaded. Close and reopen this window to retry."
        )
        return
    end
    ApplyNoEnchantVisualsForPlayer(player)
    AIO.Handle(
        player,
        "Transmog",
        "TransmogStateV2",
        token,
        2,
        slots,
        enchantState,
        GetCosmeticWeaponEnchantEligibleSlots(player),
        explicitNoSlots,
        BuildTransmogSlotCosts(player),
        GetPlayerCoinage(player)
    )
end

-- PLAYER_VISIBLE_ITEM contains the chosen appearance, not the equipped item.
-- Keep a tiny read-only endpoint for client tooltip code that needs the real
-- equipment while the transmog window is closed. This deliberately avoids the
-- database, collection cache, and all appearance mutation paths.
local TOOLTIP_EQUIPMENT_STATE_PROTOCOL_VERSION = 1

local function BuildTooltipEquipmentState(player)
    local itemIds = {}
    for _, visibleSlot in ipairs(VISIBLE_SLOTS) do
        local equipmentSlot = math.floor(CalculateSlotReverse(visibleSlot))
        itemIds[visibleSlot] = GetEquippedItemId(player, equipmentSlot)
    end
    return itemIds
end

function TransmogHandlers.GetTooltipEquipmentState(player, requestToken)
    if not IsAppearanceBuddyPlayer(player) then return end

    local token = tonumber(requestToken)
    if not token or token ~= token or token < 0 or token > 2147483647 then
        token = 0
    else
        token = math.floor(token)
    end
    local budgetAllowed, retryAfter = ConsumeExpensiveRequestBudget(player, 1)
    if not budgetAllowed then
        AIO.Handle(
            player,
            "Transmog",
            "TooltipEquipmentStateFailed",
            token,
            TOOLTIP_EQUIPMENT_STATE_PROTOCOL_VERSION,
            math.max(0.25, tonumber(retryAfter) or 0.25)
        )
        return
    end

    AIO.Handle(
        player,
        "Transmog",
        "TooltipEquipmentState",
        token,
        TOOLTIP_EQUIPMENT_STATE_PROTOCOL_VERSION,
        BuildTooltipEquipmentState(player)
    )
end

function TransmogHandlers.GetRandomAppearancePreview(player, requestToken, currentPreviewItemIds)
    if not IsAppearanceBuddyPlayer(player) then return end
    local token = tonumber(requestToken) or 0
    local result = NewEmptyAppearanceSetItemIds()
    if not ConsumeExpensiveRequestBudget(player, 2) then
        AIO.Handle(
            player,
            "Transmog",
            "RandomAppearancePreview",
            result,
            token,
            false,
            "Random appearances are being requested too quickly. Please wait a moment."
        )
        return
    end
    local allowed, retryAfter = BeginRandomAppearancePreview(player)
    if not allowed then
        AIO.Handle(player, "Transmog", "RandomAppearancePreviewThrottled", token, retryAfter)
        return
    end

    local accountCache = GetAccountAppearanceCache(player:GetAccountId())
    if accountCache.loadSucceeded ~= true then
        AIO.Handle(
            player,
            "Transmog",
            "RandomAppearancePreview",
            result,
            token,
            false,
            "Unlocked appearances could not be loaded. Please try again."
        )
        return
    end

    for index, info in ipairs(APPEARANCE_SET_SLOTS) do
        local equipSlot = math.floor(CalculateSlotReverse(info.slot))
        if GetEquippedItemId(player, equipSlot) > 0 then
            local eligibleRecords, _, filterLoadSucceeded = FilterAppearanceRecords(
                player,
                accountCache,
                info.slot,
                "all"
            )
            if not filterLoadSucceeded then
                AIO.Handle(
                    player,
                    "Transmog",
                    "RandomAppearancePreview",
                    NewEmptyAppearanceSetItemIds(),
                    token,
                    false,
                    "Appearance metadata could not be loaded. Please try again."
                )
                return
            end

            local choice = nil
            local seen = 0
            local seenDisplays = {}
            local currentItemId = 0
            if type(currentPreviewItemIds) == "table" then
                currentItemId = tonumber(currentPreviewItemIds[index] or currentPreviewItemIds[tostring(index)]) or 0
            end
            for _, record in ipairs(eligibleRecords) do
                local itemId = tonumber(record.itemId) or 0
                local displayId = tonumber(record.displayId) or 0
                local displayBucket = accountCache.bySlotDisplay[info.slot] and accountCache.bySlotDisplay[info.slot][displayId]
                local isCurrentAppearance = currentItemId > 0
                    and type(displayBucket and displayBucket.items) == "table"
                    and displayBucket.items[currentItemId] == true
                if itemId > 0 and displayId > 0 and not seenDisplays[displayId] and not isCurrentAppearance then
                    seenDisplays[displayId] = true
                    seen = seen + 1
                    if math.random(seen) == 1 then
                        choice = itemId
                    end
                end
            end
            result[index] = choice or 0
        end
    end

    AIO.Handle(player, "Transmog", "RandomAppearancePreview", result, token, true, "")
end

local function StoredAppearanceEquals(currentItem, targetItem, targetIsNil)
    if targetIsNil then
        return currentItem == nil, true
    end
    local currentId = tonumber(currentItem)
    local targetId = tonumber(targetItem)
    if currentId == targetId then
        return true, true
    end
    if currentId and currentId > 0 and targetId and targetId > 0 then
        local currentTemplate, currentLoadSucceeded = GetItemTemplateInfo(currentId)
        local targetTemplate, targetLoadSucceeded = GetItemTemplateInfo(targetId)
        if not currentLoadSucceeded or not targetLoadSucceeded then
            return false, false
        end
        local currentDisplay = currentTemplate and tonumber(currentTemplate.displayId) or 0
        local targetDisplay = targetTemplate and tonumber(targetTemplate.displayId) or 0
        return currentDisplay > 0 and currentDisplay == targetDisplay, true
    end
    return false, true
end

local function NewAppearanceRequestResult(errorMessage)
    return {
        appliedCount = 0,
        hiddenCount = 0,
        restoredCount = 0,
        missingSlots = {},
        chargedCost = 0,
        errorMessage = tostring(errorMessage or ""),
        -- Validation and pre-write failures do not need another expensive V2
        -- pull. Flip this to false as soon as money or cosmetic state may have
        -- changed, including compensation/rollback paths.
        suppressStateSync = true,
    }
end

local function ApplyAppearanceRequest(player, itemIds, weaponEnchants, explicitNoWeaponEnchants)
    local result = NewAppearanceRequestResult()
    if not player then return result end

    local requestedExplicitNoWeaponEnchants = explicitNoWeaponEnchants
    if type(requestedExplicitNoWeaponEnchants) ~= "table" and type(weaponEnchants) == "table" then
        requestedExplicitNoWeaponEnchants = weaponEnchants.explicitNo
    end
    local requestedClearWeaponEnchants = type(weaponEnchants) == "table" and weaponEnchants.clear or nil

    local playerGUID = player:GetGUIDLow()
    local storedStates, stateLoadSucceeded = RefreshStoredEquippedItems(player)
    if not stateLoadSucceeded then
        result.errorMessage = "Equipped-item state could not be verified. Please try again."
        return result
    end
    local enchantCache, enchantLoadSucceeded = LoadCosmeticWeaponEnchantCache(playerGUID, false)
    if not enchantLoadSucceeded then
        result.errorMessage = "Weapon-enchant state could not be verified. Please try again."
        return result
    end
    local appearancePlans = {}
    local enchantPlans = {}
    local chargedSlots = {}
    local totalCost = 0
    local baseSlotCost = GetTransmogBaseSlotCost(player)
    local missingSet = {}
    local equippedItemIdsByVisibleSlot = {}
    for _, info in ipairs(APPEARANCE_SET_SLOTS) do
        local equipSlot = math.floor(CalculateSlotReverse(info.slot))
        equippedItemIdsByVisibleSlot[info.slot] = GetEquippedItemId(player, equipSlot)
    end

    local function addMissing(name)
        if name and not missingSet[name] then
            missingSet[name] = true
            table.insert(result.missingSlots, name)
        end
    end

    local function addSlotCost(visibleSlot)
        if not visibleSlot or chargedSlots[visibleSlot] then return end
        chargedSlots[visibleSlot] = true
        totalCost = totalCost + baseSlotCost
    end

    local resolvedRequestedAppearances = {}
    if type(itemIds) == "table" then
        local requestedBySlot = {}
        for index, info in ipairs(APPEARANCE_SET_SLOTS) do
            local requestedItemId = tonumber(itemIds[index])
            if requestedItemId and requestedItemId > 0
                and requestedItemId == math.floor(requestedItemId)
                and requestedItemId <= 4294967295 then
                requestedBySlot[info.slot] = requestedItemId
            end
        end
        local resolutionSucceeded
        resolvedRequestedAppearances, resolutionSucceeded = ResolveStoredAppearanceItems(
            player,
            requestedBySlot
        )
        if not resolutionSucceeded then
            result.errorMessage = "Appearance ownership could not be verified. Please try again."
            return result
        end
    end

    if type(itemIds) == "table" then
        for index, info in ipairs(APPEARANCE_SET_SLOTS) do
            local rawRequest = itemIds[index]
            if rawRequest ~= nil then
                local requestedItemId = tonumber(rawRequest)
                local storedState = storedStates[info.slot]
                local currentItem = storedState and storedState.item or nil
                local storedRealItemId = storedState and storedState.realItemId or 0
                local rowExists = storedState ~= nil
                local realItemId = equippedItemIdsByVisibleSlot[info.slot] or 0
                if not rowExists or tonumber(storedRealItemId) ~= realItemId then
                    result.errorMessage = "Equipped-item state could not be verified. Please try again."
                    return result
                end
                local targetItem = nil
                local targetIsNil = false
                local valid = requestedItemId ~= nil
                    and requestedItemId == requestedItemId
                    and requestedItemId > -math.huge
                    and requestedItemId < math.huge
                    and requestedItemId == math.floor(requestedItemId)
                    and requestedItemId <= 4294967295

                if valid and requestedItemId < 0 then
                    targetIsNil = true
                elseif valid and requestedItemId == 0 then
                    targetItem = 0
                    if realItemId <= 0 then
                        -- Never create persistent hidden state for an empty
                        -- equipment slot; it would take effect later for free.
                        -- Restore (-1) may still clear dormant state safely.
                        valid = false
                        addMissing(info.name.." (no item equipped)")
                    end
                elseif valid and requestedItemId > 0 then
                    targetItem = resolvedRequestedAppearances[info.slot]
                    if not targetItem then
                        valid = false
                        addMissing(info.name)
                    elseif realItemId <= 0 then
                        local matchesCurrent, comparisonSucceeded = StoredAppearanceEquals(
                            currentItem,
                            targetItem,
                            false
                        )
                        if not comparisonSucceeded then
                            result.errorMessage = "Appearance state could not be verified. Please try again."
                            return result
                        end
                        if not matchesCurrent then
                            valid = false
                            addMissing(info.name.." (no item equipped)")
                        end
                    end
                else
                    valid = false
                    addMissing(info.name)
                end

                if valid then
                    local matchesCurrent, comparisonSucceeded = StoredAppearanceEquals(
                        currentItem,
                        targetItem,
                        targetIsNil
                    )
                    if not comparisonSucceeded then
                        result.errorMessage = "Appearance state could not be verified. Please try again."
                        return result
                    end
                    if not matchesCurrent then
                        table.insert(appearancePlans, {
                            info = info,
                            targetItem = targetItem,
                            targetIsNil = targetIsNil,
                            realItemId = realItemId,
                            previousItem = currentItem,
                            previousRealItemId = realItemId,
                            previousVisibleItemId = tonumber(player:GetUInt32Value(info.slot)) or 0,
                        })
                        if realItemId > 0 then addSlotCost(info.slot) end
                    end
                end
            end
        end
    end

    if type(weaponEnchants) == "table" then
        for _, equipSlot in ipairs(COSMETIC_WEAPON_ENCHANT_SLOTS) do
            local rawEnchantId = weaponEnchants[equipSlot]
            if rawEnchantId == nil then rawEnchantId = weaponEnchants[tostring(equipSlot)] end
            local clearValue = type(requestedClearWeaponEnchants) == "table"
                and (requestedClearWeaponEnchants[equipSlot]
                    or requestedClearWeaponEnchants[tostring(equipSlot)])
            if rawEnchantId ~= nil or clearValue == true or clearValue == 1 then
                if rawEnchantId ~= nil and NormalizeCosmeticWeaponEnchantId(rawEnchantId) == nil then
                    result.errorMessage = "Invalid weapon enchant request."
                    return result
                end
                local enchantId = rawEnchantId ~= nil and NormalizeCosmeticWeaponEnchantId(rawEnchantId) or 0
                local currentEnchantId = enchantCache.state[equipSlot] or 0
                local currentEnchantStored = enchantCache.stored[equipSlot] == true
                local equippedItem = SafeGetItemByPos(player, 255, equipSlot)
                local explicitNoValue = type(requestedExplicitNoWeaponEnchants) == "table"
                    and (requestedExplicitNoWeaponEnchants[equipSlot]
                        or requestedExplicitNoWeaponEnchants[tostring(equipSlot)])
                local explicitNoEnchant = enchantId == 0
                    and (explicitNoValue == true or explicitNoValue == 1)
                -- A zero only hides real effects when the client explicitly
                -- marks it as No Enchantment. Bare zeroes (including legacy
                -- saved sets) mean remove the cosmetic override instead.
                local clearWeaponEnchant = clearValue == true or clearValue == 1
                    or (enchantId == 0 and not explicitNoEnchant)
                if clearWeaponEnchant and currentEnchantStored then
                    table.insert(enchantPlans, {
                        equipSlot = equipSlot,
                        enchantId = enchantId,
                        clear = true,
                        previousEnchantId = currentEnchantId,
                        previousEnchantStored = currentEnchantStored,
                    })
                    if equippedItem then
                        addSlotCost(EQUIPMENT_SLOT_TO_VISIBLE_SLOT[equipSlot])
                    end
                elseif ((enchantId and enchantId > 0) or explicitNoEnchant)
                    and not IsCosmeticWeaponEnchantEligibleItem(equipSlot, equippedItem) then
                    addMissing(equipSlot == 15 and "Main Hand" or equipSlot == 16 and "Off-hand" or "Ranged")
                elseif enchantId and (
                    enchantId ~= currentEnchantId
                    or (explicitNoEnchant
                        and not currentEnchantStored
                        and IsCosmeticWeaponEnchantEligibleItem(equipSlot, equippedItem))
                ) then
                    table.insert(enchantPlans, {
                        equipSlot = equipSlot,
                        enchantId = enchantId,
                        previousEnchantId = currentEnchantId,
                        previousEnchantStored = currentEnchantStored,
                    })
                    addSlotCost(EQUIPMENT_SLOT_TO_VISIBLE_SLOT[equipSlot])
                end
            end
        end
    end

    -- A saved outfit is a single user-visible choice. Applying just the
    -- legal-looking fragments makes a local preview appear committed, then
    -- leaves the player surprised after a reload. Refuse the whole request
    -- before charging or writing when any requested slot is unavailable.
    if #result.missingSlots > 0 then
        result.errorMessage = "This appearance set has unavailable or class-restricted slots. No changes were made."
        return result
    end

    local coinageBeforeCharge = GetPlayerCoinage(player)
    if totalCost > coinageBeforeCharge then
        result.errorMessage = "Not enough money for these appearance changes."
        return result
    end
    local chargeSucceeded, chargeUncertain = ChargeTransmogCost(player, totalCost)
    if not chargeSucceeded then
        result.suppressStateSync = not chargeUncertain
        result.errorMessage = "The appearance fee could not be charged."
        return result
    end
    if totalCost > 0 or #appearancePlans > 0 or #enchantPlans > 0 then
        result.suppressStateSync = false
    end
    result.chargedCost = totalCost

    local mutationOK, mutationError = pcall(function()
        local appearanceTargets = {}
        for _, plan in ipairs(appearancePlans) do
            local target = plan.targetItem
            if plan.targetIsNil then
                target = nil
            end
            plan.mutationStarted = true
            appearanceTargets[plan.info.slot] = { item = target, realItemId = plan.realItemId }
        end
        if next(appearanceTargets) ~= nil and not WriteTransmogStates(playerGUID, appearanceTargets) then
            error("appearance persistence verification failed")
        end

        for _, plan in ipairs(appearancePlans) do
            local visibleTarget = plan.targetIsNil and plan.realItemId or plan.targetItem
            player:SetUInt32Value(plan.info.slot, visibleTarget)
            if tonumber(player:GetUInt32Value(plan.info.slot)) ~= tonumber(visibleTarget) then
                error("appearance field verification failed for "..plan.info.name)
            end
        end

        for _, plan in ipairs(enchantPlans) do
            plan.mutationStarted = true
        end
        if #enchantPlans > 0 and not WriteCosmeticWeaponEnchantPlans(playerGUID, enchantPlans, false) then
            error("weapon enchant persistence verification failed")
        end
        if #enchantPlans > 0 then
            RefreshNoEnchantVisualActivity(player)
        end
        for _, plan in ipairs(enchantPlans) do
            if not ApplyStoredCosmeticWeaponEnchant(player, plan.equipSlot) then
                error("weapon enchant visual application failed")
            end
            if not plan.clear and plan.enchantId == 0 then
                ScheduleNoEnchantVisualReapply(player, plan.equipSlot)
            end
        end
    end)

    if not mutationOK then
        local rollbackErrors = {}
        local function attemptRollback(label, operation)
            local ok, err = pcall(operation)
            if not ok then
                rollbackErrors[#rollbackErrors + 1] = label..": "..tostring(err)
            end
        end

        -- Reverse transaction order. Persistence is restored and read-verified
        -- in batches; visual fields are then restored individually.
        local enchantMutationStarted = false
        for _, plan in ipairs(enchantPlans) do
            enchantMutationStarted = enchantMutationStarted or plan.mutationStarted == true
        end
        if enchantMutationStarted then
            attemptRollback("weapon enchant state", function()
                if not WriteCosmeticWeaponEnchantPlans(playerGUID, enchantPlans, true) then
                    error("storage restore failed")
                end
                RefreshNoEnchantVisualActivity(player)
                for index = #enchantPlans, 1, -1 do
                    local plan = enchantPlans[index]
                    if not ApplyStoredCosmeticWeaponEnchant(player, plan.equipSlot) then
                        error("visual restore failed for weapon slot "..tostring(plan.equipSlot))
                    end
                    if plan.previousEnchantStored and plan.previousEnchantId == 0 then
                        ScheduleNoEnchantVisualReapply(player, plan.equipSlot)
                    end
                end
            end)
        end

        local appearanceRollback = {}
        for _, plan in ipairs(appearancePlans) do
            if plan.mutationStarted then
                appearanceRollback[plan.info.slot] = {
                    item = plan.previousItem,
                    realItemId = plan.previousRealItemId,
                }
            end
        end
        if next(appearanceRollback) ~= nil then
            attemptRollback("appearance state", function()
                if not WriteTransmogStates(playerGUID, appearanceRollback) then
                    error("storage restore failed")
                end
                for index = #appearancePlans, 1, -1 do
                    local plan = appearancePlans[index]
                    if plan.mutationStarted then
                        player:SetUInt32Value(plan.info.slot, plan.previousVisibleItemId)
                        if tonumber(player:GetUInt32Value(plan.info.slot)) ~= tonumber(plan.previousVisibleItemId) then
                            error("visible-field restore failed for "..plan.info.name)
                        end
                    end
                end
            end)
        end

        local rollbackOK = #rollbackErrors == 0
        local refunded = rollbackOK and RefundTransmogCost(player, totalCost)
        result.chargedCost = math.max(0, coinageBeforeCharge - GetPlayerCoinage(player))
        print(string.format(
            "[AppearanceBuddy Transmog] mutation failed for player %s: %s%s",
            tostring(playerGUID),
            tostring(mutationError),
            rollbackOK and "" or ("; rollback errors: "..table.concat(rollbackErrors, " | "))
        ))
        if rollbackOK and refunded then
            result.chargedCost = 0
            result.errorMessage = "Appearance changes could not be saved; all changes were rolled back and the fee was refunded."
        elseif rollbackOK then
            result.errorMessage = "Appearance changes were rolled back, but the fee refund failed. Contact an administrator."
        else
            result.errorMessage = "Appearance changes failed and rollback could not be verified; the fee was retained. Contact an administrator."
        end
        return result
    end

    for _, plan in ipairs(appearancePlans) do
        if plan.targetIsNil then
            result.restoredCount = result.restoredCount + 1
        elseif plan.targetItem == 0 then
            result.hiddenCount = result.hiddenCount + 1
        else
            result.appliedCount = result.appliedCount + 1
        end
    end

    return result
end

local function ExecuteAppearanceRequest(player, itemIds, weaponEnchants, explicitNoWeaponEnchants)
    if not IsAppearanceBuddyPlayer(player) or not player.GetGUIDLow then
        return NewAppearanceRequestResult("Invalid player state.")
    end

    local guidOK, playerGUID = pcall(player.GetGUIDLow, player)
    playerGUID = guidOK and tonumber(playerGUID) or nil
    if not playerGUID then
        return NewAppearanceRequestResult("Invalid player state.")
    end

    if not TRANSMOG_PERSISTENCE_SCHEMA_READY then
        local result = NewAppearanceRequestResult(
            "Appearance changes are temporarily disabled until the server database migration is applied."
        )
        return result
    end

    if not ConsumeExpensiveRequestBudget(player, 3) then
        local result = NewAppearanceRequestResult("Appearance requests are being submitted too quickly. Please wait a moment.")
        return result
    end

    if APPEARANCE_MUTATION_ACTIVE_BY_PLAYER[playerGUID] then
        local result = NewAppearanceRequestResult("Another appearance change is already in progress.")
        return result
    end

    local now = GetServerTimestamp()
    local nextAllowed = tonumber(APPEARANCE_MUTATION_NEXT_ALLOWED_BY_PLAYER[playerGUID]) or 0
    if now > 0 and now < nextAllowed then
        local retryAfter = nextAllowed - now
        if retryAfter <= APPEARANCE_MUTATION_MIN_INTERVAL_SECONDS * 2 then
            local result = NewAppearanceRequestResult("Appearance changes are being submitted too quickly. Please wait a moment.")
            return result
        end
    end
    if now > 0 then
        APPEARANCE_MUTATION_NEXT_ALLOWED_BY_PLAYER[playerGUID] = now + APPEARANCE_MUTATION_MIN_INTERVAL_SECONDS
    end

    APPEARANCE_MUTATION_ACTIVE_BY_PLAYER[playerGUID] = true
    local ok, result = pcall(
        ApplyAppearanceRequest,
        player,
        itemIds,
        weaponEnchants,
        explicitNoWeaponEnchants
    )
    APPEARANCE_MUTATION_ACTIVE_BY_PLAYER[playerGUID] = nil

    if ok and type(result) == "table" then
        return result
    end

    print(string.format(
        "[AppearanceBuddy Transmog] unhandled mutation error for player %s: %s",
        tostring(playerGUID),
        tostring(result)
    ))
    local failed = NewAppearanceRequestResult("The appearance request failed unexpectedly. No retry was attempted.")
    failed.suppressStateSync = false
    return failed
end

local function SendAppearanceRequestResult(player, result, requestToken)
    if not IsAppearanceBuddyPlayer(player) then
        return
    end
    AIO.Handle(
        player,
        "Transmog",
        "AppearanceSetResult",
        result.appliedCount,
        result.hiddenCount,
        table.concat(result.missingSlots, ", "),
        result.restoredCount,
        result.chargedCost,
        result.errorMessage,
        GetPlayerCoinage(player),
        requestToken,
        result.suppressStateSync == true
    )
end

function TransmogHandlers.SetWeaponEnchant(player, equipSlot, enchantId)
    if not IsAppearanceBuddyPlayer(player) then return end
    local requested = {}
    requested[tonumber(equipSlot) or 0] = enchantId
    SendAppearanceRequestResult(player, ExecuteAppearanceRequest(player, nil, requested))
end

function TransmogHandlers.ResetWeaponEnchant(player, equipSlot)
    if not IsAppearanceBuddyPlayer(player) then return end
    local requestedSlot = tonumber(equipSlot) or 0
    local requested = { [requestedSlot] = 0 }
    local explicitNo = { [requestedSlot] = true }
    SendAppearanceRequestResult(player, ExecuteAppearanceRequest(player, nil, requested, explicitNo))
end

function TransmogHandlers.EquipTransmogItem(player, item, slot)
    if not IsAppearanceBuddyPlayer(player) then return end
    slot = NormalizeVisibleSlot(slot)
    if not slot then
        return
    end
    local index = APPEARANCE_SET_INDEX_BY_SLOT[slot]
    if not index then return end

    local requested = {}
    requested[index] = item == nil and -1 or item
    SendAppearanceRequestResult(player, ExecuteAppearanceRequest(player, requested, nil))
end

function TransmogHandlers.ApplyAppearanceSet(player, itemIds, weaponEnchants, explicitNoWeaponEnchants, requestToken)
    if not IsAppearanceBuddyPlayer(player) then return end
    if type(itemIds) ~= "table" then
        SendAppearanceRequestResult(player, NewAppearanceRequestResult("Invalid appearance request."), requestToken)
        return
    end
    SendAppearanceRequestResult(
        player,
        ExecuteAppearanceRequest(player, itemIds, weaponEnchants, explicitNoWeaponEnchants),
        requestToken
    )
end

local function NormalizeItemSetPageSize(pageSize)
    pageSize = tonumber(pageSize)
    if not pageSize or pageSize ~= pageSize or pageSize <= -math.huge or pageSize >= math.huge then
        pageSize = 100
    end
    pageSize = math.floor(pageSize)
    return math.max(1, math.min(100, pageSize))
end

local function FilterItemSetCatalog(index, search)
    local normalizedSearch = string.lower(tostring(search or ""):sub(1, 64))
    if normalizedSearch == "" then
        return index, normalizedSearch
    end

    local matches = {}
    for _, setData in ipairs(index or {}) do
        local haystack = string.lower(tostring(setData.displayName or setData.name or ""))
        local setId = tostring(setData.id or "")
        if haystack:find(normalizedSearch, 1, true)
            or setId:find(normalizedSearch, 1, true) then
            matches[#matches + 1] = setData
        end
    end
    return matches, normalizedSearch
end

ITEM_SET_CATALOG_SERVICE.NormalizeRequestToken = function(requestToken)
    requestToken = tonumber(requestToken)
    if not requestToken or requestToken ~= requestToken
        or requestToken < 0 or requestToken > 2147483647 then
        return 0
    end
    return math.floor(requestToken)
end

ITEM_SET_CATALOG_SERVICE.SendFailure = function(player, requestToken, page, search, message)
    AIO.Handle(
        player,
        "Transmog",
        "InitItemSets",
        {},
        ITEM_SET_CATALOG_SERVICE.NormalizeRequestToken(requestToken),
        NormalizePage(page),
        false,
        0,
        string.lower(tostring(search or ""):sub(1, 64)),
        false,
        tostring(message or "Item sets could not be loaded. Please try again.")
    )
end

ITEM_SET_CATALOG_SERVICE.SendPage = function(player, index, request)
    request = type(request) == "table" and request or {}
    local normalizedPage = NormalizePage(request.page)
    local normalizedPageSize = NormalizeItemSetPageSize(request.pageSize)
    local playerEligibleIndex, eligibilityLoadSucceeded = ITEM_SET_CATALOG_SERVICE.GetEligibleIndexForPlayer(player, index)
    if not eligibilityLoadSucceeded then
        ITEM_SET_CATALOG_SERVICE.SendFailure(
            player,
            request.requestToken,
            normalizedPage,
            request.search,
            "Item-set appearance data could not be loaded. Please try again."
        )
        return
    end

    local filtered, normalizedSearch = FilterItemSetCatalog(playerEligibleIndex, request.search)
    local maxPage = math.max(1, math.ceil(#filtered / normalizedPageSize))
    normalizedPage = math.min(normalizedPage, maxPage)
    local first = (normalizedPage - 1) * normalizedPageSize + 1
    local last = math.min(#filtered, first + normalizedPageSize - 1)
    local result = {}
    for recordIndex = first, last do
        result[#result + 1] = filtered[recordIndex]
    end

    AIO.Handle(
        player,
        "Transmog",
        "InitItemSets",
        result,
        ITEM_SET_CATALOG_SERVICE.NormalizeRequestToken(request.requestToken),
        normalizedPage,
        last < #filtered,
        #filtered,
        normalizedSearch,
        true,
        ""
    )
end

ITEM_SET_CATALOG_SERVICE.SetPageResponder(ITEM_SET_CATALOG_SERVICE.SendPage)

function TransmogHandlers.GetUnlockedItemSets(player, requestToken, page, pageSize, search)
    if not IsAppearanceBuddyPlayer(player) then
        return
    end

    local normalizedPage = NormalizePage(page)
    local normalizedPageSize = NormalizeItemSetPageSize(pageSize)
    local normalizedSearch = string.lower(tostring(search or ""):sub(1, 64))
    if not ConsumeExpensiveRequestBudget(player, 2) then
        ITEM_SET_CATALOG_SERVICE.SendFailure(
            player,
            requestToken,
            normalizedPage,
            normalizedSearch,
            "Item sets are being requested too quickly. Please wait a moment."
        )
        return
    end

    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    accountGUID = accountOK and tonumber(accountGUID) or nil
    if not accountGUID or accountGUID <= 0 then
        ITEM_SET_CATALOG_SERVICE.SendFailure(
            player,
            requestToken,
            normalizedPage,
            normalizedSearch,
            "The item-set request could not be identified. Please try again."
        )
        return
    end

    local index, loadSucceeded = ITEM_SET_CATALOG_SERVICE.GetIndex(accountGUID)
    if loadSucceeded then
        ITEM_SET_CATALOG_SERVICE.SendPage(player, index, {
            requestToken = requestToken,
            page = normalizedPage,
            pageSize = normalizedPageSize,
            search = normalizedSearch,
        })
        return
    end

    local queued, errorMessage = ITEM_SET_CATALOG_SERVICE.QueuePage(
        player,
        requestToken,
        normalizedPage,
        normalizedPageSize,
        normalizedSearch
    )
    if not queued then
        ITEM_SET_CATALOG_SERVICE.SendFailure(
            player,
            requestToken,
            normalizedPage,
            normalizedSearch,
            errorMessage
        )
    end
end

local function SendItemSetDetailsFailure(player, itemsetId, token, message)
    AIO.Handle(
        player,
        "Transmog",
        "ItemSetDetails",
        tonumber(itemsetId) or 0,
        tonumber(token) or 0,
        NewEmptyAppearanceSetItemIds(),
        NewEmptyAppearanceSetItemIds(),
        false,
        tostring(message or "Item-set details could not be loaded. Please try again.")
    )
end

function TransmogHandlers.GetUnlockedItemSetDetails(player, itemsetId, token)
    if not IsAppearanceBuddyPlayer(player) then return end
    itemsetId = tonumber(itemsetId)
    token = ITEM_SET_CATALOG_SERVICE.NormalizeRequestToken(token)
    if not ConsumeExpensiveRequestBudget(player, 1) then
        SendItemSetDetailsFailure(player, itemsetId, token, "Item-set details are being requested too quickly.")
        return
    end

    if not itemsetId or itemsetId ~= itemsetId or itemsetId == 0
        or itemsetId ~= math.floor(itemsetId)
        or itemsetId < -2147483647 or itemsetId > 2147483647 then
        SendItemSetDetailsFailure(player, itemsetId, token, "Invalid item set.")
        return
    end

    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    accountGUID = accountOK and tonumber(accountGUID) or nil
    local _, catalogLoaded = ITEM_SET_CATALOG_SERVICE.GetIndex(accountGUID)
    if not catalogLoaded then
        local _, errorMessage = ITEM_SET_CATALOG_SERVICE.EnsureBuild(accountGUID)
        SendItemSetDetailsFailure(player, itemsetId, token, errorMessage)
        return
    end

    local selectedSet = ITEM_SET_CATALOG_SERVICE.GetById(accountGUID, itemsetId)
    if selectedSet then
        local eligibleSet, eligibilityLoadSucceeded = ITEM_SET_CATALOG_SERVICE.GetEligibleSetForPlayer(player, selectedSet)
        if not eligibilityLoadSucceeded then
            SendItemSetDetailsFailure(
                player,
                itemsetId,
                token,
                "Item-set appearance data could not be loaded. Please try again."
            )
            return
        end
        if not eligibleSet then
            SendItemSetDetailsFailure(
                player,
                itemsetId,
                token,
                "This item set has no appearances available at your current level."
            )
            return
        end
        AIO.Handle(
            player,
            "Transmog",
            "ItemSetDetails",
            itemsetId,
            token,
            NormalizeAppearanceSetItemIds(eligibleSet.fullItems),
            NormalizeAppearanceSetItemIds(eligibleSet.unlockedItems),
            true,
            ""
        )
    else
        SendItemSetDetailsFailure(player, itemsetId, token, "Item set not found.")
    end
end

local function SendUnlockedItemSetResult(player, setName, result, requestToken)
    result = type(result) == "table" and result or NewAppearanceRequestResult("Invalid item-set result.")
    AIO.Handle(
        player,
        "Transmog",
        "UnlockedItemSetResult",
        tostring(setName or "Item set"),
        tonumber(result.appliedCount) or 0,
        tonumber(result.hiddenCount) or 0,
        table.concat(result.missingSlots or {}, ", "),
        tonumber(result.chargedCost) or 0,
        tostring(result.errorMessage or ""),
        GetPlayerCoinage(player),
        requestToken,
        result.suppressStateSync == true
    )
end

-- Catalog previews show complete outfits, but applying one may only mutate
-- appearances the account owns. Hide non-set armor only when that slot exists.
local function BuildUnlockedItemSetRequest(player, eligibleSet)
    local requested = {}
    for index, info in ipairs(APPEARANCE_SET_SLOTS) do
        local unlockedItemId = tonumber(eligibleSet.unlockedItems[index]) or 0
        local previewItemId = tonumber(eligibleSet.fullItems[index]) or 0
        if unlockedItemId > 0 then
            requested[index] = unlockedItemId
        elseif previewItemId <= 0 and IsArmorSetSlotIndex(index) then
            local equipSlot = math.floor(CalculateSlotReverse(info.slot))
            if GetEquippedItemId(player, equipSlot) > 0 then
                requested[index] = 0
            end
        end
    end
    return requested
end

function TransmogHandlers.ApplyUnlockedItemSet(player, itemsetId, requestToken)
    if not IsAppearanceBuddyPlayer(player) then return end
    requestToken = ITEM_SET_CATALOG_SERVICE.NormalizeRequestToken(requestToken)
    if not ConsumeExpensiveRequestBudget(player, 1) then
        SendUnlockedItemSetResult(
            player,
            "Item set",
            NewAppearanceRequestResult("Item-set requests are being submitted too quickly. Please wait a moment."),
            requestToken
        )
        return
    end
    itemsetId = tonumber(itemsetId)
    if not itemsetId or itemsetId ~= itemsetId or itemsetId == 0
        or itemsetId ~= math.floor(itemsetId)
        or itemsetId < -2147483647 or itemsetId > 2147483647 then
        SendUnlockedItemSetResult(player, "Item set", NewAppearanceRequestResult("Invalid item set."), requestToken)
        return
    end

    local accountOK, accountGUID = pcall(player.GetAccountId, player)
    accountGUID = accountOK and tonumber(accountGUID) or nil
    local _, catalogLoaded = ITEM_SET_CATALOG_SERVICE.GetIndex(accountGUID)
    if not catalogLoaded then
        local _, errorMessage = ITEM_SET_CATALOG_SERVICE.EnsureBuild(accountGUID)
        SendUnlockedItemSetResult(
            player,
            "Item set",
            NewAppearanceRequestResult(errorMessage),
            requestToken
        )
        return
    end

    local selectedSet = ITEM_SET_CATALOG_SERVICE.GetById(accountGUID, itemsetId)
    if not selectedSet then
        SendUnlockedItemSetResult(player, "Item set", NewAppearanceRequestResult("Item set not found."), requestToken)
        return
    end

    local eligibleSet, eligibilityLoadSucceeded = ITEM_SET_CATALOG_SERVICE.GetEligibleSetForPlayer(player, selectedSet)
    if not eligibilityLoadSucceeded then
        SendUnlockedItemSetResult(
            player,
            selectedSet.name,
            NewAppearanceRequestResult("Item-set appearance data could not be loaded. Please try again."),
            requestToken
        )
        return
    end
    if not eligibleSet then
        SendUnlockedItemSetResult(
            player,
            selectedSet.name,
            NewAppearanceRequestResult("This item set has no appearances available at your current level."),
            requestToken
        )
        return
    end

    local requested = BuildUnlockedItemSetRequest(player, eligibleSet)

    local result = ExecuteAppearanceRequest(player, requested, nil)
    SendUnlockedItemSetResult(player, eligibleSet.name, result, requestToken)
end

function TransmogHandlers.UnequipTransmogItem(player, slot)
    if not IsAppearanceBuddyPlayer(player) then return end
    TransmogHandlers.EquipTransmogItem(player, 0, slot)
end

function TransmogHandlers.displayTransmog(player, spellid)
    if not IsAppearanceBuddyPlayer(player) then return false end
    AIO.Handle(player, "Transmog", "TransmogFrame")
    return false
end

local function SyncLegacyTransmogItemIds(player)
    local slots = BuildTransmogStateV2(player)
    if not slots then return end
    for _, slot in ipairs(VISIBLE_SLOTS) do
        local state = slots[slot]
        local item = nil
        if state.mode == "hidden" then
            item = 0
        elseif state.mode == "appearance" then
            item = state.itemId
        end
        AIO.Handle(player, "Transmog", "SetTransmogItemIdClient", slot, item, state.realItemId)
    end
end

function TransmogHandlers.SetTransmogItemIds(player)
    if not IsAppearanceBuddyPlayer(player) then return end
    if not ConsumeExpensiveRequestBudget(player, 1) then return end
    SyncLegacyTransmogItemIds(player)
end

local function SendDeleteUnlockedAppearanceResult(player, slot, removedItemIds, success, message)
    AIO.Handle(
        player,
        "Transmog",
        "DeleteUnlockedAppearanceResult",
        tonumber(slot) or 0,
        type(removedItemIds) == "table" and removedItemIds or {},
        success == true,
        tostring(message or "")
    )
end

local function RefreshOnlineAccountAppearances(accountGUID, sourcePlayer)
    accountGUID = tonumber(accountGUID)
    if not accountGUID then return end

    local sourceGUIDLow = nil
    if sourcePlayer and sourcePlayer.GetGUIDLow then
        local sourceGUIDLowOK, value = pcall(sourcePlayer.GetGUIDLow, sourcePlayer)
        if sourceGUIDLowOK then
            sourceGUIDLow = tonumber(value)
        end
    end
    local refreshedSource = false
    local onlineGUIDs = ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID]
    if onlineGUIDs and type(GetPlayerByGUID) == "function" then
        for playerGUIDLow, playerGUID in pairs(onlineGUIDs) do
            local playerOK, onlinePlayer = pcall(GetPlayerByGUID, playerGUID)
            local accountOK, onlineAccountGUID = false, nil
            if playerOK and IsAppearanceBuddyPlayer(onlinePlayer) and onlinePlayer.GetAccountId then
                accountOK, onlineAccountGUID = pcall(onlinePlayer.GetAccountId, onlinePlayer)
            end
            if not accountOK or tonumber(onlineAccountGUID) ~= accountGUID then
                -- Logout callbacks can race a cross-character invalidation.
                -- Prune the stale entry instead of falling back to a world scan.
                onlineGUIDs[playerGUIDLow] = nil
            else
                -- Force authoritative visible fields even for already-hydrated
                -- players. BuildTransmogStateV2 intentionally skips those
                -- writes and is therefore insufficient after revocation.
                local callOK, loadOK = pcall(Transmog_Load, onlinePlayer)
                if callOK and loadOK == true and playerGUIDLow == sourceGUIDLow then
                    refreshedSource = true
                end
            end
        end
        if next(onlineGUIDs) == nil then
            ONLINE_PLAYER_GUIDS_BY_ACCOUNT[accountGUID] = nil
        end
    end

    if not refreshedSource and IsAppearanceBuddyPlayer(sourcePlayer) then
        pcall(Transmog_Load, sourcePlayer)
    end
end

local function CompensateFailedAppearanceDeletion(accountGUID, displayId, records)
    local values = {}
    for _, record in ipairs(records or {}) do
        values[#values + 1] = string.format(
            "(%u, %u, %u, %u, '%s')",
            accountGUID,
            tonumber(record.itemId) or 0,
            displayId,
            tonumber(record.inventoryType) or 0,
            EscapeString(record.itemName or "")
        )
    end

    local ok, restored = pcall(function()
        if #values > 0 then
            AuthDBQuery(
                "INSERT IGNORE INTO account_transmog (account_id, unlocked_item_id, display_id, inventory_type, item_name) VALUES "
                .. table.concat(values, ", ")
            )
        end
        AuthDBQuery(string.format(
            "DELETE FROM account_transmog_removed_appearance WHERE account_id = %u AND display_id = %u",
            accountGUID,
            displayId
        ))
        local tombstoneCount = AuthDBQuery(string.format(
            "SELECT COUNT(*) FROM account_transmog_removed_appearance WHERE account_id = %u AND display_id = %u",
            accountGUID,
            displayId
        ))
        local restoredCount = AuthDBQuery(string.format(
            "SELECT COUNT(*) FROM account_transmog WHERE account_id = %u AND display_id = %u",
            accountGUID,
            displayId
        ))
        return tombstoneCount ~= nil
            and (tonumber(tombstoneCount:GetUInt32(0)) or -1) == 0
            and restoredCount ~= nil
            and (tonumber(restoredCount:GetUInt32(0)) or 0) >= #values
    end)
    return ok and restored == true
end

-- Permanently remove one visual from an account collection.  The exact item
-- must be unlocked in the requested slot, but every account item using the
-- same display is removed so aliases cannot keep the appearance alive.
function TransmogHandlers.DeleteUnlockedAppearance(player, slot, itemId)
    if not IsAppearanceBuddyPlayer(player) or not player.GetAccountId then
        return
    end
    if not ConsumeExpensiveRequestBudget(player, 2) then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "Appearance requests are being submitted too quickly.")
        return
    end
    if not TRANSMOG_PERSISTENCE_SCHEMA_READY then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "Appearance removal is disabled until the server database migration is applied.")
        return
    end

    local accountGUID = tonumber(player:GetAccountId())
    slot = NormalizeVisibleSlot(slot)
    itemId = tonumber(itemId)
    if not accountGUID or accountGUID ~= accountGUID or accountGUID <= 0 or accountGUID >= math.huge
        or not slot
        or not itemId or itemId ~= itemId or itemId <= 0 or itemId >= math.huge then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "That appearance could not be removed.")
        return
    end

    local displayId = GetExactUnlockedAppearanceBucket(accountGUID, slot, itemId)
    if not displayId then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "That appearance is no longer unlocked.")
        return
    end

    local removedItemIds = {}
    local removedRecords = {}
    local removedItemIdSet = {}
    -- Snapshot from the database immediately before mutation. A cache can be
    -- stale when another world process unlocks an alias for the same display.
    local snapshotOK, snapshot = pcall(AuthDBQuery, string.format(
        "SELECT unlocked_item_id, COALESCE(inventory_type, 0), COALESCE(item_name, '') FROM account_transmog WHERE account_id = %u AND display_id = %u ORDER BY unlocked_item_id",
        accountGUID,
        displayId
    ))
    if not snapshotOK or not snapshot then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "The appearance collection could not be verified. Please try again.")
        return
    end
    repeat
        local recordItemId = tonumber(snapshot:GetUInt32(0)) or 0
        if recordItemId > 0 and not removedItemIdSet[recordItemId] then
            removedItemIdSet[recordItemId] = true
            removedItemIds[#removedItemIds + 1] = recordItemId
            removedRecords[#removedRecords + 1] = {
                itemId = recordItemId,
                displayId = displayId,
                inventoryType = tonumber(snapshot:GetUInt32(1)) or 0,
                itemName = snapshot:GetString(2) or "",
            }
        end
    until not snapshot:NextRow()
    table.sort(removedItemIds)

    if #removedItemIds == 0 then
        SendDeleteUnlockedAppearanceResult(player, slot, {}, false, "That appearance is no longer unlocked.")
        return
    end

    local function failDeletionWithCompensation(stage)
        local compensated = CompensateFailedAppearanceDeletion(accountGUID, displayId, removedRecords)
        if not compensated then
            print(string.format(
                "[AppearanceBuddy Transmog] CRITICAL: %s deletion compensation failed for account %s display %s",
                tostring(stage),
                tostring(accountGUID),
                tostring(displayId)
            ))
        end
        InvalidateAccountCaches(accountGUID, true)
        SendDeleteUnlockedAppearanceResult(
            player,
            slot,
            {},
            false,
            compensated and "The appearance could not be removed. Please try again."
                or "Appearance removal could not be recovered. Contact an administrator."
        )
    end

    local itemIdList = table.concat(removedItemIds, ",")
    local tombstoneOK = pcall(function()
        AuthDBQuery(string.format(
            "INSERT IGNORE INTO account_transmog_removed_appearance (account_id, display_id) VALUES (%u, %u)",
            accountGUID,
            displayId
        ))
    end)
    local tombstoneVerified, persistedTombstone = false, nil
    if tombstoneOK then
        tombstoneVerified, persistedTombstone = pcall(AuthDBQuery, string.format(
            "SELECT 1 FROM account_transmog_removed_appearance WHERE account_id = %u AND display_id = %u LIMIT 1",
            accountGUID,
            displayId
        ))
    end
    if not tombstoneVerified or not persistedTombstone then
        failDeletionWithCompensation("tombstone")
        return
    end

    local deleteOK = pcall(function()
        AuthDBQuery(string.format(
            "DELETE FROM account_transmog WHERE account_id = %u AND display_id = %u",
            accountGUID,
            displayId
        ))
    end)
    if not deleteOK then
        failDeletionWithCompensation("row-delete")
        return
    end

    local remainingVerified, remainingCount = pcall(AuthDBQuery, string.format(
        "SELECT COUNT(*) FROM account_transmog WHERE account_id = %u AND display_id = %u",
        accountGUID,
        displayId
    ))
    if not remainingVerified
        or not remainingCount
        or (tonumber(remainingCount:GetUInt32(0)) or -1) ~= 0 then
        failDeletionWithCompensation("partial")
        return
    end

    -- Keep the equipped items themselves and their real_item records, but stop
    -- every character on this account from rendering the revoked appearance.
    local characterUpdateOK = pcall(CharDBQuery, string.format(
        "UPDATE character_transmog INNER JOIN characters ON characters.guid = character_transmog.player_guid "
        .. "SET character_transmog.item = NULL WHERE characters.account = %u "
        .. "AND character_transmog.item IN (%s)",
        accountGUID,
        itemIdList
    ))
    local characterCleanupVerified, remainingCharacterRows = false, nil
    if characterUpdateOK then
        characterCleanupVerified, remainingCharacterRows = pcall(CharDBQuery, string.format(
            "SELECT COUNT(*) FROM character_transmog INNER JOIN characters ON characters.guid = character_transmog.player_guid "
            .. "WHERE characters.account = %u AND character_transmog.item IN (%s)",
            accountGUID,
            itemIdList
        ))
    end
    if not characterCleanupVerified
        or not remainingCharacterRows
        or (tonumber(remainingCharacterRows:GetUInt32(0)) or -1) ~= 0 then
        -- Auth rows plus the tombstone are the durable revocation commit point.
        -- Character rows are a derived cache and self-heal on the next load;
        -- do not resurrect the collection after the cross-DB commit succeeded.
        print(string.format(
            "[AppearanceBuddy Transmog] WARNING: deferred character cleanup for account %s display %s",
            tostring(accountGUID),
            tostring(displayId)
        ))
    end

    InvalidateAccountCaches(accountGUID, true)
    RefreshOnlineAccountAppearances(accountGUID, player)
    AIO.Handle(player, "Transmog", "ItemSetCatalogInvalidated")
    SendDeleteUnlockedAppearanceResult(player, slot, removedItemIds, true, "Appearance removed permanently.")
end

local function BuildPagedItemIds(records, page, pageSize)
    local pageOffset = (page > 1) and (pageSize * (page - 1)) or 0
    local result = {}
    local total = #records

    if pageOffset >= total then
        return result, false, total
    end

    local lastIndex = math.min(total, pageOffset + pageSize)
    for index = pageOffset + 1, lastIndex do
        result[#result + 1] = tonumber(records[index].itemId) or 0
    end

    return result, total > lastIndex, total
end

local function ClampPageToRecordCount(page, records, pageSize)
    local total = #(records or {})
    local maxPage = math.max(1, math.ceil(total / math.max(1, pageSize)))
    return math.min(math.max(1, tonumber(page) or 1), maxPage)
end

local function SearchAppearanceRecords(records, search)
    local normalizedSearch = string.lower(tostring(search or ""):sub(1, 64))
    local matches = {}

    if normalizedSearch == "" then
        return matches
    end

    for _, record in ipairs(records) do
        if (record.lowerName and record.lowerName:find(normalizedSearch, 1, true))
            or (record.displayId and record.displayId > 0 and tostring(record.displayId):find(normalizedSearch, 1, true)) then
            matches[#matches + 1] = record
        end
    end

    return matches
end

local function EnsureAppearanceRecordMetadata(appearanceCache, slot, records)
    appearanceCache.itemMetadataLoadedBySlot = appearanceCache.itemMetadataLoadedBySlot or {}
    if appearanceCache.itemMetadataLoadedBySlot[slot] then
        return true
    end

    local itemIds = {}
    for _, record in ipairs(records or {}) do
        itemIds[#itemIds + 1] = record.itemId
    end
    if not PreloadItemTemplateInfos(itemIds) then
        -- Do not publish partial class or weapon filters after an ambiguous
        -- World DB failure. The next request must retry from a clean view.
        return false
    end

    appearanceCache.itemMetadataLoadedBySlot[slot] = true
    return true
end

FilterAppearanceRecords = function(player, appearanceCache, slot, weaponFilter)
    local normalizedFilter = NormalizeWeaponFilter(slot, weaponFilter)
    if type(appearanceCache) ~= "table" or appearanceCache.loadSucceeded ~= true then
        return {}, normalizedFilter, false
    end

    local context = AppearanceEligibility.GetContext(player)
    local eligibilityKey = AppearanceEligibility.GetCacheKey(context)
    if not eligibilityKey then
        return {}, normalizedFilter, false
    end

    local allRecords = appearanceCache.bySlot[slot] or {}
    if not EnsureAppearanceRecordMetadata(appearanceCache, slot, allRecords) then
        return {}, normalizedFilter, false
    end

    local records = allRecords
    if normalizedFilter ~= "all" then
        local definition = WEAPON_FILTER_DEFINITIONS[normalizedFilter]
        if not definition then
            normalizedFilter = "all"
        else
            appearanceCache.bySlotFilter = appearanceCache.bySlotFilter or {}
            local filterCache = appearanceCache.bySlotFilter[slot]
            if not filterCache then
                filterCache = {}
                appearanceCache.bySlotFilter[slot] = filterCache
            end
            local cachedMatches = filterCache[normalizedFilter]
            if cachedMatches then
                records = cachedMatches
            else
                local matches = {}
                for _, record in ipairs(allRecords) do
                    local itemTemplate = ITEM_TEMPLATE_CACHE[tonumber(record.itemId) or 0]
                    local subclassMatches = definition.itemSubclasses
                        and definition.itemSubclasses[itemTemplate and itemTemplate.itemSubclass]
                        or itemTemplate and itemTemplate.itemSubclass == definition.itemSubclass
                    if type(itemTemplate) == "table"
                        and itemTemplate.itemClass == definition.itemClass
                        and subclassMatches
                        and definition.inventoryTypes[itemTemplate.inventoryType] then
                        matches[#matches + 1] = record
                    end
                end
                filterCache[normalizedFilter] = matches
                records = matches
            end
        end
    end

    -- RequiredLevel makes eligibility change at every level, rather than only
    -- at the historical armor/weapon breakpoints.  Retain only a small rolling
    -- window of policy views so an account with many characters cannot retain
    -- a full copy of the catalog for every possible level.
    local MAX_APPEARANCE_ELIGIBILITY_POLICY_CACHES = 8
    appearanceCache.eligibleRecordsByPolicy = appearanceCache.eligibleRecordsByPolicy or {}
    appearanceCache.eligibleRecordPolicyOrder = appearanceCache.eligibleRecordPolicyOrder or {}
    local policyCache = appearanceCache.eligibleRecordsByPolicy[eligibilityKey]
    if not policyCache then
        while #appearanceCache.eligibleRecordPolicyOrder >= MAX_APPEARANCE_ELIGIBILITY_POLICY_CACHES do
            local expiredKey = table.remove(appearanceCache.eligibleRecordPolicyOrder, 1)
            appearanceCache.eligibleRecordsByPolicy[expiredKey] = nil
        end
        policyCache = {}
        appearanceCache.eligibleRecordsByPolicy[eligibilityKey] = policyCache
        table.insert(appearanceCache.eligibleRecordPolicyOrder, eligibilityKey)
    end
    local policySlotCache = policyCache[slot]
    if not policySlotCache then
        policySlotCache = {}
        policyCache[slot] = policySlotCache
    end
    local cachedEligible = policySlotCache[normalizedFilter]
    if cachedEligible then
        return cachedEligible, normalizedFilter, true
    end

    local eligible = {}
    for _, record in ipairs(records) do
        local itemTemplate = ITEM_TEMPLATE_CACHE[tonumber(record.itemId) or 0]
        if type(itemTemplate) == "table"
            and AppearanceEligibility.Allows(player, slot, itemTemplate, context) then
            eligible[#eligible + 1] = record
        end
    end
    policySlotCache[normalizedFilter] = eligible
    return eligible, normalizedFilter, true
end

local function FindAppearanceRecordIndex(records, itemId)
    itemId = tonumber(itemId) or 0
    for index, record in ipairs(records) do
        if (tonumber(record.itemId) or 0) == itemId then
            return index
        end
    end
    return nil
end

local function NormalizeAppearancePageRetryAfter(retryAfter)
    retryAfter = tonumber(retryAfter)
    if not retryAfter or retryAfter ~= retryAfter
        or retryAfter <= -math.huge or retryAfter >= math.huge then
        return 0
    end
    return math.max(0, math.min(60, retryAfter))
end

local function SendCurrentSlotPageResult(
    player,
    slot,
    page,
    requestToken,
    weaponFilter,
    succeeded,
    errorMessage,
    errorCode,
    retryAfter
)
    requestToken = NormalizeAppearancePageRequestToken(requestToken)
    if not requestToken then
        return false
    end
    AIO.Handle(
        player,
        "Transmog",
        "SetCurrentSlotItemPageClient",
        tonumber(slot) or 0,
        math.max(1, math.floor(tonumber(page) or 1)),
        requestToken,
        tostring(weaponFilter or "all"),
        succeeded == true,
        tostring(errorMessage or ""),
        tostring(errorCode or ""),
        NormalizeAppearancePageRetryAfter(retryAfter)
    )
    return true
end

local function SendAppearanceTabResult(
    player,
    itemIds,
    page,
    hasMorePages,
    slot,
    requestToken,
    totalCount,
    weaponFilter,
    succeeded,
    errorMessage,
    errorCode,
    retryAfter
)
    requestToken = NormalizeAppearancePageRequestToken(requestToken)
    if not requestToken then
        return false
    end
    AIO.Handle(
        player,
        "Transmog",
        "InitTab",
        type(itemIds) == "table" and itemIds or {},
        math.max(1, math.floor(tonumber(page) or 1)),
        hasMorePages == true,
        tonumber(slot) or 0,
        requestToken,
        math.max(0, math.floor(tonumber(totalCount) or 0)),
        tostring(weaponFilter or "all"),
        succeeded == true,
        tostring(errorMessage or ""),
        tostring(errorCode or ""),
        NormalizeAppearancePageRetryAfter(retryAfter)
    )
    return true
end

function TransmogHandlers.SetCurrentSlotItemPage(player, slot, itemId, pageSize, requestToken, weaponFilter)
    if not IsAppearanceBuddyPlayer(player) then return end
    if requestToken == nil then
        requestToken = pageSize
        pageSize = SLOTS
    end
    requestToken = NormalizeAppearancePageRequestToken(requestToken)
    if not requestToken then return end
    slot = NormalizeVisibleSlot(slot)
    itemId = tonumber(itemId)
    if not itemId or itemId ~= itemId or itemId <= 0 or itemId >= math.huge
        or itemId ~= math.floor(itemId) or itemId > 4294967295 then
        itemId = 0
    end
    pageSize = NormalizePageSize(pageSize)
    local normalizedFilter = NormalizeWeaponFilter(slot, weaponFilter)
    local budgetAllowed, retryAfter = ConsumeExpensiveRequestBudget(player, 2)
    if not budgetAllowed then
        SendCurrentSlotPageResult(
            player,
            slot,
            1,
            requestToken,
            normalizedFilter,
            false,
            "Appearance data is being requested too quickly.",
            APPEARANCE_PAGE_ERROR_RATE_LIMITED,
            retryAfter
        )
        return
    end
    local accountGUID = player:GetAccountId()

    if not slot or itemId <= 0 then
        SendCurrentSlotPageResult(player, slot, 1, requestToken, normalizedFilter, false, "Invalid appearance page request.")
        return
    end

    local inventoryTypes = SLOT_INVENTORY_TYPES[slot]
    local appearanceCache = inventoryTypes and GetAccountAppearanceCache(accountGUID) or nil
    if appearanceCache and appearanceCache.loadSucceeded ~= true then
        SendCurrentSlotPageResult(player, slot, 1, requestToken, normalizedFilter, false, "Appearance data could not be loaded. Please try again.")
        return
    end
    if not inventoryTypes then
        SendCurrentSlotPageResult(player, slot, 1, requestToken, normalizedFilter, false, "That appearance is not available in this slot.")
        return
    end

    local filteredRecords, filterLoadSucceeded
    filteredRecords, normalizedFilter, filterLoadSucceeded = FilterAppearanceRecords(player, appearanceCache, slot, normalizedFilter)
    if not filterLoadSucceeded then
        SendCurrentSlotPageResult(player, slot, 1, requestToken, normalizedFilter, false, "Appearance metadata could not be loaded. Please try again.")
        return
    end
    local itemIndex = FindAppearanceRecordIndex(filteredRecords, itemId)
    if not itemIndex then
        SendCurrentSlotPageResult(player, slot, 1, requestToken, normalizedFilter, false, "That appearance is not available in this slot.")
        return
    end
    local page = math.floor((itemIndex - 1) / pageSize) + 1
    SendCurrentSlotPageResult(player, slot, page, requestToken, normalizedFilter, true, "")
end

function TransmogHandlers.SetCurrentSlotItemIds(player, slot, page, pageSize, requestToken, weaponFilter)
    if not IsAppearanceBuddyPlayer(player) then return end
    slot = NormalizeVisibleSlot(slot)
    page = NormalizePage(page)
    if requestToken == nil then
        requestToken = pageSize
        pageSize = SLOTS
    end
    requestToken = NormalizeAppearancePageRequestToken(requestToken)
    if not requestToken then return end
    pageSize = NormalizePageSize(pageSize)
    local normalizedFilter = NormalizeWeaponFilter(slot, weaponFilter)
    local budgetAllowed, retryAfter = ConsumeExpensiveRequestBudget(player, 2)
    if not budgetAllowed then
        SendAppearanceTabResult(
            player,
            {},
            1,
            false,
            slot,
            requestToken,
            0,
            normalizedFilter,
            false,
            "Appearance data is being requested too quickly.",
            APPEARANCE_PAGE_ERROR_RATE_LIMITED,
            retryAfter
        )
        return
    end
    local accountGUID = player:GetAccountId()

    local inventoryTypes = SLOT_INVENTORY_TYPES[slot]

    if not inventoryTypes then
        SendAppearanceTabResult(player, {}, 1, false, 0, requestToken, 0, "all", false, "Invalid appearance slot.")
        return
    end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local filteredRecords, filterLoadSucceeded
    filteredRecords, normalizedFilter, filterLoadSucceeded = FilterAppearanceRecords(player, appearanceCache, slot, normalizedFilter)
    if not filterLoadSucceeded then
        SendAppearanceTabResult(player, {}, 1, false, slot, requestToken, 0, normalizedFilter, false, "Appearance data could not be loaded. Please try again.")
        return
    end
    page = ClampPageToRecordCount(page, filteredRecords, pageSize)
    local currentSlotItemIds, hasMorePages, totalCount = BuildPagedItemIds(filteredRecords, page, pageSize)

    SendAppearanceTabResult(player, currentSlotItemIds, page, hasMorePages, slot, requestToken, totalCount, normalizedFilter, true, "")
end

function TransmogHandlers.SetSearchCurrentSlotItemIds(player, slot, page, search, pageSize, requestToken, weaponFilter)
    if not IsAppearanceBuddyPlayer(player) then return end
    slot = NormalizeVisibleSlot(slot)
    page = NormalizePage(page)
    if requestToken == nil then
        requestToken = pageSize
        pageSize = SLOTS
    end
    requestToken = NormalizeAppearancePageRequestToken(requestToken)
    if not requestToken then return end
    pageSize = NormalizePageSize(pageSize)

    search = tostring(search or ""):sub(1, 64)
    if search == "" then
        TransmogHandlers.SetCurrentSlotItemIds(player, slot, page, pageSize, requestToken, weaponFilter)
        return
    end
    local normalizedFilter = NormalizeWeaponFilter(slot, weaponFilter)
    local budgetAllowed, retryAfter = ConsumeExpensiveRequestBudget(player, 2)
    if not budgetAllowed then
        SendAppearanceTabResult(
            player,
            {},
            1,
            false,
            slot,
            requestToken,
            0,
            normalizedFilter,
            false,
            "Appearance data is being requested too quickly.",
            APPEARANCE_PAGE_ERROR_RATE_LIMITED,
            retryAfter
        )
        return
    end

    local inventoryTypes = SLOT_INVENTORY_TYPES[slot]

    if not inventoryTypes then
        SendAppearanceTabResult(player, {}, 1, false, 0, requestToken, 0, "all", false, "Invalid appearance slot.")
        return
    end
    local accountGUID = player:GetAccountId()

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local filteredRecords, filterLoadSucceeded
    filteredRecords, normalizedFilter, filterLoadSucceeded = FilterAppearanceRecords(player, appearanceCache, slot, normalizedFilter)
    if not filterLoadSucceeded then
        SendAppearanceTabResult(player, {}, 1, false, slot, requestToken, 0, normalizedFilter, false, "Appearance data could not be loaded. Please try again.")
        return
    end
    local matches = SearchAppearanceRecords(filteredRecords, search)
    page = ClampPageToRecordCount(page, matches, pageSize)
    local currentSlotItemIds, hasMorePages, totalCount = BuildPagedItemIds(matches, page, pageSize)

    SendAppearanceTabResult(player, currentSlotItemIds, page, hasMorePages, slot, requestToken, totalCount, normalizedFilter, true, "")
end

local function SendTransmogCommandMessage(player, message)
    if player and type(player.SendBroadcastMessage) == "function" then
        pcall(player.SendBroadcastMessage, player, "|cff6ff98<Appearance Buddy>|r: "..message)
    end
end

local function PushFreeTransmogModeState(player, enabled)
    if not player or not AIO or type(AIO.Handle) ~= "function" then
        return
    end

    pcall(
        AIO.Handle,
        player,
        "Transmog",
        "FreeTransmogModeChanged",
        enabled == true,
        BuildTransmogSlotCosts(player),
        GetPlayerCoinage(player)
    )
end

local function Transmog_OnCommand(event, player, command)
    if not player or type(command) ~= "string" then
        return true
    end

    local commandName, arguments = command:match("^%s*%.?(%S+)%s*(.-)%s*$")
    if not commandName or commandName:lower() ~= "transmog" then
        return true
    end

    local subcommand, mode = (arguments or ""):match("^(%S+)%s*(.-)%s*$")
    if not subcommand or subcommand:lower() ~= "free" then
        return true
    end

    if not IsAppearanceBuddyGameMaster(player) then
        SendTransmogCommandMessage(player, "You do not have permission to change transmog pricing.")
        return false
    end

    mode = tostring(mode or ""):lower()
    if mode == "" or mode == "on" then
        if not SetFreeTransmogEnabled(player, true) then
            SendTransmogCommandMessage(player, "Free transmog could not be enabled for this character.")
            return false
        end
        PushFreeTransmogModeState(player, true)
        SendTransmogCommandMessage(player, "Free transmog enabled for this GM session.")
    elseif mode == "off" then
        SetFreeTransmogEnabled(player, false)
        PushFreeTransmogModeState(player, false)
        SendTransmogCommandMessage(player, "Free transmog disabled; normal prices apply.")
    elseif mode == "status" then
        local enabled = IsFreeTransmogEnabled(player)
        PushFreeTransmogModeState(player, enabled)
        SendTransmogCommandMessage(player, enabled and "Free transmog is enabled for this GM session."
            or "Free transmog is disabled; normal prices apply.")
    else
        SendTransmogCommandMessage(player, "Usage: .transmog free [on|off|status]")
    end

    return false
end

RegisterPlayerEvent(1, Transmog_OnCharacterCreate)
RegisterPlayerEvent(2, Transmog_OnCharacterDelete)
RegisterPlayerEvent(3, Transmog_OnLogin)
RegisterPlayerEvent(4, Transmog_OnLogout)
RegisterPlayerEvent(5, Transmog_OnWeaponEnchantVisualUpdate)
RegisterPlayerEvent(51, Transmog_OnLootItem)
RegisterPlayerEvent(52, Transmog_OnLootItem)
RegisterPlayerEvent(53, Transmog_OnLootItem)
RegisterPlayerEvent(56, Transmog_OnLootItem)
RegisterPlayerEvent(29, Transmog_OnEquipItem)
RegisterPlayerEvent(42, Transmog_OnCommand)
RegisterPlayerEvent(64, Transmog_OnWeaponEnchantVisualUpdate)
RegisterPlayerEvent(67, Transmog_OnWeaponEnchantVisualUpdate)

-- `.reload ale` does not fire login for players already in the world. Rehydrate
-- all appearance state immediately so a reload cannot leave an ineligible
-- stored look or explicit-zero weapon glow visible until the next equip, aura
-- update, or relog.
ReapplyNoEnchantVisualsForOnlinePlayers()
