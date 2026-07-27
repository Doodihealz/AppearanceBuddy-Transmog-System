local addon, ns = ...

local mainFrame = ns.mainFrame
if not mainFrame or not mainFrame.tabs or not mainFrame.tabs.transmog then
    return
end

local AIO = _G.AIO
if not AIO and type(require) == "function" then
    local ok, lib = pcall(require, "AIO")
    if ok then
        AIO = lib
    end
end

local GetSettings = ns.GetSettings
local transmogTab = mainFrame.tabs.transmog
local transmogTabName = transmogTab:GetName() or (addon.."TransmogTab")
local TransmogPaging = assert(ns.TransmogPaging, "AppearanceBuddy transmog pager was not loaded")

local function clearEditBoxFocus(editBox)
    if editBox and editBox.ClearFocus then
        editBox:ClearFocus()
    end
end

local function clearTransmogSearchFocus()
    clearEditBoxFocus(transmogTab.searchBox)
    clearEditBoxFocus(transmogTab.setsFrame and transmogTab.setsFrame.searchBox)
end

local function setModelIconButtonEnabled(button, enabled)
    if not button then
        return
    end

    if enabled then
        button:Enable()
    else
        button:Disable()
    end

    -- The themed button background does not dim custom icon textures.  Keep
    -- disabled mannequin controls visibly disabled instead of looking clickable.
    if button.icon then
        if button.icon.SetDesaturated then
            button.icon:SetDesaturated(not enabled)
        end
        button.icon:SetAlpha(enabled and 1 or 0.35)
    end
end

local SLOT_DATA = {
    { name = "Head", slotId = 283, previewSubclass = nil },
    { name = "Shoulder", slotId = 287, previewSubclass = nil },
    { name = "Back", slotId = 311, previewSubclass = "Cloth" },
    { name = "Chest", slotId = 291, previewSubclass = nil },
    { name = "Shirt", slotId = 289, previewSubclass = "Miscellaneous" },
    { name = "Tabard", slotId = 319, previewSubclass = "Miscellaneous" },
    { name = "Wrist", slotId = 299, previewSubclass = nil },
    { name = "Hands", slotId = 301, previewSubclass = nil },
    { name = "Waist", slotId = 293, previewSubclass = nil },
    { name = "Legs", slotId = 295, previewSubclass = nil },
    { name = "Feet", slotId = 297, previewSubclass = nil },
    { name = "Main Hand", slotId = 313, previewSubclass = "1H Sword" },
    { name = "Off-hand", slotId = 315, previewSubclass = "Shield" },
    { name = "Ranged", slotId = 317, previewSubclass = "Bow" },
}

local FALLBACK_SLOT_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

local function getSlotPlaceholderTexture(slotName)
    if type(ns.GetSlotPlaceholderTexture) == "function" then
        return ns.GetSlotPlaceholderTexture(slotName) or FALLBACK_SLOT_TEXTURE
    end
    return FALLBACK_SLOT_TEXTURE
end

local DEFAULT_ARMOR_SUBCLASS = {
    ["MAGE"] = "Cloth",
    ["PRIEST"] = "Cloth",
    ["WARLOCK"] = "Cloth",
    ["DRUID"] = "Leather",
    ["ROGUE"] = "Leather",
    ["HUNTER"] = "Mail",
    ["SHAMAN"] = "Mail",
    ["PALADIN"] = "Plate",
    ["WARRIOR"] = "Plate",
    ["DEATHKNIGHT"] = "Plate",
}

local SLOT_ID_BY_NAME = {}
local SLOT_NAME_BY_ID = {}
local SLOT_PREVIEW_SUBCLASS = {}

for _, info in ipairs(SLOT_DATA) do
    SLOT_ID_BY_NAME[info.name] = info.slotId
    SLOT_NAME_BY_ID[info.slotId] = info.name
    SLOT_PREVIEW_SUBCLASS[info.name] = info.previewSubclass
end

local _, playerRaceFileName = UnitRace("player")
local playerSex = UnitSex("player")
local _, playerClassFileName = UnitClass("player")

local LIST_TOP_Y = -86
local LIST_BOTTOM_Y = 20
local SLOT_ACTION_ROW_Y = -47
local SETS_FRAME_BOTTOM_Y = 10
local SETS_SCROLL_STEP = 72
local SETS_LIST_SCROLL_WIDTH = 184
local SETS_LIST_WIDTH = 160
local SETS_PREVIEW_LEFT_X = 198
local DEFAULT_TRANSMOG_PAGE_SIZE = 20
local APPEARANCE_PAGE_POLICY = {
    scrollDebounceSeconds = 0.12,
    minimumIntervalSeconds = 0.55,
    maximumRateLimitRetries = 4,
    retryMarginSeconds = 0.10,
    rateLimitErrorCode = "RATE_LIMITED",
}
-- Must match PreviewList's visual card gaps so each requested page fills the
-- exact visible grid, including the final row.
local PREVIEW_GRID_GAP_X = 8
local PREVIEW_GRID_GAP_Y = 10

local PREVIEW_CARD_LAYOUT = {
    armor = {
        width = 80,
        height = 102,
    },
    weapon = {
        width = 80,
        height = 102,
    },
}

local WEAPON_SLOT = {
    ["Main Hand"] = true,
    ["Off-hand"] = true,
    ["Ranged"] = true,
}

-- DressMe keeps generic one-hand and hand-specific records in separate data
-- buckets. AppearanceBuddy groups those implementation details into the
-- weapon families players expect while preserving an unfiltered default.
transmogTab.weaponFilterOptions = {
    ["Main Hand"] = {
        { key = "all", label = "All Weapons" },
        { key = "dagger", label = "Daggers" },
        { key = "sword_1h", label = "One-Hand Swords" },
        { key = "axe_1h", label = "One-Hand Axes" },
        { key = "mace_1h", label = "One-Hand Maces" },
        { key = "fist", label = "Fist Weapons" },
        { key = "sword_2h", label = "Two-Hand Swords" },
        { key = "axe_2h", label = "Two-Hand Axes" },
        { key = "mace_2h", label = "Two-Hand Maces" },
        { key = "polearm", label = "Polearms" },
        { key = "staff", label = "Staves" },
    },
    ["Off-hand"] = {
        { key = "all", label = "All Off-hand" },
        { key = "dagger", label = "Daggers" },
        { key = "sword_1h", label = "One-Hand Swords" },
        { key = "axe_1h", label = "One-Hand Axes" },
        { key = "mace_1h", label = "One-Hand Maces" },
        { key = "fist", label = "Fist Weapons" },
        { key = "sword_2h", label = "Two-Hand Swords" },
        { key = "axe_2h", label = "Two-Hand Axes" },
        { key = "mace_2h", label = "Two-Hand Maces" },
        { key = "shield", label = "Shields" },
    },
    ["Ranged"] = {
        { key = "all", label = "All Ranged" },
        { key = "bow", label = "Bows" },
        { key = "crossbow", label = "Crossbows" },
        { key = "gun", label = "Guns" },
        { key = "wand", label = "Wands" },
        { key = "thrown", label = "Thrown" },
        { key = "relic", label = "Relics" },
    },
}
local LARGE_WEAPON_MINI_PREVIEW_X_SCALE = 0.5

-- Cosmetic weapon enchants are intentionally separate from transmog item
-- choices.  The server validates this same small visual-only catalog and only
-- writes the player-visible enchant field, never the equipped item's stats.
local WEAPON_EQUIPMENT_SLOT_BY_NAME = {
    ["Main Hand"] = 15,
    ["Off-hand"] = 16,
    ["Ranged"] = 17,
}

local WEAPON_NAME_BY_EQUIPMENT_SLOT = {
    [15] = "Main Hand",
    [16] = "Off-hand",
    [17] = "Ranged",
}

-- Keep this list in lockstep with Build/bin/RelWithDebInfo/lua_scripts/transmog.lua.
local WEAPON_ENCHANT_OPTIONS = {
    { id = 0, name = "No Enchantment" },
    { id = 803, name = "Fiery Weapon", spellId = 13897 },
    { id = 1894, name = "Icy Chill", spellId = 20005 },
    { id = 1898, name = "Lifestealing", spellId = 20004 },
    { id = 1899, name = "Unholy Weapon", spellId = 20006 },
    { id = 1900, name = "Crusader", spellId = 20007 },
    { id = 2671, name = "Sunfire", spellId = 27979 },
    { id = 2672, name = "Soulfrost", spellId = 27980 },
    { id = 2673, name = "Mongoose", spellId = 28093 },
    { id = 2674, name = "Spellsurge", spellId = 27997 },
    { id = 2675, name = "Battlemaster", spellId = 28005 },
    { id = 3225, name = "Executioner", spellId = 42976 },
    { id = 3239, name = "Icebreaker", spellId = 44525 },
    { id = 3241, name = "Lifeward", spellId = 44578 },
    { id = 3273, name = "Deathfrost", spellId = 46579 },
    { id = 3350, name = "Earthliving", spellId = 52008 },
    { id = 3368, name = "Rune of the Fallen Crusader", spellId = 53362 },
    { id = 3369, name = "Rune of Cinderglacier", spellId = 53386 },
    { id = 3370, name = "Rune of Razorice", spellId = 50401 },
    { id = 3789, name = "Berserking", spellId = 59620 },
    { id = 3790, name = "Black Magic", spellId = 59630 },
    { id = 3869, name = "Blade Ward", spellId = 64440 },
    { id = 3870, name = "Blood Draining", spellId = 64571 },
}

local WEAPON_ENCHANT_OPTION_BY_ID = {}
for _, option in ipairs(WEAPON_ENCHANT_OPTIONS) do
    WEAPON_ENCHANT_OPTION_BY_ID[option.id] = option
end

local SET_LIST_ICON_SLOT_PRIORITY = {1, 2, 4, 8, 9, 10, 11, 7, 3, 5, 6, 12, 13, 14}
local SET_PREVIEW_RETRY_SLOT_ORDER = {
    "Chest", "Legs", "Feet", "Waist", "Hands", "Wrist",
    "Back", "Shoulder", "Head", "Shirt", "Tabard",
    "Main Hand", "Off-hand", "Ranged",
}

local SET_SOURCE_SAVED = "saved"
local SET_SOURCE_CATALOG = "catalog"
ns.MAX_SAVED_TRANSMOG_SETS = 100
local ITEM_SET_DETAIL_REQUEST_TIMEOUT = 4
local ITEM_SET_DETAIL_MAX_RETRIES = 1

local function trim(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function safeLink(itemId)
    local _, link = GetItemInfo(itemId)
    return link
end

-- Client item data is only a preview safeguard; the server remains the
-- authority for custom RequiredLevel values and every Apply request.  Until
-- the local item cache can prove an item is usable at the player's current
-- level, do not render that appearance in local mannequin, slot, or set UI.
local function getPlayerAppearancePreviewLevel()
    if type(UnitLevel) ~= "function" then
        return nil
    end

    local level = tonumber(UnitLevel("player"))
    if not level or level < 1 then
        return nil
    end

    return math.floor(level)
end

-- Returns true when the cached DBC requirement permits the preview, false
-- when it is known to be too high, and nil while the item data is unavailable.
-- Callers must treat nil as blocked and may query the item cache before retrying.
local function getItemPreviewLevelEligibility(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or itemId ~= math.floor(itemId) or itemId > 4294967295 then
        return false
    end

    local _, itemLink, _, _, requiredLevel = GetItemInfo(itemId)
    if type(itemLink) ~= "string" then
        return nil
    end

    requiredLevel = tonumber(requiredLevel)
    local playerLevel = getPlayerAppearancePreviewLevel()
    if not requiredLevel or requiredLevel < 0 or not playerLevel then
        return false
    end

    return requiredLevel <= playerLevel
end

local function getPreviewAppearanceLabel(itemId)
    local levelEligible = getItemPreviewLevelEligibility(itemId)
    if levelEligible == true then
        return safeLink(itemId) or ("item:"..tostring(itemId))
    end
    if levelEligible == nil then
        return "appearance data is loading"
    end
    return "unavailable at your current level"
end

local function getAppearanceKey(slotName, itemId)
    local numericItemId = tonumber(itemId)
    if not slotName or not numericItemId or numericItemId <= 0 then
        return nil
    end

    if type(ns.FindAppearance) == "function" then
        local canonicalItemId = ns.FindAppearance(slotName, numericItemId)
        if tonumber(canonicalItemId) then
            return tonumber(canonicalItemId)
        end
    end

    -- Keep unmapped IDs in a disjoint key space so they cannot collide with a
    -- canonical positive appearance ID.
    return -numericItemId
end

local function dedupeItemIdsByAppearance(slotName, itemIds)
    local uniqueItemIds = {}
    local seenAppearanceKeys = {}

    for index = 1, #(itemIds or {}) do
        local itemId = tonumber(itemIds[index])
        if itemId and itemId > 0 then
            local appearanceKey = getAppearanceKey(slotName, itemId) or -itemId
            if not seenAppearanceKeys[appearanceKey] then
                seenAppearanceKeys[appearanceKey] = true
                uniqueItemIds[#uniqueItemIds + 1] = itemId
            end
        end
    end

    return uniqueItemIds
end

local function getDisplayedItemIdForAppearance(slotName, selectedItemId, displayedItemIds)
    local numericItemId = tonumber(selectedItemId)
    if not slotName or not numericItemId or numericItemId <= 0 then
        return nil
    end

    local selectedAppearanceKey = getAppearanceKey(slotName, numericItemId)
    if not selectedAppearanceKey then
        return nil
    end

    for index = 1, #(displayedItemIds or {}) do
        local displayedItemId = tonumber(displayedItemIds[index])
        if displayedItemId == numericItemId then
            return displayedItemId
        end

        if displayedItemId and getAppearanceKey(slotName, displayedItemId) == selectedAppearanceKey then
            return displayedItemId
        end
    end

    return nil
end

local savedTransmogSetsSanitized = false
local function getSavedTransmogSets()
    -- Migrate from old DressMe variable name.
    -- Also migrate if AppearanceBuddyTransmogSavedSets is an empty table but
    -- DressMeTransmogSavedSets has entries (handles the case where a previous
    -- session wrote an empty table before migration had a chance to run).
    local existing = _G.AppearanceBuddyTransmogSavedSets
    local legacy   = _G.DressMeTransmogSavedSets
    local needMigrate = type(existing) ~= "table"
        or (type(legacy) == "table" and #legacy > 0 and #existing == 0)
    if needMigrate then
        if type(legacy) == "table" and #legacy > 0 then
            _G.AppearanceBuddyTransmogSavedSets = legacy
            _G.DressMeTransmogSavedSets = nil
        elseif type(existing) ~= "table" then
            _G.AppearanceBuddyTransmogSavedSets = {}
        end
    end

    if not savedTransmogSetsSanitized then
        local source = _G.AppearanceBuddyTransmogSavedSets
        local sanitized = {}
        local usedNames = {}
        local maximumSets = math.min(#source, ns.MAX_SAVED_TRANSMOG_SETS)

        for sourceIndex = 1, maximumSets do
            local setData = source[sourceIndex]
            if type(setData) == "table" then
                local baseName = trim(tostring(setData.name or "")):sub(1, 50)
                if baseName ~= "" then
                    local name = baseName
                    local suffixIndex = 2
                    while usedNames[string.lower(name)] do
                        local suffix = " ("..suffixIndex..")"
                        name = baseName:sub(1, math.max(1, 50 - #suffix))..suffix
                        suffixIndex = suffixIndex + 1
                    end
                    local items = {}
                    local itemsComplete = type(setData.items) == "table"
                    for itemIndex = 1, #SLOT_DATA do
                        local itemId = itemsComplete and tonumber(setData.items[itemIndex]) or nil
                        if itemId and itemId == itemId and itemId > 0 and itemId < math.huge
                            and itemId == math.floor(itemId) and itemId <= 4294967295 then
                            items[itemIndex] = itemId
                        elseif itemId == 0 or itemId == -1 then
                            items[itemIndex] = itemId
                        else
                            itemsComplete = false
                            break
                        end
                    end

                    local weaponEnchants = nil
                    if type(setData.weaponEnchants) == "table" then
                        local candidate = { explicitNo = {}, clear = {} }
                        local complete = true
                        for _, equipSlot in ipairs({15, 16, 17}) do
                            local enchantId = tonumber(setData.weaponEnchants[equipSlot]
                                or setData.weaponEnchants[tostring(equipSlot)])
                            if not enchantId or enchantId ~= math.floor(enchantId)
                                or not WEAPON_ENCHANT_OPTION_BY_ID[enchantId] then
                                complete = false
                                break
                            end
                            candidate[equipSlot] = enchantId
                            local explicitNo = setData.weaponEnchants.explicitNo
                            candidate.explicitNo[equipSlot] = enchantId == 0
                                and type(explicitNo) == "table"
                                and (explicitNo[equipSlot] == true or explicitNo[tostring(equipSlot)] == true
                                    or explicitNo[equipSlot] == 1 or explicitNo[tostring(equipSlot)] == 1)
                            local clear = setData.weaponEnchants.clear
                            candidate.clear[equipSlot] = type(clear) == "table"
                                and (clear[equipSlot] == true or clear[tostring(equipSlot)] == true
                                    or clear[equipSlot] == 1 or clear[tostring(equipSlot)] == 1)
                                or (enchantId == 0 and not candidate.explicitNo[equipSlot])
                        end
                        if complete then weaponEnchants = candidate end
                    end

                    if itemsComplete then
                        usedNames[string.lower(name)] = true
                        sanitized[#sanitized + 1] = {
                            name = name,
                            items = items,
                            weaponEnchants = weaponEnchants,
                        }
                    end
                end
            end
        end

        _G.AppearanceBuddyTransmogSavedSets = sanitized
        savedTransmogSetsSanitized = true
    end

    return _G.AppearanceBuddyTransmogSavedSets
end

local function sortSavedTransmogSets()
    table.sort(getSavedTransmogSets(), function(a, b)
        local nameA = tostring(a and a.name or "")
        local nameB = tostring(b and b.name or "")
        if nameA == nameB then
            return false
        end
        return nameA < nameB
    end)
end

local function normalizeServerState(itemId, realItemId)
    -- V2 owns equipment truth; WoW's client inventory cache can be cold at login.
    local item = tonumber(itemId)
    local real = tonumber(realItemId)

    if real == 0 then
        real = nil
    end

    local effectiveId
    if not real or real <= 0 then
        effectiveId = nil
    elseif item == 0 then
        effectiveId = 0
    elseif item and item > 0 then
        effectiveId = item
    else
        effectiveId = real
    end

    return {
        itemId = item,
        realItemId = real,
        effectiveId = effectiveId,
    }
end

local state = {
    enabled = AIO and type(AIO.AddHandlers) == "function" and type(AIO.Handle) == "function",
    disabledReason = nil,
    applyingAppearanceSet = false,
    applyingUnlockedItemSet = false,
    protocolVersion = 2,
    synced = false,
    weaponEnchantSynced = false,
    hasServerSnapshot = false,
    syncFailureMessage = nil,
    itemListInvalidatedBySyncFailure = false,
    appearanceLevelChanged = false,
    syncRequestToken = 0,
    syncRequestPending = false,
    syncRequestStartedAt = 0,
    syncRequestRetryCount = 0,
    syncRequestTimeoutSeconds = 5,
    syncRequestMaxRetries = 1,
    postMutationModelRebindPending = false,
    postMutationModelRebindRequestToken = 0,
    mutationRequestToken = 0,
    mutationRequestStartedAt = 0,
    mutationRequestTimeoutSeconds = 10,
    currentSlot = SLOT_DATA[1].name,
    currentPage = 1,
    hasMorePages = false,
    totalItemCount = 0,
    requestToken = 0,
    appearancePageRequestPending = false,
    appearancePageRequestStartedAt = 0,
    appearancePageRequestRetryCount = 0,
    appearancePageRequestTimeoutSeconds = 5,
    appearancePageGeneration = 0,
    appearancePageContext = nil,
    appearancePageRequest = nil,
    appearancePager = TransmogPaging.New(
        APPEARANCE_PAGE_POLICY.scrollDebounceSeconds,
        APPEARANCE_PAGE_POLICY.minimumIntervalSeconds,
        APPEARANCE_PAGE_POLICY.maximumRateLimitRetries,
        APPEARANCE_PAGE_POLICY.retryMarginSeconds
    ),
    search = "",
    viewMode = "items",
    setSource = SET_SOURCE_SAVED,
    setSearchBySource = {
        [SET_SOURCE_SAVED] = "",
        [SET_SOURCE_CATALOG] = "",
    },
    itemSetCatalog = {},
    itemSetCatalogById = {},
    itemSetDetailsById = {},
    itemSetDetailRequests = {},
    itemSetDetailFailures = {},
    itemSetDetailRequestToken = 0,
    itemSetCatalogLoaded = false,
    itemSetCatalogRequestPending = false,
    itemSetCatalogRequestToken = 0,
    itemSetCatalogRequestStartedAt = 0,
    itemSetCatalogRequestTimeoutSeconds = 15,
    itemSetCatalogRequestPage = 0,
    itemSetCatalogRequestSearch = "",
    itemSetCatalogPage = 0,
    itemSetCatalogHasMore = false,
    itemSetCatalogTotal = 0,
    itemSetCatalogSearch = "",
    itemSetCatalogPageSize = 100,
    itemSetCatalogLastRefreshAt = 0,
    itemSetCatalogDirty = true,
    itemSetCatalogDirtyAt = 0,
    itemSetCatalogLevelChanged = false,
    itemSetCatalogRevision = 0,
    savedSetRevision = 0,
    selectedSavedSetName = nil,
    selectedCatalogSetId = nil,
    slotPages = {},
    slotPageAnchors = {},
    weaponFilterBySlot = {
        ["Main Hand"] = "all",
        ["Off-hand"] = "all",
        ["Ranged"] = "all",
    },
    pageLookupToken = 0,
    pageLookupSlot = nil,
    pageLookupAnchor = nil,
    pageLookupFilter = nil,
    pageLookupPageSize = nil,
    pageLookupRequestPending = false,
    pageLookupRequestStartedAt = 0,
    pageLookupRequestRetryCount = 0,
    pageLookupRequestTimeoutSeconds = 5,
    pageLookupRateLimitRetryAt = 0,
    pageLookupRateLimitRetryCount = 0,
    pageLookupRateLimitMaxRetries = APPEARANCE_PAGE_POLICY.maximumRateLimitRetries,
    previousUnit = nil,
    previousView = nil,
    server = {},
    tooltipEquipmentBySlot = {},
    tooltipEquipmentRequestToken = 0,
    tooltipEquipmentRequestPending = false,
    tooltipEquipmentRequestStartedAt = 0,
    tooltipEquipmentRetryAt = 0,
    preview = {},
    slotButtons = {},
    weaponEnchantServer = { [15] = 0, [16] = 0, [17] = 0 },
    weaponEnchantPreview = { [15] = 0, [16] = 0, [17] = 0 },
    weaponEnchantExplicitNoServer = { [15] = false, [16] = false, [17] = false },
    weaponEnchantExplicitNoPreview = { [15] = false, [16] = false, [17] = false },
    weaponEnchantEligible = {},
    weaponEnchantButtons = {},
    enchantingEquipSlot = nil,
    enchantPage = 1,
    enchantHasMorePages = false,
    slotCosts = {},
    money = type(GetMoney) == "function" and (tonumber(GetMoney()) or 0) or 0,
    costSynced = false,
    costRequestPending = false,
    costRequestToken = 0,
    scanRequestToken = 0,
    scanRequestPending = false,
    scanRequestStartedAt = 0,
    setPreviewCost = 0,
    showEquippedGear = false,
    randomRequestToken = 0,
    randomRequestStartedAt = 0,
    randomizeCooldownUntil = 0,
    randomizeMinIntervalSeconds = 0.75,
    randomizeRequestTimeoutSeconds = 8,
    randomizeTimeoutBackoffSeconds = 2,
    randomizePending = false,
    randomizeSnapshot = nil,
}

local function isTransmogTabVisible()
    return transmogTab:IsVisible()
end

local function isCatalogSetViewVisible()
    local setsFrame = transmogTab.setsFrame
    return isTransmogTabVisible()
        and state.viewMode == "sets"
        and state.setSource == SET_SOURCE_CATALOG
        and setsFrame ~= nil
        and setsFrame:IsVisible()
end

for _, info in ipairs(SLOT_DATA) do
    state.server[info.name] = normalizeServerState(nil, nil)
    state.preview[info.name] = {
        mode = "restore",
        itemId = nil,
        effectiveId = nil,
    }
end

-- AzerothCore stores a transmog as a PLAYER_VISIBLE_ITEM override. The stock
-- client therefore builds paper-doll set tooltips from the appearance entry,
-- even though the server applies set bonuses from the real equipped item.
-- Keep this isolated so the large legacy file stays below Lua's local limit.
do
local CHARACTER_SLOT_FRAME_BY_INVENTORY_SLOT = {
    [1] = "CharacterHeadSlot",
    [3] = "CharacterShoulderSlot",
    [4] = "CharacterShirtSlot",
    [5] = "CharacterChestSlot",
    [6] = "CharacterWaistSlot",
    [7] = "CharacterLegsSlot",
    [8] = "CharacterFeetSlot",
    [9] = "CharacterWristSlot",
    [10] = "CharacterHandsSlot",
    [15] = "CharacterBackSlot",
    [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot",
    [18] = "CharacterRangedSlot",
    [19] = "CharacterTabardSlot",
}

local ITEM_SET_ACTIVE_COLOR = { 1.0, 0.82, 0.0 }
local ITEM_SET_INACTIVE_COLOR = { 0.5, 0.5, 0.5 }
local ITEM_SET_BONUS_ACTIVE_COLOR = { 0.0, 1.0, 0.0 }
local itemSetMetadataByItemId = {}
local itemSetProbeTooltip = _G.AppearanceBuddyItemSetProbeTooltip

local function parseItemSetHeader(text)
    local name, count, total = tostring(text or ""):match("^(.-)%s*%((%d+)%s*/%s*(%d+)%)$")
    count = tonumber(count)
    total = tonumber(total)
    name = trim(name)
    if name == "" or not count or not total or count < 0 or total <= 0 or count > total then
        return nil
    end
    return name, count, total
end

local function getTooltipLeftText(tooltip, line)
    local tooltipName = tooltip and tooltip.GetName and tooltip:GetName()
    local fontString = tooltipName and _G[tooltipName .. "TextLeft" .. line] or nil
    return fontString, fontString and fontString:GetText() or nil
end

local function getItemSetMetadata(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then
        return nil, nil, true
    end
    if type(GetItemInfo) ~= "function" or not GetItemInfo(itemId) then
        return nil, nil, false
    end

    local cached = itemSetMetadataByItemId[itemId]
    if cached ~= nil then
        if cached == false then
            return nil, nil, true
        end
        return cached.name, cached.total, true
    end

    if not itemSetProbeTooltip and type(CreateFrame) == "function" and UIParent then
        itemSetProbeTooltip = CreateFrame(
            "GameTooltip",
            "AppearanceBuddyItemSetProbeTooltip",
            UIParent,
            "GameTooltipTemplate"
        )
    end
    if not itemSetProbeTooltip then
        return nil, nil, false
    end

    itemSetProbeTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    itemSetProbeTooltip:ClearLines()
    local ok = pcall(itemSetProbeTooltip.SetHyperlink, itemSetProbeTooltip, "item:" .. itemId)
    if not ok then
        itemSetProbeTooltip:Hide()
        return nil, nil, false
    end

    local name, _, total
    for line = 1, itemSetProbeTooltip:NumLines() do
        local _, text = getTooltipLeftText(itemSetProbeTooltip, line)
        local candidateName, _, candidateTotal = parseItemSetHeader(text)
        if candidateName then
            name = candidateName
            total = candidateTotal
            break
        end
    end
    itemSetProbeTooltip:Hide()

    if not name then
        itemSetMetadataByItemId[itemId] = false
        return nil, nil, true
    end

    itemSetMetadataByItemId[itemId] = { name = name, total = total }
    return name, total, true
end

local function getActualEquippedSetItems(setName)
    if type(GetItemInfo) ~= "function" then
        return 0, {}, false
    end

    local count = 0
    local itemNames = {}
    for _, info in ipairs(SLOT_DATA) do
        local itemId = state.tooltipEquipmentBySlot[info.slotId]
        if itemId == nil then
            local serverState = state.server[info.name]
            itemId = serverState and serverState.realItemId or nil
        end
        if itemId == nil then
            return 0, {}, false
        end

        local itemSetName, _, metadataReady = getItemSetMetadata(itemId)
        if not metadataReady then
            return 0, {}, false
        end
        if itemSetName == setName then
            count = count + 1
            local itemName = GetItemInfo(itemId)
            if itemName then
                itemNames[itemName] = true
            end
        end
    end
    return count, itemNames, true
end

local function recolorItemSetTooltip(tooltip, headerLine, itemNames, actualCount)
    local itemSection = true
    for line = headerLine + 1, tooltip:NumLines() do
        local fontString, text = getTooltipLeftText(tooltip, line)
        if not fontString then
            break
        end

        text = tostring(text or "")
        local threshold = tonumber(text:match("^%((%d+)%)"))
        if threshold then
            itemSection = false
            local color = actualCount >= threshold and ITEM_SET_BONUS_ACTIVE_COLOR or ITEM_SET_INACTIVE_COLOR
            fontString:SetTextColor(color[1], color[2], color[3])
        elseif itemSection then
            if text == "" then
                break
            end
            local color = itemNames[text] and ITEM_SET_ACTIVE_COLOR or ITEM_SET_INACTIVE_COLOR
            fontString:SetTextColor(color[1], color[2], color[3])
        end
    end
end

local function correctCharacterItemSetTooltip(inventorySlot)
    if not GameTooltip or not GameTooltip:IsShown() then
        return
    end

    local headerLine, headerFontString, setName, displayedCount, total
    for line = 1, GameTooltip:NumLines() do
        local fontString, text = getTooltipLeftText(GameTooltip, line)
        local candidateName, candidateCount, candidateTotal = parseItemSetHeader(text)
        if candidateName then
            local actualCount, itemNames, stateReady = getActualEquippedSetItems(candidateName)
            if stateReady then
                headerLine = line
                headerFontString = fontString
                setName = candidateName
                displayedCount = candidateCount
                total = candidateTotal
                if actualCount ~= displayedCount then
                    headerFontString:SetText(setName .. " (" .. actualCount .. "/" .. total .. ")")
                    recolorItemSetTooltip(GameTooltip, headerLine, itemNames, actualCount)
                    GameTooltip:Show()
                end
                return
            end
        end
    end
end

local function hookCharacterItemSetTooltips()
    for inventorySlot, frameName in pairs(CHARACTER_SLOT_FRAME_BY_INVENTORY_SLOT) do
        local slotFrame = _G[frameName]
        if slotFrame and slotFrame.HookScript and not slotFrame.appearanceBuddySetTooltipHooked then
            slotFrame:HookScript("OnEnter", function()
                correctCharacterItemSetTooltip(inventorySlot)
            end)
            slotFrame.appearanceBuddySetTooltipHooked = true
        end
    end
end

hookCharacterItemSetTooltips()

-- The paper-doll UI is load-on-demand on a stock 3.3.5 client.  Hook it now
-- when it already exists, and once more when Blizzard loads it later.
local characterUiLoadFrame = CreateFrame("Frame")
if characterUiLoadFrame then
    characterUiLoadFrame:RegisterEvent("ADDON_LOADED")
    characterUiLoadFrame:SetScript("OnEvent", function(self, _, loadedAddon)
        if loadedAddon == "Blizzard_CharacterUI" then
            hookCharacterItemSetTooltips()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
end

local function isServerStateReady()
    return state.synced and state.weaponEnchantSynced and state.costSynced
end

-- Random previews can change up to every equipped slot. Pace them even when
-- the server replies quickly so item-data requests never become a burst.
state.getRandomizeTime = function()
    local now = type(GetTime) == "function" and GetTime() or 0
    return tonumber(now) or 0
end

state.isRandomizeCoolingDown = function()
    local now = state.getRandomizeTime()
    return now > 0 and now < (tonumber(state.randomizeCooldownUntil) or 0)
end

state.getWeaponFilterOption = function(slotName, filterKey)
    for _, option in ipairs(transmogTab.weaponFilterOptions[slotName] or {}) do
        if option.key == filterKey then
            return option
        end
    end
    return nil
end

state.getWeaponFilterKey = function(slotName)
    if not transmogTab.weaponFilterOptions[slotName] then
        return "all"
    end

    local key = tostring(state.weaponFilterBySlot[slotName] or "all")
    if not state.getWeaponFilterOption(slotName, key) then
        key = "all"
        state.weaponFilterBySlot[slotName] = key
    end
    return key
end

state.refreshWeaponFilterButton = function()
    local button = transmogTab.buttonWeaponFilter
    if not button then
        return
    end

    local slotName = state.currentSlot
    local option = state.getWeaponFilterOption(slotName, state.getWeaponFilterKey(slotName))
    if state.viewMode == "items" and not state.enchantingEquipSlot and option then
        button:SetText(option.label.."  v")
        button:Show()
    else
        button:Hide()
    end
end

local function slotHasRestorableAppearance(slotName)
    local serverState = slotName and state.server[slotName]
    local realItemId = serverState and tonumber(serverState.realItemId) or nil
    return realItemId and realItemId > 0
end

local function copyServerToPreview(slotName)
    local serverState = state.server[slotName]
    local previewState = state.preview[slotName]

    previewState.itemId = nil

    local hasEquippedItem = serverState.realItemId and serverState.realItemId > 0
    if not hasEquippedItem then
        -- Retain the persisted assignment so it can return on re-equip, but do
        -- not render an appearance on the mannequin for an empty slot.
        if serverState.itemId == 0 then
            previewState.mode = "hidden"
        elseif serverState.itemId and serverState.itemId > 0 then
            previewState.mode = "item"
            previewState.itemId = serverState.itemId
        else
            previewState.mode = "restore"
        end
        previewState.effectiveId = nil
    elseif serverState.itemId == 0 then
        previewState.mode = "hidden"
        previewState.effectiveId = 0
    elseif serverState.itemId and serverState.itemId > 0 then
        previewState.mode = "item"
        previewState.itemId = serverState.itemId
        previewState.effectiveId = serverState.itemId
    else
        previewState.mode = "restore"
        previewState.effectiveId = serverState.realItemId
    end
end

local function copyAllServerToPreview()
    for _, info in ipairs(SLOT_DATA) do
        copyServerToPreview(info.name)
    end
end

local function copyWeaponEnchantServerToPreview(equipSlot)
    equipSlot = tonumber(equipSlot)
    if equipSlot and state.weaponEnchantPreview[equipSlot] ~= nil then
        state.weaponEnchantPreview[equipSlot] = tonumber(state.weaponEnchantServer[equipSlot]) or 0
        state.weaponEnchantExplicitNoPreview[equipSlot] = state.weaponEnchantExplicitNoServer[equipSlot] == true
    end
end

local function copyAllWeaponEnchantServerToPreview()
    for _, equipSlot in ipairs({15, 16, 17}) do
        copyWeaponEnchantServerToPreview(equipSlot)
    end
end

local function isWeaponEnchantDirty(equipSlot)
    equipSlot = tonumber(equipSlot)
    if not equipSlot then
        return false
    end
    return (tonumber(state.weaponEnchantPreview[equipSlot]) or 0)
        ~= (tonumber(state.weaponEnchantServer[equipSlot]) or 0)
        or (state.weaponEnchantExplicitNoPreview[equipSlot] == true)
            ~= (state.weaponEnchantExplicitNoServer[equipSlot] == true)
end

local function snapshotCurrentTransmogSet()
    local items = {}

    for index, info in ipairs(SLOT_DATA) do
        local previewState = state.preview[info.name]
        if previewState.mode == "hidden" then
            items[index] = 0
        elseif previewState.mode == "item" and previewState.itemId then
            items[index] = previewState.itemId
        else
            -- Restore/unassigned is always the -1 sentinel, including for an
            -- empty equipment slot. Zero is reserved exclusively for an
            -- intentional hidden appearance.
            items[index] = -1
        end
    end

    return items
end

local function snapshotCurrentWeaponEnchants()
    return {
        [15] = tonumber(state.weaponEnchantPreview[15]) or 0,
        [16] = tonumber(state.weaponEnchantPreview[16]) or 0,
        [17] = tonumber(state.weaponEnchantPreview[17]) or 0,
        explicitNo = {
            [15] = state.weaponEnchantExplicitNoPreview[15] == true,
            [16] = state.weaponEnchantExplicitNoPreview[16] == true,
            [17] = state.weaponEnchantExplicitNoPreview[17] == true,
        },
    }
end

local function getTransmogSetPreviewItem(index, itemIds)
    local requestedItemId = type(itemIds) == "table" and tonumber(itemIds[index]) or nil
    local slotName = SLOT_DATA[index] and SLOT_DATA[index].name or nil

    if requestedItemId and requestedItemId > 0 then
        return requestedItemId
    end

    if requestedItemId == 0 then
        return 0
    end

    if slotName and state.server[slotName] and state.server[slotName].realItemId then
        return state.server[slotName].realItemId
    end

    return 0
end

local function buildPreviewItemsFromTransmogSet(itemIds)
    local previewItems = {}

    for index = 1, #SLOT_DATA do
        previewItems[index] = getTransmogSetPreviewItem(index, itemIds)
    end

    return previewItems
end

local function ensureSetPreviewBackground(model)
    if not model or not model.backgroundTextures then
        return
    end

    for _, texture in pairs(model.backgroundTextures) do
        texture:Hide()
    end
end

local function updateSetPreviewBackground(model)
    local setsFrame = transmogTab and transmogTab.setsFrame
    model = model or (setsFrame and setsFrame.previewModel)
    ensureSetPreviewBackground(model)
end

local function getSetListIconItemId(setData)
    if type(setData) ~= "table" then
        return nil
    end

    local catalogIconItemId = tonumber(setData.iconItemId)
    if catalogIconItemId and catalogIconItemId > 0 then
        return catalogIconItemId
    end

    for _, slotIndex in ipairs(SET_LIST_ICON_SLOT_PRIORITY) do
        local unlockedItemId = type(setData.unlockedItems) == "table" and tonumber(setData.unlockedItems[slotIndex]) or nil
        if unlockedItemId and unlockedItemId > 0 then
            return unlockedItemId
        end

        local previewItemId = type(setData.fullItems) == "table" and tonumber(setData.fullItems[slotIndex]) or nil
        if previewItemId and previewItemId > 0 then
            return previewItemId
        end

        local savedItemId = type(setData.items) == "table" and tonumber(setData.items[slotIndex]) or nil
        if savedItemId and savedItemId > 0 then
            return savedItemId
        end
    end

    return nil
end

local function ensureSetListButtonLayout(button)
    if not button then
        return nil
    end

    if not button.iconTexture then
        button.iconTexture = button:CreateTexture(nil, "ARTWORK")
        button.iconTexture:SetSize(26, 26)
        button.iconTexture:SetPoint("LEFT", button, "LEFT", 5, 0)
        button.iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.iconTexture:Hide()

        button.iconBackdrop = button:CreateTexture(nil, "BACKGROUND")
        button.iconBackdrop:SetPoint("TOPLEFT", button.iconTexture, "TOPLEFT", -1, 1)
        button.iconBackdrop:SetPoint("BOTTOMRIGHT", button.iconTexture, "BOTTOMRIGHT", 1, -1)
        button.iconBackdrop:SetTexture("Interface\\Buttons\\WHITE8X8")
        button.iconBackdrop:SetVertexColor(0.12, 0.12, 0.12, 0.85)
        button.iconBackdrop:Hide()

        button.subtitle = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.subtitle:SetJustifyH("LEFT")
        button.subtitle:SetTextColor(0.52, 0.49, 0.43)
        button.CancelPendingWork = function(self)
            if state.cancelSetListButtonIconQuery then
                state.cancelSetListButtonIconQuery(self)
            end
            self.catalogIconItemId = nil
            self.iconNeedsItemData = false
            self.setName = nil
            self.savedSet = nil
            self.itemSetId = nil
            self.fullLabelText = nil
        end
    end

    button:SetHeight(36)

    local label = button:GetFontString()
    if label then
        label:ClearAllPoints()
        if button.iconTexture:IsShown() then
            label:SetPoint("TOPLEFT", button.iconTexture, "TOPRIGHT", 5, 4)
        else
            label:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
        end
        label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.84, 0.66, 0.086)
        if button.subtitle then
            button.subtitle:ClearAllPoints()
            button.subtitle:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
            button.subtitle:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        end
    end

    return label
end

state.cancelSetListButtonIconQuery = function(button)
    if not button then
        return
    end

    local wasPending = button.iconQueryPending == true
    local handle = button.iconQueryHandle
    if handle and handle.Cancel then
        handle:Cancel()
    end
    button.iconQueryHandle = nil
    button.iconQueryPending = false
    if wasPending and (tonumber(button.catalogIconItemId) or 0) > 0 then
        button.iconNeedsItemData = true
    end
end

local function hideSetListButtonIcon(button)
    state.cancelSetListButtonIconQuery(button)
    if button.iconTexture then
        button.iconTexture:Hide()
    end
    if button.iconBackdrop then
        button.iconBackdrop:Hide()
    end
    button.iconNeedsItemData = false
    ensureSetListButtonLayout(button)
end

local function setSetListButtonIcon(button, itemId, requestItemData)
    if not button then
        return
    end

    ensureSetListButtonLayout(button)
    itemId = tonumber(itemId) or 0
    local iconChanged = button.catalogIconItemId ~= itemId
    if iconChanged then
        state.cancelSetListButtonIconQuery(button)
    end
    button.catalogIconItemId = itemId
    if iconChanged then
        button.iconQueryPending = false
        button.iconNeedsItemData = false
    end

    if itemId <= 0 then
        hideSetListButtonIcon(button)
        return
    end

    -- Do not use a cached icon as a back door around the preview-level gate.
    -- A saved set may contain any historical item ID, including one the player
    -- cannot currently use.
    if getItemPreviewLevelEligibility(itemId) == false then
        hideSetListButtonIcon(button)
        return
    end

    if button.iconBackdrop then
        button.iconBackdrop:Show()
    end
    if button.iconTexture then
        button.iconTexture:Show()
        button.iconTexture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    ensureSetListButtonLayout(button)

    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
    if texture then
        state.cancelSetListButtonIconQuery(button)
        if button.catalogIconItemId == itemId and button.iconTexture then
            button.iconTexture:SetTexture(texture)
        end
        button.iconNeedsItemData = false
        return
    end

    if requestItemData == false then
        button.iconNeedsItemData = true
        return
    end

    if button.iconQueryPending then
        return
    end

    button.iconNeedsItemData = false
    button.iconQueryPending = true
    button.iconQueryHandle = true
    local queryHandle = ns.QueryItem(itemId, function(queriedItemId, success)
        if not button or button.catalogIconItemId ~= queriedItemId then
            return
        end

        button.iconQueryHandle = nil
        button.iconQueryPending = false
        if not success then
            button.iconNeedsItemData = true
            return
        end

        if getItemPreviewLevelEligibility(queriedItemId) ~= true then
            hideSetListButtonIcon(button)
            return
        end

        local _, _, _, _, _, _, _, _, _, queriedTexture = GetItemInfo(queriedItemId)
        if queriedTexture and button.iconTexture then
            button.iconTexture:SetTexture(queriedTexture)
        end
    end)
    if queryHandle and button.iconQueryHandle then
        button.iconQueryHandle = queryHandle
    end
end

state.cancelSetListIconQueries = function(listFrame)
    for index = 1, listFrame and listFrame:GetSize() or 0 do
        state.cancelSetListButtonIconQuery(listFrame:GetButton(index))
    end
end

state.resumeSetListIconQueries = function(listFrame)
    for index = 1, listFrame and listFrame:GetSize() or 0 do
        local button = listFrame:GetButton(index)
        if button and button.catalogIconItemId
            and (button.savedSet or button.iconNeedsItemData) then
            setSetListButtonIcon(button, button.catalogIconItemId, true)
        end
    end
end

local function ensureSetListButtonTooltip(button)
    if not button or button.fullLabelTooltipHooked then
        return
    end

    button:HookScript("OnEnter", function(self)
        if self.iconNeedsItemData and self.catalogIconItemId then
            setSetListButtonIcon(self, self.catalogIconItemId, true)
        end

        local fullText = self.fullLabelText
        if not fullText or fullText == "" then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(fullText, 1, 0.82, 0)
        if self.setName and GetSettings and GetSettings().showShortcutsInTooltip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffff8080Ctrl + Right Click:|r permanently remove this saved set.")
        end
        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button.fullLabelTooltipHooked = true
end

local function getCurrentSlotPageAnchor(slotName)
    local previewState = state.preview[slotName]
    local serverState = state.server[slotName]

    if previewState and previewState.mode == "item" and previewState.itemId and previewState.itemId > 0 then
        return previewState.itemId
    end

    if previewState and previewState.mode == "hidden" then
        return 0
    end

    if serverState and serverState.itemId and serverState.itemId > 0 then
        return serverState.itemId
    end

    if serverState and serverState.itemId == 0 then
        return 0
    end

    if previewState and previewState.effectiveId and previewState.effectiveId > 0 then
        return previewState.effectiveId
    end

    if serverState and serverState.realItemId and serverState.realItemId > 0 then
        return serverState.realItemId
    end

    return 0
end

local function rememberSlotPage(slotName, page, anchor)
    slotName = slotName or state.currentSlot
    if not slotName then
        return
    end

    page = tonumber(page) or 1
    if page < 1 then
        page = 1
    end

    if anchor == nil then
        anchor = getCurrentSlotPageAnchor(slotName)
    end

    state.slotPages[slotName] = page
    state.slotPageAnchors[slotName] = tonumber(anchor) or 0
end

local function isSlotDirty(slotName)
    local serverState = state.server[slotName]
    local previewState = state.preview[slotName]

    if previewState.mode == "restore" then
        return serverState.itemId ~= nil
    elseif previewState.mode == "hidden" then
        return serverState.itemId ~= 0
    elseif previewState.mode == "item" then
        if serverState.itemId == previewState.itemId then
            return false
        end
        if tonumber(serverState.itemId) and tonumber(serverState.itemId) > 0
            and tonumber(previewState.itemId) and tonumber(previewState.itemId) > 0 then
            return getAppearanceKey(slotName, serverState.itemId)
                ~= getAppearanceKey(slotName, previewState.itemId)
        end
        return true
    end

    return false
end

local function getDirtyCount()
    local total = 0
    for _, info in ipairs(SLOT_DATA) do
        if isSlotDirty(info.name) then
            total = total + 1
        end
    end
    for _, equipSlot in ipairs({15, 16, 17}) do
        if isWeaponEnchantDirty(equipSlot) then
            total = total + 1
        end
    end
    return total
end

local function getPendingCost()
    local chargedSlots = {}
    local total = 0

    for _, info in ipairs(SLOT_DATA) do
        if isSlotDirty(info.name) then
            chargedSlots[info.name] = true
            total = total + (tonumber(state.slotCosts[info.name]) or 0)
        end
    end

    for _, equipSlot in ipairs({15, 16, 17}) do
        local slotName = WEAPON_NAME_BY_EQUIPMENT_SLOT[equipSlot]
        if isWeaponEnchantDirty(equipSlot) and slotName and not chargedSlots[slotName] then
            chargedSlots[slotName] = true
            total = total + (tonumber(state.slotCosts[slotName]) or 0)
        end
    end

    return math.max(0, math.floor(total))
end

local function getAppearanceSetCost(itemIds, weaponEnchants)
    local chargedSlots = {}
    local total = 0

    for index, info in ipairs(SLOT_DATA) do
        local target = type(itemIds) == "table" and tonumber(itemIds[index]) or -1
        local serverState = state.server[info.name]
        local current = serverState and tonumber(serverState.itemId) or nil
        local changed

        if target and target > 0 then
            target = math.floor(target)
            changed = current ~= target
            if changed and current and current > 0 then
                changed = getAppearanceKey(info.name, current) ~= getAppearanceKey(info.name, target)
            end
        elseif target == 0 then
            changed = current ~= 0
        else
            changed = current ~= nil
        end

        if changed and serverState and (tonumber(serverState.realItemId) or 0) > 0 then
            chargedSlots[info.name] = true
            total = total + (tonumber(state.slotCosts[info.name]) or 0)
        end
    end

    for _, equipSlot in ipairs({15, 16, 17}) do
        local slotName = WEAPON_NAME_BY_EQUIPMENT_SLOT[equipSlot]
        local target = type(weaponEnchants) == "table"
            and tonumber(weaponEnchants[equipSlot] or weaponEnchants[tostring(equipSlot)])
            or nil
        local explicitNoSlots = type(weaponEnchants) == "table" and weaponEnchants.explicitNo or nil
        local clearSlots = type(weaponEnchants) == "table" and weaponEnchants.clear or nil
        local targetExplicitNo = target == 0
            and type(explicitNoSlots) == "table"
            and (explicitNoSlots[equipSlot] == true or explicitNoSlots[tostring(equipSlot)] == true
                or explicitNoSlots[equipSlot] == 1 or explicitNoSlots[tostring(equipSlot)] == 1)
        -- A bare zero clears a cosmetic override. Only an explicit marker may
        -- suppress the weapon's real enchant effect.
        local targetClear = type(clearSlots) == "table"
            and (clearSlots[equipSlot] == true or clearSlots[tostring(equipSlot)] == true
                or clearSlots[equipSlot] == 1 or clearSlots[tostring(equipSlot)] == 1)
            or (target == 0 and not targetExplicitNo)
        local currentExplicitNo = state.weaponEnchantExplicitNoServer[equipSlot] == true
        local changed = targetClear
            and ((tonumber(state.weaponEnchantServer[equipSlot]) or 0) > 0 or currentExplicitNo)
            or (not targetClear and target ~= nil
                and (target ~= (tonumber(state.weaponEnchantServer[equipSlot]) or 0)
                    or targetExplicitNo ~= currentExplicitNo))
        if changed
            and slotName
            and not chargedSlots[slotName]
            and state.server[slotName]
            and (tonumber(state.server[slotName].realItemId) or 0) > 0 then
            chargedSlots[slotName] = true
            total = total + (tonumber(state.slotCosts[slotName]) or 0)
        end
    end

    return math.max(0, math.floor(total))
end

local function getDisplayedCost()
    if state.viewMode == "sets" then
        return math.max(0, math.floor(tonumber(state.setPreviewCost) or 0))
    end
    return getPendingCost()
end

state.getRestoreAllCost = function()
    local restoreAll = {}
    for index in ipairs(SLOT_DATA) do
        restoreAll[index] = -1
    end
    return getAppearanceSetCost(restoreAll, {
        [15] = 0, [16] = 0, [17] = 0,
        clear = { [15] = true, [16] = true, [17] = true },
    })
end

local updateCostDisplay

local function hasAppliedTransmogs()
    for _, info in ipairs(SLOT_DATA) do
        if state.server[info.name].itemId ~= nil then
            return true
        end
    end

    for _, equipSlot in ipairs({15, 16, 17}) do
        if (tonumber(state.weaponEnchantServer[equipSlot]) or 0) > 0
            or state.weaponEnchantExplicitNoServer[equipSlot] == true then
            return true
        end
    end

    return false
end

local function getPreviewSubclass(slotName, itemId)
    local subclass = SLOT_PREVIEW_SUBCLASS[slotName] or DEFAULT_ARMOR_SUBCLASS[playerClassFileName]
    if WEAPON_SLOT[slotName] and tonumber(itemId) and type(ns.FindAppearance) == "function" then
        local _, itemSubclass = ns.FindAppearance(slotName, tonumber(itemId))
        if itemSubclass then
            subclass = itemSubclass
        end
    end

    return subclass
end

local TWO_HANDED_WEAPON_EQUIP_LOCATION = "INVTYPE_2HWEAPON"

local function isTwoHandedWeaponPreviewItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or type(GetItemInfo) ~= "function" then
        return false
    end

    -- ItemEquipLoc is supplied by the client's authoritative item query. It
    -- covers custom or newly added entries that are not present in our local
    -- appearance-subclass index.
    local _, _, _, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemId)
    return itemEquipLoc == TWO_HANDED_WEAPON_EQUIP_LOCATION
end

local function isLargeWeaponPreviewSubclass(subclass)
    return type(subclass) == "string"
        and (string.sub(subclass, 1, 2) == "2H"
            or subclass == "Polearm"
            or subclass == "Staff")
end

local function needsLargeWeaponMiniPreview(itemId, subclass)
    -- The item's inventory classification is the rule. The local subclass
    -- remains a cold-cache fallback so existing known 2H/staff/polearm cards
    -- retain their framing while an item query is still pending.
    return isTwoHandedWeaponPreviewItem(itemId)
        or isLargeWeaponPreviewSubclass(subclass)
end

local function getPreviewSetup(slotName, itemId)
    local subclass = getPreviewSubclass(slotName, itemId)
    local version = ns.GetPreviewSetupVersion and ns.GetPreviewSetupVersion() or "classic"
    return ns.GetPreviewSetup(version, playerRaceFileName, playerSex, slotName, subclass), subclass
end

local function getListPreviewSetup(slotName, itemId)
    local baseSetup, subclass = getPreviewSetup(slotName, itemId)
    baseSetup = baseSetup or {}
    local layout = WEAPON_SLOT[slotName] and PREVIEW_CARD_LAYOUT.weapon or PREVIEW_CARD_LAYOUT.armor
    local x = tonumber(baseSetup.x) or 0

    -- DressUpModel's X position is the zoom axis. Long weapons need a wider
    -- card framing, so move their authored camera halfway toward the default.
    if WEAPON_SLOT[slotName] and needsLargeWeaponMiniPreview(itemId, subclass) then
        x = x * LARGE_WEAPON_MINI_PREVIEW_X_SCALE
    end

    -- Keep Appearance Buddy's card/grid layout, but place the model with the
    -- exact race/sex/slot/subclass coordinates authored for DressMe. DressMe
    -- leaves the DressUpModel on its default camera so these coordinates crop
    -- each slot instead of forcing a full-body view.
    return layout.width,
        layout.height,
        x,
        tonumber(baseSetup.y) or 0,
        tonumber(baseSetup.z) or 0,
        tonumber(baseSetup.facing) or 0,
        tonumber(baseSetup.sequence) or 3
end

local function getCurrentSlotPageSize(slotName)
    local width, height = getListPreviewSetup(slotName)
    width = tonumber(width) or 0
    height = tonumber(height) or 0

    if width <= 0 or height <= 0 then
        return DEFAULT_TRANSMOG_PAGE_SIZE
    end

    local listWidth = tonumber(transmogTab.list and transmogTab.list:GetWidth()) or 0
    local listHeight = tonumber(transmogTab.list and transmogTab.list:GetHeight()) or 0
    if listWidth <= 0 or listHeight <= 0 then
        return DEFAULT_TRANSMOG_PAGE_SIZE
    end

    local columns = math.max(1, math.floor((listWidth + PREVIEW_GRID_GAP_X) / width))
    local rows = math.max(1, math.floor((listHeight + PREVIEW_GRID_GAP_Y) / height))
    return math.max(1, columns * rows)
end

state.getAppearancePageTime = function()
    local now = type(GetTime) == "function" and tonumber(GetTime()) or 0
    return now and now > 0 and now or 0
end

state.captureAppearancePageContext = function()
    local slotName = state.currentSlot
    return {
        slotName = slotName,
        slotId = SLOT_ID_BY_NAME[slotName],
        search = trim(transmogTab.searchBox:GetText()),
        pageSize = getCurrentSlotPageSize(slotName),
        weaponFilter = state.getWeaponFilterKey(slotName),
    }
end

state.appearancePageContextsEqual = function(left, right)
    return left ~= nil and right ~= nil
        and left.slotName == right.slotName
        and left.slotId == right.slotId
        and left.search == right.search
        and left.pageSize == right.pageSize
        and left.weaponFilter == right.weaponFilter
end

state.isAppearancePageContextCurrent = function(context)
    local current = state.captureAppearancePageContext()
    -- Search text is committed only by Search/Enter. Typing must not cancel a
    -- valid in-flight page for the last submitted query.
    current.search = state.search
    return state.appearancePageContextsEqual(context, current)
end

local function setPreviewToRestore(slotName)
    local serverState = state.server[slotName]
    local previewState = state.preview[slotName]

    previewState.mode = "restore"
    previewState.itemId = nil
    previewState.effectiveId = serverState.realItemId
end

local function setPreviewToHidden(slotName)
    local previewState = state.preview[slotName]

    previewState.mode = "hidden"
    previewState.itemId = nil
    previewState.effectiveId = 0
end

local function setPreviewToItem(slotName, itemId)
    local previewState = state.preview[slotName]
    local serverState = state.server[slotName]

    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then
        return
    end

    if serverState.realItemId and itemId == serverState.realItemId then
        setPreviewToRestore(slotName)
        return
    end

    previewState.mode = "item"
    previewState.itemId = itemId
    previewState.effectiveId = itemId
end

local updatePreviewModel
local schedulePostMutationModelRebind
local cancelPostMutationModelRebind
local previewModelItemQueries = {}

state.cancelPreviewModelItemQueries = function()
    for itemId, queryHandle in pairs(previewModelItemQueries) do
        if queryHandle and queryHandle.Cancel then
            queryHandle:Cancel()
        end
        previewModelItemQueries[itemId] = nil
    end
end

local function requestPreviewModelItemData(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 or previewModelItemQueries[itemId] or not ns.QueryItem then
        return
    end

    previewModelItemQueries[itemId] = true
    local queryHandle = ns.QueryItem(itemId, function(queriedItemId, success)
        queriedItemId = tonumber(queriedItemId) or itemId
        previewModelItemQueries[queriedItemId] = nil
        if success and updatePreviewModel and mainFrame:IsShown() then
            updatePreviewModel()
        end
    end)
    if queryHandle and previewModelItemQueries[itemId] then
        previewModelItemQueries[itemId] = queryHandle
    end
end

local function getPreviewModelItem(slotName, itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then
        return nil
    end

    local levelEligible = getItemPreviewLevelEligibility(itemId)
    if levelEligible ~= true then
        if levelEligible == nil then
            requestPreviewModelItemData(itemId)
        end
        return nil
    end

    local equipSlot = WEAPON_EQUIPMENT_SLOT_BY_NAME[slotName]
    local enchantId = equipSlot and tonumber(state.weaponEnchantPreview[equipSlot]) or 0
    local explicitNoEnchant = equipSlot and state.weaponEnchantExplicitNoPreview[equipSlot] == true
    local previewEnchantId = enchantId and enchantId > 0 and enchantId or (explicitNoEnchant and 0 or nil)
    if previewEnchantId ~= nil then
        -- Wrath's DressUpModel needs the complete item hyperlink to carry the
        -- permanent-enchant field into the rendered weapon visual.  Explicit
        -- zero is equally important: it prevents the model from inheriting an
        -- equipped weapon's real glow while previewing No Enchantment.
        local itemLink = safeLink(itemId)
        if type(itemLink) == "string" then
            local previewLink, replacements = itemLink:gsub(
                "(item:%d+):%-?%d+",
                "%1:"..previewEnchantId,
                1
            )
            if replacements == 1 then
                return previewLink
            end
        end

        -- Custom items are not guaranteed to be cached when server state first
        -- arrives. Deduplicate the probe and re-dress as soon as the complete
        -- link becomes available, otherwise the weapon could keep its bare ID
        -- appearance until some unrelated UI refresh.
        requestPreviewModelItemData(itemId)
        return nil
    end
    return itemId
end

updatePreviewModel = function()
    if not mainFrame:IsShown() then
        return
    end

    local hasPreviewData = false
    for _, info in ipairs(SLOT_DATA) do
        if state.preview[info.name].effectiveId ~= nil then
            hasPreviewData = true
            break
        end
    end

    if not hasPreviewData and not state.synced then
        return
    end

    mainFrame.dressingRoom:SetUnit("player")
    mainFrame.dressingRoom:Undress()

    for _, info in ipairs(SLOT_DATA) do
        local itemId = state.preview[info.name].effectiveId
        if itemId and itemId > 0 then
            local previewItem = getPreviewModelItem(info.name, itemId)
            if previewItem then
                mainFrame.dressingRoom:TryOn(previewItem)
            end
        end
    end

    -- DressUpModel can visually favor another equipped weapon slot unless
    -- the browsed weapon (or active enchant target) is tried on again last.
    local favoredWeaponSlot = state.enchantingEquipSlot and WEAPON_NAME_BY_EQUIPMENT_SLOT[state.enchantingEquipSlot] or state.currentSlot
    if WEAPON_SLOT[favoredWeaponSlot] then
        local selectedItemId = state.preview[favoredWeaponSlot].effectiveId
        if selectedItemId and selectedItemId > 0 then
            local previewItem = getPreviewModelItem(favoredWeaponSlot, selectedItemId)
            if previewItem then
                mainFrame.dressingRoom:TryOn(previewItem)
            end
        end
    end

    if mainFrame.dressingRoom.shadowformEnabled then
        mainFrame.dressingRoom:EnableShadowform()
    end
end

if mainFrame.tabs and mainFrame.tabs.settings then
    mainFrame.tabs.settings:HookScript("OnShow", function()
        updatePreviewModel()
    end)
end

local function saveDressingRoomView()
    local x, y, z = mainFrame.dressingRoom:GetPosition()

    state.previousView = {
        x = tonumber(x) or 0,
        y = tonumber(y) or 0,
        z = tonumber(z) or 0,
        facing = tonumber(mainFrame.dressingRoom:GetFacing()) or 0,
    }
end

local transmogDressingRoomStatic = false
local modelControlVisibility = {}

local function setTransmogDressingRoomStatic(static)
    if transmogDressingRoomStatic == static then
        return
    end

    local dressingRoom = mainFrame.dressingRoom
    transmogDressingRoomStatic = static

    if static then
        if dressingRoom.StopCameraMotion then
            dressingRoom:StopCameraMotion()
        end
        -- Keep the opening camera predictable, but retain the normal
        -- left-click-and-drag mannequin rotation in Transmogrify mode.
        dressingRoom:EnableDragRotation(true)
        dressingRoom:EnableMouseWheel(false)
        -- Keep the compact camera controls visible in Transmogrify mode.  Wheel
        -- zoom remains disabled here so the reference framing stays intact.
        return
    end

    dressingRoom:EnableDragRotation(true)
    dressingRoom:EnableMouseWheel(true)
    for index, control in ipairs(mainFrame.modelControls or {}) do
        modelControlVisibility[index] = nil
    end
end

local function setStaticTransmogModelView(model)
    model:SetPosition(0, 0, 0)
    model:SetFacing(0)
end

local function setTransmogDressingRoomView()
    setStaticTransmogModelView(mainFrame.dressingRoom)
end

local function restoreDressingRoomView()
    local view = state.previousView
    if not view then
        return
    end

    mainFrame.dressingRoom:SetPosition(view.x or 0, view.y or 0, view.z or 0)
    mainFrame.dressingRoom:SetFacing(view.facing or 0)
end

local function showListMessage(text)
    transmogTab.messageText:SetText(text or "")
    transmogTab.messageText:Show()
    transmogTab.list:Hide()

    for _, dressingRoom in ipairs(transmogTab.list.dressingRooms) do
        dressingRoom:OnUpdateModel(nil)
        dressingRoom:ClearModel()
        dressingRoom:Hide()
    end
end

state.isPreviewMutationLocked = function()
    return state.applyingAppearanceSet or state.applyingUnlockedItemSet
end

local function updateActionButtons()
    local hasDirty = getDirtyCount() > 0
    local hasApplied = hasAppliedTransmogs()
    local serverState = state.server[state.currentSlot]
    local previewState = state.preview[state.currentSlot]
    local pendingCost = getDisplayedCost()
    local canAfford = pendingCost <= (tonumber(state.money) or 0)
    local canAffordRestoreAll = state.getRestoreAllCost() <= (tonumber(state.money) or 0)
    local mutationLocked = state.isPreviewMutationLocked()
    if transmogTab.enchantPicker and transmogTab.enchantPicker.buttons then
        for _, button in ipairs(transmogTab.enchantPicker.buttons) do
            if button.option then
                if mutationLocked then button:Disable() else button:Enable() end
            end
        end
    end
    local canApply = state.enabled
        and isServerStateReady()
        and hasDirty
        and canAfford
        and not mutationLocked
        and not state.randomizePending

    if updateCostDisplay then
        updateCostDisplay()
    end

    local equippedIcon = serverState and tonumber(serverState.realItemId) and GetItemIcon(tonumber(serverState.realItemId)) or nil
    if transmogTab.buttonApply and transmogTab.buttonApply.leadingIcon then
        transmogTab.buttonApply.leadingIcon:SetTexture(equippedIcon or "Interface\\Icons\\INV_Chest_Chain_05")
    end
    if transmogTab.buttonRestore and transmogTab.buttonRestore.leadingIcon then
        transmogTab.buttonRestore.leadingIcon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque")
    end

    local sidebar = transmogTab.sidebar
    if sidebar and sidebar.buttonNew then
        sidebar.buttonNew:SetText("New Outfit")
        if isServerStateReady() and not mutationLocked then sidebar.buttonNew:Enable() else sidebar.buttonNew:Disable() end
    end
    if sidebar and sidebar.buttonSave then
        if isServerStateReady() and not mutationLocked then sidebar.buttonSave:Enable() else sidebar.buttonSave:Disable() end
    end
    if sidebar and sidebar.currentGear then
        if state.enabled and state.synced and not mutationLocked then sidebar.currentGear:Enable() else sidebar.currentGear:Disable() end
    end

    transmogTab.buttonApply:SetText("Show Equipped Gear")
    if ns.Theme then ns.Theme.SetSelected(transmogTab.buttonApply, state.showEquippedGear) end
    transmogTab.buttonHide:SetText(previewState and previewState.mode == "hidden" and "Show" or "Hide")

    if canApply then transmogTab.buttonApplyAll:Enable() else transmogTab.buttonApplyAll:Disable() end
    if state.enabled and hasDirty and not mutationLocked then
        transmogTab.buttonRevert:Enable()
    else
        transmogTab.buttonRevert:Disable()
    end
    if state.enabled and isServerStateReady() and hasApplied and canAffordRestoreAll and not mutationLocked then
        transmogTab.buttonRevertAll:Enable()
    else
        transmogTab.buttonRevertAll:Disable()
    end

    setModelIconButtonEnabled(
        transmogTab.buttonRandomize,
        state.enabled and isServerStateReady() and not mutationLocked
            and not state.randomizePending and not state.isRandomizeCoolingDown()
            and not state.enchantingEquipSlot
    )
    setModelIconButtonEnabled(
        transmogTab.buttonRandomUndo,
        state.randomizeSnapshot and not mutationLocked and not state.randomizePending
    )

    if state.enchantingEquipSlot then
        transmogTab.buttonRestore:SetText("No Enchantment")
        transmogTab.buttonHide:Disable()

        if not state.enabled then
            transmogTab.buttonApply:Disable()
            transmogTab.buttonRestore:Disable()
            transmogTab.buttonPrev:Disable()
            transmogTab.buttonNext:Disable()
            return
        end

        if state.synced then transmogTab.buttonApply:Enable() else transmogTab.buttonApply:Disable() end
        if not mutationLocked and ((tonumber(state.weaponEnchantPreview[state.enchantingEquipSlot]) or 0) > 0
            or state.weaponEnchantExplicitNoPreview[state.enchantingEquipSlot] ~= true) then
            transmogTab.buttonRestore:Enable()
        else
            transmogTab.buttonRestore:Disable()
        end
        if state.enchantPage > 1 then transmogTab.buttonPrev:Enable() else transmogTab.buttonPrev:Disable() end
        if state.enchantHasMorePages then transmogTab.buttonNext:Enable() else transmogTab.buttonNext:Disable() end
        return
    end

    -- Match the reference action row. Unassigned restores the current slot;
    -- this distinct toggle controls whether candidate models retain the
    -- player's equipped gear for context.
    transmogTab.buttonRestore:SetText("Unassigned")

    if not state.enabled then
        transmogTab.buttonApply:Disable()
        transmogTab.buttonRestore:Disable()
        transmogTab.buttonHide:Disable()
        transmogTab.buttonPrev:Disable()
        transmogTab.buttonNext:Disable()
        return
    end

    if state.synced then transmogTab.buttonApply:Enable() else transmogTab.buttonApply:Disable() end

    if not mutationLocked and (serverState.itemId ~= nil or previewState.mode ~= "restore") then
        transmogTab.buttonRestore:Enable()
    else
        transmogTab.buttonRestore:Disable()
    end

    if not mutationLocked and (slotHasRestorableAppearance(state.currentSlot)
        or serverState.itemId ~= nil
        or previewState.mode ~= "restore") then
        transmogTab.buttonHide:Enable()
    else
        transmogTab.buttonHide:Disable()
    end

    local pageSize = getCurrentSlotPageSize(state.currentSlot)
    local pageCount = TransmogPaging.PageCount(state.totalItemCount, pageSize)
    local displayPage = math.min(
        TransmogPaging.DisplayPage(state.appearancePager, state.currentPage),
        pageCount
    )
    if displayPage > 1 then
        transmogTab.buttonPrev:Enable()
    else
        transmogTab.buttonPrev:Disable()
    end

    if displayPage < pageCount then
        transmogTab.buttonNext:Enable()
    else
        transmogTab.buttonNext:Disable()
    end
end

local function cancelPendingRandomize()
    if not state.randomizePending then return false end
    state.randomizePending = false
    state.randomRequestToken = state.randomRequestToken + 1
    state.randomRequestStartedAt = 0
    state.randomizeSnapshot = nil
    updateActionButtons()
    return true
end

local refreshSlotButton
local refreshWeaponEnchantButtons
local showWeaponEnchantPicker
local hideWeaponEnchantPicker
local refreshWeaponEnchantPicker

local pendingSlotButtonRefreshes = {}
local slotButtonRefreshFrame = CreateFrame("Frame")
local function slotButtonRefreshFrame_OnUpdate(self)
    self:SetScript("OnUpdate", nil)

    local queuedRefreshes = pendingSlotButtonRefreshes
    pendingSlotButtonRefreshes = {}

    for slotName, itemId in pairs(queuedRefreshes) do
        local previewState = state.preview[slotName]
        if previewState and previewState.effectiveId == itemId then
            refreshSlotButton(slotName)
        end
    end
end

local function queueSlotButtonRefresh(slotName, itemId)
    pendingSlotButtonRefreshes[slotName] = itemId
    if slotButtonRefreshFrame:GetScript("OnUpdate") == nil then
        slotButtonRefreshFrame:SetScript("OnUpdate", slotButtonRefreshFrame_OnUpdate)
    end
end

state.cancelSlotButtonIconQuery = function(button)
    if not button then
        return
    end

    local queryHandle = button.appearanceIconQueryHandle
    if queryHandle and queryHandle.Cancel then
        queryHandle:Cancel()
    end
    button.appearanceIconQueryHandle = nil
    button.appearanceIconQueryItemId = nil
end

state.cancelPendingSlotButtonIconQueries = function()
    for _, info in ipairs(SLOT_DATA) do
        state.cancelSlotButtonIconQuery(state.slotButtons[info.name])
    end
end

refreshSlotButton = function(slotName)
    local button = state.slotButtons[slotName]
    if not button then
        return
    end

    local previewState = state.preview[slotName]
    local itemId = previewState.effectiveId
    local itemLink
    local texture
    local levelEligible = false
    if itemId and itemId > 0 then
        levelEligible = getItemPreviewLevelEligibility(itemId)
    end
    local displayedItemId = levelEligible == true and itemId or nil
    if displayedItemId then
        local itemName
        local itemRarity
        local itemLevel
        local itemMinLevel
        local itemType
        local itemSubType
        local itemStackCount
        local itemEquipLoc
        itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, texture = GetItemInfo(displayedItemId)
    end
    local icon = displayedItemId and (GetItemIcon(displayedItemId) or texture) or nil

    if itemId and itemId > 0 and (levelEligible == nil or (displayedItemId and not icon and not itemLink)) then
        local samePendingQuery = button.appearanceIconQueryItemId == itemId
            and button.appearanceIconQueryHandle
            and button.appearanceIconQueryHandle.active
        if not samePendingQuery then
            state.cancelSlotButtonIconQuery(button)
            button.appearanceIconQueryItemId = itemId

            local queryHandle
            queryHandle = ns.QueryItem(itemId, function(queriedItemId, success)
                if button.appearanceIconQueryHandle == queryHandle then
                    button.appearanceIconQueryHandle = nil
                end
                if button.appearanceIconQueryItemId == queriedItemId then
                    button.appearanceIconQueryItemId = nil
                end
                if success and previewState.effectiveId == queriedItemId then
                    queueSlotButtonRefresh(slotName, queriedItemId)
                end
            end)

            if button.appearanceIconQueryItemId == itemId then
                button.appearanceIconQueryHandle = queryHandle
            end
        end
    else
        state.cancelSlotButtonIconQuery(button)
    end

    -- Keep a visible slot glyph in the inherited icon region whenever an item
    -- is empty, hidden, uncached, or fails to load.  A BACKGROUND texture is
    -- covered by the themed item-button backdrop.
    SetItemButtonTexture(button, icon or button.slotFallbackTexture or getSlotPlaceholderTexture(slotName))
    if icon then
        button.hiddenOverlay:Hide()
    elseif previewState.effectiveId == 0 then
        button.hiddenOverlay:Show()
    else
        button.hiddenOverlay:Hide()
    end

    local serverState = state.server[slotName]
    local hasEquippedItem = serverState and (tonumber(serverState.realItemId) or 0) > 0
    local iconTexture = _G[button:GetName().."IconTexture"]
    if iconTexture then
        if iconTexture.SetDesaturated then iconTexture:SetDesaturated(not hasEquippedItem) end
        iconTexture:SetVertexColor(hasEquippedItem and 1 or 0.62, hasEquippedItem and 1 or 0.62, hasEquippedItem and 1 or 0.62)
    end
    if hasEquippedItem then
        button:Enable()
        button.unavailableShade:Hide()
    else
        button:Disable()
        button.unavailableShade:Show()
        button.hiddenOverlay:Hide()
    end

    local showOutline = isSlotDirty(slotName) or state.currentSlot == slotName
    if ns.Theme and ns.Theme.SetInsetBorderColor then
        ns.Theme.SetInsetBorderColor(button, showOutline and "magenta" or "bronzeDim", showOutline and 0.96 or 0.72)
    end

    local appliedItemId = serverState and tonumber(serverState.itemId) or 0
    local hasVisibleAppliedAppearance = appliedItemId > 0
        and getItemPreviewLevelEligibility(appliedItemId) == true
    if button.appliedCheck and hasEquippedItem and not isSlotDirty(slotName) and hasVisibleAppliedAppearance then
        button.appliedCheck:Show()
    elseif button.appliedCheck then
        button.appliedCheck:Hide()
    end
end

local function refreshAllSlotButtons()
    for _, info in ipairs(SLOT_DATA) do
        refreshSlotButton(info.name)
    end
end

local updatePageText

local function selectSlot(slotName)
    if not SLOT_ID_BY_NAME[slotName] then
        return
    end

    state.currentSlot = slotName
    if hideWeaponEnchantPicker then
        hideWeaponEnchantPicker()
    end
    if transmogTab.searchLabel then
        transmogTab.searchLabel:SetText(slotName)
    end
    state.refreshWeaponFilterButton()
    if trim(transmogTab.searchBox:GetText()) == "" then
        state.currentPage = state.getWeaponFilterKey(slotName) == "all" and (tonumber(state.slotPages[slotName]) or 1) or 1
        if state.currentPage < 1 then
            state.currentPage = 1
        end
    end

    for _, info in ipairs(SLOT_DATA) do
        local button = state.slotButtons[info.name]
        if button then
            button:UnlockHighlight()
            if ns.Theme then ns.Theme.SetSelected(button, false) end
        end
    end

    refreshAllSlotButtons()
    updatePageText()
    updateActionButtons()
end

updatePageText = function()
    if state.enchantingEquipSlot then
        local pageCount = math.max(1, math.ceil(#WEAPON_ENCHANT_OPTIONS / 20))
        transmogTab.pageText:SetText(("Page %d / %d"):format(state.enchantPage, pageCount))
    else
        local pageSize = getCurrentSlotPageSize(state.currentSlot)
        local pageCount = TransmogPaging.PageCount(state.totalItemCount, pageSize)
        local displayPage = math.min(
            TransmogPaging.DisplayPage(state.appearancePager, state.currentPage),
            pageCount
        )
        transmogTab.pageText:SetText(("Page %d / %d"):format(displayPage, pageCount))
    end
end

local requestCurrentSlotItems
local requestCurrentSlotItemPage
local loadCurrentSlotItems
local requestItemSetCatalog
local rebuildSetLists
local rebuildSidebarSets
local updateSetPreview
local updateSetButtons

local function invalidateItemSetCatalog()
    state.itemSetCatalogDirty = true
    state.itemSetCatalogDirtyAt = GetTime and GetTime() or 0
    state.itemSetDetailsById = {}
    state.itemSetDetailRequests = {}
    state.itemSetDetailFailures = {}
end

local function canHandlePageNavigation()
    return state.enabled
        and state.hasServerSnapshot
        and state.viewMode == "items"
        and isTransmogTabVisible()
        and not transmogTab.searchBox:HasFocus()
end

local function changePage(direction)
    if not canHandlePageNavigation() then
        return false
    end

    direction = tonumber(direction)
    if direction == nil or direction == 0 then
        return false
    end

    if state.enchantingEquipSlot then
        local pageCount = math.max(1, math.ceil(#WEAPON_ENCHANT_OPTIONS / 20))
        local nextPage = state.enchantPage + (direction < 0 and -1 or 1)
        if nextPage < 1 or nextPage > pageCount then
            return false
        end
        state.enchantPage = nextPage
        PlaySound("gsTitleOptionOK")
        if refreshWeaponEnchantPicker then refreshWeaponEnchantPicker() end
        return true
    end

    local context = state.appearancePageContext
    if not context or not state.isAppearancePageContextCurrent(context) then
        return false
    end

    local queued = TransmogPaging.Queue(
        state.appearancePager,
        state.appearancePageGeneration,
        state.currentPage,
        state.totalItemCount,
        context.pageSize,
        direction,
        state.getAppearancePageTime()
    )
    if not queued then
        return false
    end
    PlaySound("gsTitleOptionOK")
    updatePageText()
    updateActionButtons()
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    return true
end

local function handlePageScroll(_, delta)
    if delta == nil or delta == 0 then
        return false
    end

    local setsFrame = transmogTab.setsFrame
    if state.viewMode == "sets" and isTransmogTabVisible()
        and setsFrame and setsFrame:IsVisible() then
        local scrollFrame = setsFrame.listScroll
        local scrollChild = setsFrame.list
        if not scrollFrame or not scrollChild then
            return false
        end

        local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
        if maxScroll <= 0 then
            scrollFrame:SetVerticalScroll(0)
            return false
        end

        local currentScroll = scrollFrame:GetVerticalScroll() or 0
        local nextScroll = currentScroll - (delta * SETS_SCROLL_STEP)
        if nextScroll < 0 then
            nextScroll = 0
        elseif nextScroll > maxScroll then
            nextScroll = maxScroll
        end

        if nextScroll == currentScroll then
            return false
        end

        scrollFrame:SetVerticalScroll(nextScroll)
        return true
    end

    if delta > 0 then
        return changePage(-1)
    end

    return changePage(1)
end

local function updateListSelection()
    local previewState = state.preview[state.currentSlot]
    if previewState.mode == "item" and previewState.itemId then
        local displayedItemId = getDisplayedItemIdForAppearance(state.currentSlot, previewState.itemId, transmogTab.list.itemIds)
        transmogTab.list:SelectByItemId(displayedItemId or previewState.itemId)
    else
        transmogTab.list.selectedItemId = nil
        for _, dressingRoom in ipairs(transmogTab.list.dressingRooms) do
            if dressingRoom.SetAppearanceSelected then
                dressingRoom:SetAppearanceSelected(false)
            else
                dressingRoom:SetBackdropBorderColor(0.31, 0.205, 0.030, 1)
            end
        end
    end
end

local function updateCandidateList(itemIds)
    itemIds = dedupeItemIdsByAppearance(state.currentSlot, itemIds or {})

    if #itemIds == 0 then
        local message
        if state.search ~= "" and state.getWeaponFilterKey(state.currentSlot) ~= "all" then
            message = "No unlocked appearances match this search and weapon type."
        elseif state.search ~= "" then
            message = "No unlocked appearances match this search."
        elseif state.getWeaponFilterKey(state.currentSlot) ~= "all" then
            message = "No unlocked appearances match this weapon type."
        else
            message = "No unlocked appearances for this slot yet."
        end
        showListMessage(message)
        updateListSelection()
        updateActionButtons()
        return
    end

    local width, height, x, y, z, facing, sequence = getListPreviewSetup(state.currentSlot)

    transmogTab.messageText:Hide()
    local listWasShown = transmogTab.list:IsShown()
    transmogTab.list:SetItems(itemIds)
    local listSlot = state.currentSlot
    transmogTab.list.getItemSetup = function(itemId)
        return getListPreviewSetup(listSlot, itemId)
    end
    transmogTab.list:SetupModel(width, height, x, y, z, facing, sequence)
    transmogTab.list:SetPage(1)

    -- For hand-weapon slots, skip Undress() inside queryItemHandler so the
    -- player's real equipped off-hand stays on the model and WoW doesn't
    -- auto-mirror a 1H weapon into both hand attachment points.
    transmogTab.list.skipUndress = state.showEquippedGear
        or state.currentSlot == "Main Hand"
        or state.currentSlot == "Off-hand"

    if listWasShown then
        transmogTab.list:Update()
    else
        -- The list's OnShow performs the first update after all new state has
        -- been installed, avoiding a stale-page query/cancel cycle.
        transmogTab.list:Show()
    end
    updateListSelection()
    updateActionButtons()
end

local function ensureServerSnapshotForItemList()
    if state.hasServerSnapshot then
        return true
    end

    -- Before the first V2 snapshot, nil means unknown rather than unequipped.
    showListMessage(state.syncFailureMessage or "Loading transmog state...")
    updateActionButtons()
    return false
end

state.cancelPageLookupActivity = function()
    if state.pageLookupRequestPending then
        state.pageLookupToken = state.pageLookupToken + 1
    end
    state.pageLookupRequestPending = false
    state.pageLookupRequestStartedAt = 0
    state.pageLookupRequestRetryCount = 0
    state.pageLookupRateLimitRetryAt = 0
    state.pageLookupRateLimitRetryCount = 0
    state.pageLookupSlot = nil
    state.pageLookupAnchor = nil
    state.pageLookupFilter = nil
    state.pageLookupPageSize = nil
end

state.newAppearancePageRequest = function(context, page)
    return {
        generation = state.appearancePageGeneration,
        slotName = context.slotName,
        slotId = context.slotId,
        search = context.search,
        page = math.max(1, math.floor(tonumber(page) or 1)),
        pageSize = context.pageSize,
        weaponFilter = context.weaponFilter,
        token = 0,
    }
end

state.sendAppearancePageRequest = function(request, isRetry)
    if not request or request.generation ~= state.appearancePageGeneration then
        return false
    end

    if not isRetry then
        state.appearancePageRequestRetryCount = 0
    end
    state.requestToken = state.requestToken + 1
    request.token = state.requestToken
    state.appearancePageRequest = request
    state.appearancePageRequestPending = true
    state.appearancePageRequestStartedAt = state.getAppearancePageTime()
    state.search = request.search

    state.cancelPageLookupActivity()

    updatePageText()
    showListMessage("Loading appearances...")
    updateActionButtons()
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end

    if request.search ~= "" then
        AIO.Handle(
            "Transmog",
            "SetSearchCurrentSlotItemIds",
            request.slotId,
            request.page,
            request.search,
            request.pageSize,
            request.token,
            request.weaponFilter
        )
    else
        AIO.Handle(
            "Transmog",
            "SetCurrentSlotItemIds",
            request.slotId,
            request.page,
            request.pageSize,
            request.token,
            request.weaponFilter
        )
    end
    return true
end

state.cancelAppearancePageActivity = function()
    state.appearancePageGeneration = state.appearancePageGeneration + 1
    TransmogPaging.Cancel(state.appearancePager, state.appearancePageGeneration)
    if state.appearancePageRequestPending then
        state.requestToken = state.requestToken + 1
    end
    state.appearancePageRequest = nil
    state.appearancePageRequestPending = false
    state.appearancePageRequestStartedAt = 0
    state.appearancePageRequestRetryCount = 0
end

requestCurrentSlotItems = function(resetPage, isRetry)
    if not state.enabled or state.enchantingEquipSlot then
        return false
    end

    if not ensureServerSnapshotForItemList() then
        return false
    end

    local now = state.getAppearancePageTime()
    if isRetry then
        local request = state.appearancePageRequest
        if not state.appearancePageRequestPending or not request
            or not TransmogPaging.RepeatActive(
                state.appearancePager,
                request.generation,
                now
            ) then
            return false
        end
        return state.sendAppearancePageRequest(request, true)
    end

    local context = state.captureAppearancePageContext()
    local contextChanged = not state.appearancePageContextsEqual(state.appearancePageContext, context)
    state.appearancePageGeneration = state.appearancePageGeneration + 1
    state.appearancePageContext = context
    if resetPage then
        state.currentPage = 1
    end
    if contextChanged then
        state.hasMorePages = false
        state.totalItemCount = 0
    end

    local page = TransmogPaging.BeginDirect(
        state.appearancePager,
        state.appearancePageGeneration,
        state.currentPage,
        now
    )
    return state.sendAppearancePageRequest(state.newAppearancePageRequest(context, page), false)
end

state.dispatchQueuedAppearancePage = function(now)
    if not state.appearancePageRequestPending
        and not TransmogPaging.HasScheduledRequest(state.appearancePager) then
        return false
    end

    local context = state.appearancePageContext
    if not state.enabled or state.enchantingEquipSlot or state.viewMode ~= "items" or not isTransmogTabVisible()
        or not context or not state.isAppearancePageContextCurrent(context) then
        state.cancelAppearancePageActivity()
        return false
    end
    if not TransmogPaging.IsReady(
        state.appearancePager,
        state.appearancePageGeneration,
        now,
        state.appearancePageRequestPending
    ) then
        return false
    end

    local page = TransmogPaging.BeginQueued(
        state.appearancePager,
        state.appearancePageGeneration,
        now
    )
    if not page then
        return false
    end
    return state.sendAppearancePageRequest(state.newAppearancePageRequest(context, page), false)
end

requestCurrentSlotItemPage = function(slotName, itemId, isRetry)
    if not state.enabled or state.enchantingEquipSlot then
        return false
    end

    if not ensureServerSnapshotForItemList() then
        return false
    end

    local slotId = SLOT_ID_BY_NAME[slotName]
    itemId = tonumber(itemId) or 0
    if not slotId or itemId <= 0 then
        state.pageLookupRequestPending = false
        state.pageLookupRequestStartedAt = 0
        state.pageLookupRequestRetryCount = 0
        state.pageLookupRateLimitRetryAt = 0
        state.pageLookupRateLimitRetryCount = 0
        state.pageLookupPageSize = nil
        state.currentPage = 1
        updatePageText()
        requestCurrentSlotItems(false)
        return false
    end

    if not isRetry then
        state.cancelAppearancePageActivity()
        -- Locator requests are the unfiltered path used after clearing Search.
        state.search = ""
        state.pageLookupRequestRetryCount = 0
        state.pageLookupRateLimitRetryCount = 0
        state.pageLookupPageSize = getCurrentSlotPageSize(slotName)
    end
    state.pageLookupToken = state.pageLookupToken + 1
    if not isRetry then
        state.pageLookupSlot = slotName
        state.pageLookupAnchor = itemId
        state.pageLookupFilter = state.getWeaponFilterKey(slotName)
    end
    state.pageLookupRequestPending = true
    state.pageLookupRequestStartedAt = state.getAppearancePageTime()
    state.pageLookupRateLimitRetryAt = 0
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    state.currentPage = 1
    state.hasMorePages = false
    state.totalItemCount = 0

    updatePageText()
    showListMessage("Locating current appearance...")
    updateActionButtons()

    AIO.Handle(
        "Transmog",
        "SetCurrentSlotItemPage",
        slotId,
        itemId,
        state.pageLookupPageSize or getCurrentSlotPageSize(slotName),
        state.pageLookupToken,
        state.pageLookupFilter
    )
    return true
end

loadCurrentSlotItems = function()
    if not state.enabled or state.enchantingEquipSlot then
        return
    end

    if not ensureServerSnapshotForItemList() then
        return
    end
    state.itemListInvalidatedBySyncFailure = false

    local currentServerState = state.server[state.currentSlot]
    if not currentServerState or (tonumber(currentServerState.realItemId) or 0) <= 0 then
        state.cancelAppearancePageActivity()
        state.cancelPageLookupActivity()
        state.currentPage = 1
        state.hasMorePages = false
        state.totalItemCount = 0
        transmogTab.list:SetItems({})
        updatePageText()
        showListMessage("No item is equipped in this slot.")
        updateActionButtons()
        return
    end

    local currentSearch = trim(transmogTab.searchBox:GetText())
    if currentSearch ~= "" then
        requestCurrentSlotItems(true)
        return
    end

    if state.getWeaponFilterKey(state.currentSlot) ~= "all" then
        requestCurrentSlotItems(true)
        return
    end

    local slotName = state.currentSlot
    local currentAnchor = getCurrentSlotPageAnchor(slotName)
    local rememberedPage = tonumber(state.slotPages[slotName])
    local rememberedAnchor = tonumber(state.slotPageAnchors[slotName]) or 0

    if rememberedPage and rememberedPage > 0 and rememberedAnchor == currentAnchor then
        state.currentPage = rememberedPage
        updatePageText()
        requestCurrentSlotItems(false)
        return
    end

    if currentAnchor and currentAnchor > 0 then
        requestCurrentSlotItemPage(slotName, currentAnchor)
    else
        state.currentPage = rememberedPage and rememberedPage > 0 and rememberedPage or 1
        updatePageText()
        requestCurrentSlotItems(false)
    end
end

state.normalizeItemSetCatalogSearch = function(value)
    return string.lower(trim(tostring(value or "")))
end

requestItemSetCatalog = function(page, search)
    if not state.enabled or not isCatalogSetViewVisible() then
        return false
    end

    page = math.max(1, math.floor(tonumber(page) or 1))
    search = state.normalizeItemSetCatalogSearch(search == nil
        and state.setSearchBySource[SET_SOURCE_CATALOG]
        or search)
    if state.itemSetCatalogRequestPending then
        if page ~= 1 or (search == state.itemSetCatalogRequestSearch and not state.itemSetCatalogLevelChanged) then
            return false
        end
        -- A debounced search or a level change supersedes the old page-one
        -- request. The server may still finish it, but the incremented token
        -- makes its response a harmless no-op instead of blocking the newest
        -- eligibility-filtered query.
        state.itemSetCatalogRequestToken = state.itemSetCatalogRequestToken + 1
        state.itemSetCatalogRequestPending = false
        state.itemSetCatalogRequestStartedAt = 0
    end
    if page > 1 then
        if not state.itemSetCatalogLoaded
            or not state.itemSetCatalogHasMore
            or state.itemSetCatalogSearch ~= search
            or page ~= state.itemSetCatalogPage + 1 then
            return false
        end
    end

    state.itemSetCatalogRequestPending = true
    state.itemSetCatalogRequestToken = state.itemSetCatalogRequestToken + 1
    state.itemSetCatalogRequestStartedAt = GetTime and GetTime() or 0
    state.itemSetCatalogRequestPage = page
    state.itemSetCatalogRequestSearch = search
    if page == 1 then
        state.resetSetListScroll = true
    end
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    updateSetButtons()

    if state.viewMode == "sets" and state.setSource == SET_SOURCE_CATALOG then
        if rebuildSetLists then rebuildSetLists(true) end
        if page == 1 and #state.itemSetCatalog == 0 then
            local setsFrame = transmogTab.setsFrame
            if setsFrame then
                setsFrame.previewTitle:SetText("Loading Item Sets")
                setsFrame.previewInfo:SetText("Fetching unlocked account item sets...")
            end
        end
    end

    AIO.Handle(
        "Transmog",
        "GetUnlockedItemSets",
        state.itemSetCatalogRequestToken,
        page,
        state.itemSetCatalogPageSize,
        search
    )
    return true
end

local function shouldRefreshItemSetCatalog(force)
    if not state.enabled then
        return false
    end

    if state.itemSetCatalogRequestPending and not (force and state.itemSetCatalogLevelChanged) then
        return false
    end

    if not isCatalogSetViewVisible() then
        return false
    end

    if force then
        return true
    end

    if not state.itemSetCatalogLoaded then
        return true
    end

    if state.itemSetCatalogSearch ~= state.normalizeItemSetCatalogSearch(state.setSearchBySource[SET_SOURCE_CATALOG]) then
        return true
    end

    if state.itemSetCatalogLevelChanged then
        return true
    end

    -- The account catalog is intentionally sticky for this session.  Even its
    -- compact index can be large, so an actual unlock only marks it stale;
    -- the user can refresh deliberately instead of paying that cost on tabs,
    -- bag moves, or equipment changes.
    return false
end

local function refreshItemSetCatalogIfNeeded(force)
    if not shouldRefreshItemSetCatalog(force) then
        return false
    end

    requestItemSetCatalog(1)
    return true
end

state.requestNextItemSetCatalogPage = function()
    if state.setSource ~= SET_SOURCE_CATALOG
        or not state.itemSetCatalogLoaded
        or not state.itemSetCatalogHasMore
        or state.itemSetCatalogRequestPending then
        return false
    end

    return requestItemSetCatalog(
        state.itemSetCatalogPage + 1,
        state.setSearchBySource[SET_SOURCE_CATALOG]
    )
end

state.markServerStateStale = function(cancelPendingRequest)
    state.synced = false
    state.weaponEnchantSynced = false
    state.costSynced = false
    state.costRequestPending = false
    if cancelPendingRequest and state.syncRequestPending then
        state.syncRequestToken = state.syncRequestToken + 1
        state.syncRequestPending = false
        state.syncRequestStartedAt = 0
        state.syncRequestRetryCount = 0
    end
end

local function requestServerState(isRetry)
    if not state.enabled then
        return false
    end

    if not isRetry then
        state.syncRequestRetryCount = 0
    end
    state.syncFailureMessage = nil
    state.syncRequestToken = state.syncRequestToken + 1
    if state.postMutationModelRebindPending then
        state.postMutationModelRebindRequestToken = state.syncRequestToken
    end
    state.syncRequestPending = true
    state.syncRequestStartedAt = GetTime and GetTime() or 0
    state.synced = false
    state.weaponEnchantSynced = false
    state.costSynced = false
    state.costRequestToken = state.syncRequestToken
    state.costRequestPending = true
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    AIO.Handle("Transmog", "GetTransmogStateV2", state.syncRequestToken)
    updateActionButtons()
    return true
end

local function requestPostMutationStateSync()
    state.postMutationModelRebindPending = true
    state.postMutationModelRebindRequestToken = 0
    if requestServerState() then
        return true
    end

    state.postMutationModelRebindPending = false
    state.postMutationModelRebindRequestToken = 0
    return false
end

local function scanInventoryForAppearances()
    if not state.enabled or state.scanRequestPending then
        return false
    end

    state.scanRequestToken = state.scanRequestToken + 1
    state.scanRequestPending = true
    state.scanRequestStartedAt = GetTime and GetTime() or 0
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    AIO.Handle("Transmog", "ScanInventoryUnlocks", state.scanRequestToken)

    return true
end

ns.ScanInventoryForAppearances = scanInventoryForAppearances

local function normalizeAppearanceSet(itemIds)
    local normalized = {}

    for index = 1, #SLOT_DATA do
        local itemId = type(itemIds) == "table" and tonumber(itemIds[index]) or nil
        local finite = itemId and itemId == itemId and itemId > -math.huge and itemId < math.huge
        if finite and itemId > 0 then
            normalized[index] = math.floor(itemId)
        elseif itemId == 0 then
            normalized[index] = 0
        else
            normalized[index] = -1
        end
    end

    return normalized
end

local function normalizeWeaponEnchantSet(weaponEnchants)
    if type(weaponEnchants) ~= "table" then
        return nil
    end

    local normalized = { explicitNo = {}, clear = {} }
    local explicitNoSlots = type(weaponEnchants.explicitNo) == "table" and weaponEnchants.explicitNo or nil
    local clearSlots = type(weaponEnchants.clear) == "table" and weaponEnchants.clear or nil
    for _, equipSlot in ipairs({15, 16, 17}) do
        local enchantId = tonumber(weaponEnchants[equipSlot] or weaponEnchants[tostring(equipSlot)]) or 0
        enchantId = math.floor(enchantId)
        normalized[equipSlot] = WEAPON_ENCHANT_OPTION_BY_ID[enchantId] and enchantId or 0
        normalized.explicitNo[equipSlot] = normalized[equipSlot] == 0
            and type(explicitNoSlots) == "table"
            and (explicitNoSlots[equipSlot] == true or explicitNoSlots[tostring(equipSlot)] == true
                or explicitNoSlots[equipSlot] == 1 or explicitNoSlots[tostring(equipSlot)] == 1)
        normalized.clear[equipSlot] = type(clearSlots) == "table"
            and (clearSlots[equipSlot] == true or clearSlots[tostring(equipSlot)] == true
                or clearSlots[equipSlot] == 1 or clearSlots[tostring(equipSlot)] == 1)
            or (normalized[equipSlot] == 0 and not normalized.explicitNo[equipSlot])
    end
    return normalized
end

local function applyAppearanceSetAsTransmog(itemIds, weaponEnchants)
    if not state.enabled then
        if state.disabledReason then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..state.disabledReason)
        end
        return false
    end

    if state.isPreviewMutationLocked() or not isServerStateReady() then
        return false
    end

    cancelPendingRandomize()
    state.mutationRequestToken = state.mutationRequestToken + 1
    state.mutationRequestStartedAt = GetTime and GetTime() or 0
    state.applyingAppearanceSet = true
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    updateActionButtons()
    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetButtons()
    end
    local normalizedWeaponEnchants = normalizeWeaponEnchantSet(weaponEnchants)
    AIO.Handle(
        "Transmog",
        "ApplyAppearanceSet",
        normalizeAppearanceSet(itemIds),
        normalizedWeaponEnchants,
        normalizedWeaponEnchants and normalizedWeaponEnchants.explicitNo or {},
        state.mutationRequestToken
    )
    return true
end

local function revertAllTransmogs()
    local restoreAll = {}
    for index in ipairs(SLOT_DATA) do
        restoreAll[index] = -1
    end

    return applyAppearanceSetAsTransmog(restoreAll, {
        [15] = 0, [16] = 0, [17] = 0,
        clear = { [15] = true, [16] = true, [17] = true },
    })
end

local function applyUnlockedCatalogSet(itemSetId)
    itemSetId = tonumber(itemSetId)
    if not state.enabled or not isServerStateReady()
        or state.isPreviewMutationLocked() or not itemSetId or itemSetId == 0 then
        return false
    end

    cancelPendingRandomize()
    state.mutationRequestToken = state.mutationRequestToken + 1
    state.mutationRequestStartedAt = GetTime and GetTime() or 0
    state.applyingUnlockedItemSet = true
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    updateActionButtons()
    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetButtons()
    end
    AIO.Handle("Transmog", "ApplyUnlockedItemSet", itemSetId, state.mutationRequestToken)
    return true
end

local function revertAllPreview()
    cancelPendingRandomize()
    state.randomizeSnapshot = nil
    copyAllServerToPreview()
    copyAllWeaponEnchantServerToPreview()
    refreshAllSlotButtons()
    if refreshWeaponEnchantButtons then
        refreshWeaponEnchantButtons()
    end
    if refreshWeaponEnchantPicker and state.enchantingEquipSlot then
        refreshWeaponEnchantPicker()
    end
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end

local function onSlotButtonEnter(self)
    local slotName = self.slotName
    local serverState = state.server[slotName]
    local previewState = state.preview[slotName]

    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(slotName)

    if serverState.realItemId then
        GameTooltip:AddLine("Original: "..(safeLink(serverState.realItemId) or ("item:"..serverState.realItemId)), 1, 1, 1)
    else
        GameTooltip:AddLine("Original: no item equipped", 0.75, 0.75, 0.75)
    end

    if serverState.itemId == 0 then
        GameTooltip:AddLine("Applied: hidden", 1, 0.3, 0.3)
    elseif serverState.itemId and serverState.itemId > 0 then
        GameTooltip:AddLine("Applied: "..getPreviewAppearanceLabel(serverState.itemId), 0.3, 1, 0.3)
    else
        GameTooltip:AddLine("Applied: original appearance", 0.3, 1, 0.3)
    end

    if isSlotDirty(slotName) then
        if previewState.mode == "hidden" then
            GameTooltip:AddLine("Preview: hidden", 1, 0.82, 0)
        elseif previewState.mode == "restore" then
            GameTooltip:AddLine("Preview: restore original appearance", 1, 0.82, 0)
        elseif previewState.itemId then
            GameTooltip:AddLine("Preview: "..getPreviewAppearanceLabel(previewState.itemId), 1, 0.82, 0)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to browse unlocked appearances.")
    if GetSettings and GetSettings().showShortcutsInTooltip then
        if isSlotDirty(slotName) then
            GameTooltip:AddLine("|cff00ff00Right Click:|r discard this pending transmog change.")
        elseif serverState.itemId ~= nil then
            GameTooltip:AddLine("|cff00ff00Right Click:|r mark this transmog for removal; click Apply to confirm.")
        end
    end
    GameTooltip:Show()
end

local function onSlotButtonLeave()
    GameTooltip:Hide()
end

local function onSlotButtonClick(self, mouseButton)
    local slotName = self.slotName

    if mouseButton == "RightButton" then
        local serverState = state.server[slotName]
        local hasPendingChange = isSlotDirty(slotName)
        local canPendOriginalAppearance = serverState and serverState.itemId ~= nil

        if state.isPreviewMutationLocked()
            or not serverState
            or (tonumber(serverState.realItemId) or 0) <= 0
            or not (hasPendingChange or canPendOriginalAppearance) then
            return
        end

        cancelPendingRandomize()
        PlaySound("gsTitleOptionOK")
        selectSlot(slotName)
        if hasPendingChange then
            copyServerToPreview(slotName)
        else
            setPreviewToRestore(slotName)
        end
        refreshSlotButton(slotName)
        updatePreviewModel()
        updateListSelection()
        updateActionButtons()
        loadCurrentSlotItems()
        return
    end

    PlaySound("gsTitleOptionOK")
    selectSlot(slotName)
    loadCurrentSlotItems()
end

local function onListItemEnter(self)
    local itemId = self:GetParent().itemId
    if not itemId then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:ClearLines()
    local link = safeLink(itemId)
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:AddLine("item:"..itemId)
    end

    if GetSettings and GetSettings().showShortcutsInTooltip then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Left Click:|r preview this appearance.")
        GameTooltip:AddLine("|cff00ff00Shift + Left Click:|r create an item link.")
        GameTooltip:AddLine("|cff00ff00Ctrl + Left Click:|r create a Wowhead URL.")
        GameTooltip:AddLine("|cffff8080Ctrl + Right Click:|r permanently remove this appearance.")
    end
    GameTooltip:Show()
end

local function onListItemLeave()
    GameTooltip:Hide()
end

local function requestPermanentAppearanceRemoval(slotName, itemId)
    local slotId = SLOT_ID_BY_NAME[slotName]
    itemId = tonumber(itemId)
    if not state.enabled or not slotId or not itemId or itemId <= 0 then
        return
    end

    AIO.Handle("Transmog", "DeleteUnlockedAppearance", slotId, itemId)
end

StaticPopupDialogs["APPEARANCE_BUDDY_REMOVE_APPEARANCE_CONFIRM"] = {
    text = "Permanently remove %s from your appearance collection?\n\nThis cannot be undone.",
    button1 = "Remove",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        data = data or self.data
        if type(data) == "table" then
            requestPermanentAppearanceRemoval(data.slotName, data.itemId)
        end
    end,
}

local function showPermanentAppearanceRemovalConfirmation(slotName, itemId)
    itemId = tonumber(itemId)
    if not SLOT_ID_BY_NAME[slotName] or not itemId or itemId <= 0 then
        return
    end

    local displayName = safeLink(itemId) or ("item:"..itemId)
    StaticPopup_Show("APPEARANCE_BUDDY_REMOVE_APPEARANCE_CONFIRM", displayName, nil, {
        slotName = slotName,
        itemId = itemId,
    })
end

local function onListItemClick(self, mouseButton)
    local itemId = self:GetParent().itemId
    if not itemId then
        return
    end

    if mouseButton == "RightButton" then
        if IsControlKeyDown() then
            showPermanentAppearanceRemovalConfirmation(state.currentSlot, itemId)
        end
        return
    end

    local serverState = state.server[state.currentSlot]
    if not serverState or (tonumber(serverState.realItemId) or 0) <= 0 then
        loadCurrentSlotItems()
        return
    end

    if IsShiftKeyDown() then
        local link = safeLink(itemId)
        if link then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..link.." ("..itemId..")")
        end
        return
    end

    if IsControlKeyDown() then
        ns.ShowWowheadURLDialog(itemId)
        return
    end

    if state.isPreviewMutationLocked() then
        return
    end

    cancelPendingRandomize()
    PlaySound("gsTitleOptionOK")

    setPreviewToItem(state.currentSlot, itemId)
    refreshSlotButton(state.currentSlot)
    updatePreviewModel()
    updateActionButtons()
    onListItemEnter(self)
end

-- Transmog slot buttons live on the dressing room (same positions as main slots).
-- They are children of transmogTab so they auto-show/hide with the tab.
for index, info in ipairs(SLOT_DATA) do
    local safeSlotName = info.name:gsub("[%s%-]", "")
    local button = CreateFrame("Button", (transmogTab:GetName() or addon.."Transmog").."Slot"..safeSlotName, transmogTab, "ItemButtonTemplate")
    button:SetSize(36, 36)
    button:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.slotName = info.name
    button:SetScript("OnClick", onSlotButtonClick)
    button:SetScript("OnEnter", onSlotButtonEnter)
    button:SetScript("OnLeave", onSlotButtonLeave)

    button.slotFallbackTexture = getSlotPlaceholderTexture(info.name)
    SetItemButtonTexture(button, button.slotFallbackTexture)
    if ns.Theme then ns.Theme.SkinItemButton(button) end

    button.appliedCheck = button:CreateTexture(nil, "OVERLAY")
    button.appliedCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    button.appliedCheck:SetSize(18, 18)
    button.appliedCheck:SetPoint("TOPRIGHT", 4, 4)
    button.appliedCheck:Hide()

    button.unavailableShade = button:CreateTexture(nil, "ARTWORK")
    button.unavailableShade:SetTexture("Interface\\Buttons\\WHITE8X8")
    button.unavailableShade:SetPoint("TOPLEFT", 4, -4)
    button.unavailableShade:SetPoint("BOTTOMRIGHT", -4, 4)
    button.unavailableShade:SetVertexColor(0.02, 0.02, 0.02, 0.28)
    button.unavailableShade:Hide()

    button.hiddenOverlay = button:CreateTexture(nil, "OVERLAY")
    button.hiddenOverlay:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    button.hiddenOverlay:SetSize(22, 22)
    button.hiddenOverlay:SetPoint("CENTER", 0, 0)
    button.hiddenOverlay:Hide()

    state.slotButtons[info.name] = button
end

-- Position transmog slot buttons on the dressing room, mirroring main slot layout.
do
    local dr = mainFrame.dressingRoom
    local sb = state.slotButtons
    sb["Head"]:SetPoint("TOPLEFT", dr, "TOPLEFT", 16, -103)
    sb["Shoulder"]:SetPoint("TOP", sb["Head"], "BOTTOM", 0, -4)
    sb["Back"]:SetPoint("TOP", sb["Shoulder"], "BOTTOM", 0, -4)
    sb["Chest"]:SetPoint("TOP", sb["Back"], "BOTTOM", 0, -4)
    sb["Shirt"]:SetPoint("TOP", sb["Chest"], "BOTTOM", 0, -4)
    sb["Tabard"]:SetPoint("TOP", sb["Shirt"], "BOTTOM", 0, -4)
    sb["Wrist"]:SetPoint("TOP", sb["Tabard"], "BOTTOM", 0, -4)
    sb["Hands"]:SetPoint("TOPRIGHT", dr, "TOPRIGHT", -8, -170)
    sb["Waist"]:SetPoint("TOP", sb["Hands"], "BOTTOM", 0, -4)
    sb["Legs"]:SetPoint("TOP", sb["Waist"], "BOTTOM", 0, -4)
    sb["Feet"]:SetPoint("TOP", sb["Legs"], "BOTTOM", 0, -4)
    -- Leave the weapon pair high enough for its smaller enchant children to
    -- sit below it without overlapping either the parent icon or frame edge.
    sb["Main Hand"]:SetPoint("BOTTOM", dr, "BOTTOM", -23, 28)
    sb["Off-hand"]:SetPoint("BOTTOM", dr, "BOTTOM", 23, 28)
    -- WotLK has a separate ranged equipment slot. Keep it accessible as the
    -- final compact entry in the right column without disturbing the reference
    -- weapon pair beneath the mannequin.
    sb["Ranged"]:SetPoint("TOP", sb["Feet"], "BOTTOM", 0, -4)
end

local function normalizeEnchantButtonTemplate(button)
    if not button or not button.GetName then return end
    local name = button:GetName()

    -- ItemButtonTemplate keeps fixed 36-64px regions even when its button is
    -- resized. Strip that inherited chrome so this child is truly 20px rather
    -- than painting another weapon-sized border around itself.
    local icon = name and _G[name.."IconTexture"]
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetTexture(nil)
        normal:Hide()
    end

    local function constrainTemplateTexture(texture, inset)
        if not texture then return end
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end

    constrainTemplateTexture(button.GetPushedTexture and button:GetPushedTexture(), 3)
    constrainTemplateTexture(button.GetDisabledTexture and button:GetDisabledTexture(), 3)
    constrainTemplateTexture(button.GetHighlightTexture and button:GetHighlightTexture(), 2)

    for _, suffix in ipairs({"Count", "Stock"}) do
        local region = name and _G[name..suffix]
        if region then region:Hide() end
    end
end

-- Small illusion controls sit directly under each visible weapon slot, like
-- the reference UI.  They select a visual-only weapon enchant; they do not
-- touch the actual item enchant or combat stats.
do
    for _, slotName in ipairs({"Main Hand", "Off-hand", "Ranged"}) do
        local equipSlot = WEAPON_EQUIPMENT_SLOT_BY_NAME[slotName]
        local button = CreateFrame("Button", transmogTabName.."WeaponEnchant"..equipSlot, transmogTab, "ItemButtonTemplate")
        button:SetSize(20, 20)
        button:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 4)
        button:RegisterForClicks("LeftButtonUp")
        button.equipSlot = equipSlot
        button.slotName = slotName
        button:SetPoint("TOP", state.slotButtons[slotName], "BOTTOM", 0, -3)
        if ns.Theme then ns.Theme.SkinItemButton(button) end
        normalizeEnchantButtonTemplate(button)

        button.connector = button:CreateTexture(nil, "BORDER")
        button.connector:SetTexture("Interface\\Buttons\\WHITE8X8")
        button.connector:SetPoint("BOTTOM", button, "TOP", 0, -2)
        button.connector:SetSize(1, 7)
        button.connector:SetVertexColor(0.31, 0.205, 0.030, 0.72)

        button.pendingGlow = button:CreateTexture(nil, "OVERLAY")
        button.pendingGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        button.pendingGlow:SetBlendMode("ADD")
        button.pendingGlow:SetPoint("CENTER", 0, 0)
        button.pendingGlow:SetSize(24, 24)
        button.pendingGlow:SetVertexColor(0.85, 0.18, 0.96)
        button.pendingGlow:Hide()

        button:SetScript("OnClick", function(self)
            if self:IsEnabled() and showWeaponEnchantPicker then
                PlaySound("gsTitleOptionOK")
                showWeaponEnchantPicker(self.equipSlot)
            end
        end)
        button:SetScript("OnEnter", function(self)
            local enchantId = tonumber(state.weaponEnchantPreview[self.equipSlot]) or 0
            local option = WEAPON_ENCHANT_OPTION_BY_ID[enchantId] or WEAPON_ENCHANT_OPTION_BY_ID[0]
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.slotName.." Enchant", 1, 0.82, 0)
            if self:IsEnabled() then
                GameTooltip:AddLine(option.name, 1, 1, 1)
                GameTooltip:AddLine("Click to choose a cosmetic weapon enchant.", 0.7, 0.7, 0.7, true)
            elseif self.slotName == "Ranged"
                and state.server[self.slotName]
                and (tonumber(state.server[self.slotName].realItemId) or 0) > 0 then
                GameTooltip:AddLine("Only wands can use a cosmetic weapon enchant.", 0.75, 0.75, 0.75, true)
            else
                GameTooltip:AddLine("No weapon equipped.", 0.75, 0.75, 0.75)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        state.weaponEnchantButtons[equipSlot] = button
    end
end

local function addLeadingButtonIcon(button, texturePath)
    button.leadingIconBorder = button:CreateTexture(nil, "ARTWORK")
    button.leadingIconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    button.leadingIconBorder:SetBlendMode("ADD")
    button.leadingIconBorder:SetPoint("LEFT", button, "LEFT", 5, 0)
    button.leadingIconBorder:SetSize(22, 22)
    button.leadingIconBorder:SetVertexColor(0.84, 0.66, 0.086, 0.82)

    button.leadingIcon = button:CreateTexture(nil, "ARTWORK")
    button.leadingIcon:SetPoint("CENTER", button.leadingIconBorder, "CENTER", 0, 0)
    button.leadingIcon:SetSize(14, 14)
    button.leadingIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.leadingIcon:SetTexture(texturePath)

    local label = button:GetFontString()
    if label then
        label:ClearAllPoints()
        label:SetFontObject(GameFontNormalSmall)
        label:SetPoint("LEFT", button, "LEFT", 28, 0)
        label:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        label:SetJustifyH("CENTER")
    end
end

local function captureRandomizeSnapshot()
    local snapshot = { preview = {}, weaponEnchants = {} }
    for _, info in ipairs(SLOT_DATA) do
        local previewState = state.preview[info.name]
        snapshot.preview[info.name] = {
            mode = previewState.mode,
            itemId = previewState.itemId,
            effectiveId = previewState.effectiveId,
        }
    end
    for _, equipSlot in ipairs({15, 16, 17}) do
        snapshot.weaponEnchants[equipSlot] = tonumber(state.weaponEnchantPreview[equipSlot]) or 0
        snapshot.weaponEnchants.explicitNo = snapshot.weaponEnchants.explicitNo or {}
        snapshot.weaponEnchants.explicitNo[equipSlot] = state.weaponEnchantExplicitNoPreview[equipSlot] == true
    end
    return snapshot
end

local function requestRandomAppearance()
    if not state.enabled
        or not isServerStateReady()
        or state.randomizePending
        or state.isRandomizeCoolingDown()
        or state.isPreviewMutationLocked() then
        return
    end

    -- Stop stale icon/model lookups before this batch replaces their items.
    -- That leaves the shared query queue available to the currently visible UI.
    state.cancelPendingSlotButtonIconQueries()
    state.cancelPreviewModelItemQueries()

    local snapshot = captureRandomizeSnapshot()
    local currentPreviewItemIds = {}
    for index, info in ipairs(SLOT_DATA) do
        currentPreviewItemIds[index] = tonumber(snapshot.preview[info.name].effectiveId) or 0
    end

    state.randomizeSnapshot = snapshot
    state.randomRequestToken = state.randomRequestToken + 1
    local now = state.getRandomizeTime()
    state.randomRequestStartedAt = now
    if now > 0 then
        state.randomizeCooldownUntil = now + state.randomizeMinIntervalSeconds
    end
    state.randomizePending = true
    if state.armRandomRequestPolling then state.armRandomRequestPolling() end
    updateActionButtons()
    AIO.Handle("Transmog", "GetRandomAppearancePreview", state.randomRequestToken, currentPreviewItemIds)
end

local function restoreRandomizedAppearance()
    local snapshot = state.randomizeSnapshot
    if state.isPreviewMutationLocked() then return end

    -- A close can happen before the server reply. Invalidate that reply before
    -- restoring so it cannot overwrite the restored preview afterward.
    if state.randomizePending then
        state.randomRequestToken = state.randomRequestToken + 1
    end
    state.randomizePending = false
    state.randomRequestStartedAt = 0

    if not snapshot then
        updateActionButtons()
        return
    end

    for _, info in ipairs(SLOT_DATA) do
        local saved = snapshot.preview[info.name]
        if saved then
            state.preview[info.name].mode = saved.mode
            state.preview[info.name].itemId = saved.itemId
            state.preview[info.name].effectiveId = saved.effectiveId
        end
    end
    for _, equipSlot in ipairs({15, 16, 17}) do
        state.weaponEnchantPreview[equipSlot] = tonumber(snapshot.weaponEnchants[equipSlot]) or 0
        state.weaponEnchantExplicitNoPreview[equipSlot] = type(snapshot.weaponEnchants.explicitNo) == "table"
            and snapshot.weaponEnchants.explicitNo[equipSlot] == true
    end

    state.randomizeSnapshot = nil
    refreshAllSlotButtons()
    refreshWeaponEnchantButtons()
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end

local function stageAppearanceSetPreview(itemIds, weaponEnchants)
    cancelPendingRandomize()
    for index, info in ipairs(SLOT_DATA) do
        local serverState = state.server[info.name]
        local hasEquippedItem = serverState and (tonumber(serverState.realItemId) or 0) > 0
        local itemId = type(itemIds) == "table" and tonumber(itemIds[index]) or -1

        if not hasEquippedItem then
            copyServerToPreview(info.name)
        elseif itemId and itemId > 0 then
            setPreviewToItem(info.name, itemId)
        elseif itemId == 0 then
            setPreviewToHidden(info.name)
        else
            setPreviewToRestore(info.name)
        end
    end

    for _, equipSlot in ipairs({15, 16, 17}) do
        if type(weaponEnchants) == "table" then
            local enchantId = tonumber(weaponEnchants[equipSlot] or weaponEnchants[tostring(equipSlot)]) or 0
            state.weaponEnchantPreview[equipSlot] = WEAPON_ENCHANT_OPTION_BY_ID[enchantId] and enchantId or 0
            local explicitNoSlots = weaponEnchants.explicitNo
            state.weaponEnchantExplicitNoPreview[equipSlot] = state.weaponEnchantPreview[equipSlot] == 0
                and type(explicitNoSlots) == "table"
                and (explicitNoSlots[equipSlot] == true or explicitNoSlots[tostring(equipSlot)] == true
                    or explicitNoSlots[equipSlot] == 1 or explicitNoSlots[tostring(equipSlot)] == 1)
        else
            copyWeaponEnchantServerToPreview(equipSlot)
        end
    end

    state.randomizeSnapshot = nil
    refreshAllSlotButtons()
    refreshWeaponEnchantButtons()
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end

local function createModelIconButton(name, texturePath, tooltipText)
    local button = CreateFrame("Button", name, transmogTab, "UIPanelButtonTemplate2")
    button:SetSize(24, 24)
    if ns.Theme then ns.Theme.SkinButton(button) end
    button.tooltipText = tooltipText
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("CENTER", 0, 0)
    button.icon:SetSize(16, 16)
    button.icon:SetTexture(texturePath)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local text = self.tooltipText or ""
        if not self:IsEnabled() and self.disabledTooltipText then
            text = self.disabledTooltipText
        end
        GameTooltip:SetText(text, 0.84, 0.66, 0.086)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

transmogTab.buttonRandomize = createModelIconButton(
    transmogTabName.."ButtonRandomize",
    "Interface\\Icons\\INV_Misc_Dice_02",
    "Randomize unlocked appearances"
)
if mainFrame.modelPanel then
    -- This is card chrome, not model content. Keep it fixed when the dressing
    -- room's safe inset changes.
    transmogTab.buttonRandomize:SetPoint("TOPRIGHT", mainFrame.modelPanel, "TOPRIGHT", -40, -22)
else
    transmogTab.buttonRandomize:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "TOPRIGHT", -38, -8)
end
transmogTab.buttonRandomize:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 5)
transmogTab.buttonRandomize:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    requestRandomAppearance()
end)

transmogTab.buttonRandomUndo = createModelIconButton(
    transmogTabName.."ButtonRandomUndo",
    "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo",
    "Undo last randomize"
)
transmogTab.buttonRandomUndo.disabledTooltipText = "Randomize an outfit first."
transmogTab.buttonRandomUndo:SetPoint("LEFT", transmogTab.buttonRandomize, "RIGHT", 3, 0)
transmogTab.buttonRandomUndo:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 5)
transmogTab.buttonRandomUndo:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    restoreRandomizedAppearance()
end)

local randomRequestTimeoutFrame = CreateFrame("Frame")
randomRequestTimeoutFrame.elapsed = 0
local function randomRequestTimeoutFrame_OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.05 then
        return
    end
    self.elapsed = 0

    local now = state.getRandomizeTime()
    if not state.randomizePending then
        if now > 0
            and (tonumber(state.randomizeCooldownUntil) or 0) > 0
            and now >= state.randomizeCooldownUntil then
            state.randomizeCooldownUntil = 0
            updateActionButtons()
        end
        if (tonumber(state.randomizeCooldownUntil) or 0) <= 0 then
            self:SetScript("OnUpdate", nil)
        end
        return
    end

    if now > 0 and (now - (state.randomRequestStartedAt or now)) >= state.randomizeRequestTimeoutSeconds then
        state.randomizePending = false
        state.randomRequestToken = state.randomRequestToken + 1
        state.randomRequestStartedAt = 0
        state.randomizeSnapshot = nil
        state.randomizeCooldownUntil = math.max(
            tonumber(state.randomizeCooldownUntil) or 0,
            now + state.randomizeTimeoutBackoffSeconds
        )
        refreshAllSlotButtons()
        refreshWeaponEnchantButtons()
        updatePreviewModel()
        updateListSelection()
        updateActionButtons()
        local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if chatFrame then
            chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: random appearance request timed out.")
        end
    end
end

state.armRandomRequestPolling = function()
    if randomRequestTimeoutFrame:GetScript("OnUpdate") == nil then
        randomRequestTimeoutFrame.elapsed = 0
        randomRequestTimeoutFrame:SetScript("OnUpdate", randomRequestTimeoutFrame_OnUpdate)
    end
end

transmogTab.searchLabel = transmogTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
-- Center the current-slot label in the lane between the mode tabs and actions.
transmogTab.searchLabel:SetPoint("TOPLEFT", 12, -25)
transmogTab.searchLabel:SetText("Head")
transmogTab.searchLabel:SetTextColor(0.92, 0.89, 0.80)
transmogTab.searchLabel:SetFontObject(GameFontHighlight)

transmogTab.searchBox = CreateFrame("EditBox", (transmogTab:GetName() or addon.."Transmog").."SearchBox", transmogTab, "InputBoxTemplate")
transmogTab.searchBox:SetMaxLetters(64)
transmogTab.searchBox:SetPoint("TOPRIGHT", transmogTab, "TOPRIGHT", -73, -36)
transmogTab.searchBox:SetWidth(94)
transmogTab.searchBox:SetHeight(18)
transmogTab.searchBox:SetAutoFocus(false)
transmogTab.searchBox:SetTextInsets(6, 22, 0, 0)
if ns.Theme then ns.Theme.SkinEditBox(transmogTab.searchBox) end
transmogTab.searchBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
transmogTab.searchBox:HookScript("OnHide", clearEditBoxFocus)
transmogTab.searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    requestCurrentSlotItems(true)
end)

transmogTab.searchPlaceholder = transmogTab.searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
transmogTab.searchPlaceholder:SetPoint("LEFT", 6, 0)
transmogTab.searchPlaceholder:SetText("Search")

transmogTab.searchBox:SetScript("OnTextChanged", function(self)
    if self:GetText() == "" then
        transmogTab.searchPlaceholder:Show()
        if transmogTab.buttonClearSearch then transmogTab.buttonClearSearch:Hide() end
    else
        transmogTab.searchPlaceholder:Hide()
        if transmogTab.buttonClearSearch then transmogTab.buttonClearSearch:Show() end
    end
end)

transmogTab.buttonSearch = CreateFrame("Button", transmogTabName.."ButtonSearch", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonSearch:SetPoint("TOPRIGHT", transmogTab, "TOPRIGHT", -8, 4)
transmogTab.buttonSearch:SetSize(61, 18)
transmogTab.buttonSearch:SetText("Search")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonSearch) end
transmogTab.searchBox:ClearAllPoints()
transmogTab.searchBox:SetPoint("TOPRIGHT", transmogTab.buttonSearch, "TOPLEFT", -4, 0)
transmogTab.buttonSearch:SetScript("OnClick", function()
    clearEditBoxFocus(transmogTab.searchBox)
    PlaySound("gsTitleOptionOK")
    requestCurrentSlotItems(true)
end)
transmogTab.buttonSearch:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Search unlocked appearances", 0.84, 0.66, 0.086)
    GameTooltip:Show()
end)
transmogTab.buttonSearch:HookScript("OnLeave", function()
    GameTooltip:Hide()
end)

transmogTab.buttonClearSearch = CreateFrame("Button", transmogTabName.."ButtonClearSearch", transmogTab.searchBox, "UIPanelButtonTemplate2")
transmogTab.buttonClearSearch:SetFrameLevel(transmogTab.searchBox:GetFrameLevel() + 1)
transmogTab.buttonClearSearch:SetPoint("RIGHT", transmogTab.searchBox, "RIGHT", -1, 0)
transmogTab.buttonClearSearch:SetSize(16, 16)
transmogTab.buttonClearSearch:SetText("x")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonClearSearch, "danger") end
transmogTab.buttonClearSearch:Hide()
transmogTab.buttonClearSearch:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    transmogTab.searchBox:SetText("")
    clearEditBoxFocus(transmogTab.searchBox)
    loadCurrentSlotItems()
end)

transmogTab.buttonWeaponFilter = CreateFrame("Button", transmogTabName.."ButtonWeaponFilter", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonWeaponFilter:SetPoint("TOPRIGHT", transmogTab, "TOPRIGHT", -8, -18)
transmogTab.buttonWeaponFilter:SetSize(159, 18)
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonWeaponFilter) end

transmogTab.weaponFilterMenu = CreateFrame("Frame", transmogTabName.."WeaponFilterMenu", UIParent, "UIDropDownMenuTemplate")
transmogTab.weaponFilterMenu:Hide()
transmogTab.weaponFilterMenu.displayMode = "MENU"

state.selectWeaponFilter = function(_, slotName, filterKey)
    if slotName ~= state.currentSlot
        or not state.getWeaponFilterOption(slotName, filterKey) then
        return
    end

    state.weaponFilterBySlot[slotName] = filterKey
    state.currentPage = 1
    state.slotPages[slotName] = nil
    state.slotPageAnchors[slotName] = nil
    state.refreshWeaponFilterButton()
    CloseDropDownMenus()
    PlaySound("gsTitleOptionOK")
    requestCurrentSlotItems(true)
end

UIDropDownMenu_Initialize(transmogTab.weaponFilterMenu, function(_, level)
    if level ~= 1 then
        return
    end

    local slotName = state.currentSlot
    local selectedKey = state.getWeaponFilterKey(slotName)
    for _, option in ipairs(transmogTab.weaponFilterOptions[slotName] or {}) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.label
        info.checked = option.key == selectedKey
        info.arg1 = slotName
        info.arg2 = option.key
        info.func = state.selectWeaponFilter
        UIDropDownMenu_AddButton(info, level)
    end
end, "MENU")

transmogTab.buttonWeaponFilter:SetScript("OnClick", function(self)
    if transmogTab.weaponFilterOptions[state.currentSlot] then
        ToggleDropDownMenu(1, nil, transmogTab.weaponFilterMenu, self, 0, 0)
    end
end)
transmogTab.buttonWeaponFilter:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Filter unlocked weapon appearances", 0.84, 0.66, 0.086)
    GameTooltip:Show()
end)
transmogTab.buttonWeaponFilter:HookScript("OnLeave", function()
    GameTooltip:Hide()
end)
state.refreshWeaponFilterButton()

transmogTab.buttonNext = CreateFrame("Button", transmogTabName.."ButtonNext", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonNext:SetPoint("BOTTOM", transmogTab, "BOTTOM", 58, 0)
transmogTab.buttonNext:SetSize(18, 18)
transmogTab.buttonNext:SetText(">")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonNext) end
transmogTab.buttonNext:SetScript("OnClick", function()
    changePage(1)
end)

transmogTab.pageText = transmogTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
transmogTab.pageText:SetPoint("BOTTOM", transmogTab, "BOTTOM", 0, 4)
transmogTab.pageText:SetText("Page 1")
transmogTab.pageText:SetTextColor(0.84, 0.66, 0.086)
transmogTab.buttonNext:ClearAllPoints()
transmogTab.buttonNext:SetPoint("LEFT", transmogTab.pageText, "RIGHT", 7, -1)

transmogTab.buttonPrev = CreateFrame("Button", transmogTabName.."ButtonPrev", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonPrev:SetPoint("BOTTOM", transmogTab, "BOTTOM", -58, 0)
transmogTab.buttonPrev:SetSize(18, 18)
transmogTab.buttonPrev:SetText("<")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonPrev) end
transmogTab.buttonPrev:ClearAllPoints()
transmogTab.buttonPrev:SetPoint("RIGHT", transmogTab.pageText, "LEFT", -7, -1)
transmogTab.buttonPrev:SetScript("OnClick", function()
    changePage(-1)
end)

transmogTab.list = ns.CreatePreviewList(transmogTab)
transmogTab.list:SetPoint("TOPLEFT", 8, LIST_TOP_Y)
transmogTab.list:SetPoint("BOTTOMRIGHT", -8, LIST_BOTTOM_Y)
transmogTab.list:Hide()
transmogTab.list.onEnter = onListItemEnter
transmogTab.list.onLeave = onListItemLeave
transmogTab.list.onItemClick = onListItemClick

transmogTab.messageText = transmogTab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
transmogTab.messageText:SetPoint("TOPLEFT", transmogTab.list, "TOPLEFT", 20, -24)
transmogTab.messageText:SetPoint("BOTTOMRIGHT", transmogTab.list, "BOTTOMRIGHT", -20, 24)
transmogTab.messageText:SetJustifyH("CENTER")
transmogTab.messageText:SetJustifyV("MIDDLE")
transmogTab.messageText:SetTextColor(1, 0.82, 0)
transmogTab.messageText:Hide()

transmogTab.buttonApply = CreateFrame("Button", transmogTabName.."ButtonApply", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonApply:SetPoint("TOPLEFT", 150, SLOT_ACTION_ROW_Y)
transmogTab.buttonApply:SetSize(144, 21)
transmogTab.buttonApply:SetText("Show Equipped Gear")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonApply) end
addLeadingButtonIcon(transmogTab.buttonApply, "Interface\\Icons\\INV_Chest_Chain_05")
transmogTab.buttonApply:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    state.showEquippedGear = not state.showEquippedGear
    transmogTab.list.skipUndress = state.showEquippedGear
        or state.currentSlot == "Main Hand"
        or state.currentSlot == "Off-hand"
    if transmogTab.list:IsShown()
        and type(transmogTab.list.itemIds) == "table"
        and #transmogTab.list.itemIds > 0 then
        transmogTab.list:Update()
    end
    updatePreviewModel()
    updateActionButtons()
end)

transmogTab.buttonHide = CreateFrame("Button", transmogTabName.."ButtonHide", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonHide:SetPoint("LEFT", transmogTab.buttonApply, "RIGHT", 8, 0)
transmogTab.buttonHide:SetSize(58, 21)
transmogTab.buttonHide:SetText("Hide")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonHide, "danger") end
transmogTab.buttonHide:SetScript("OnClick", function()
    if state.isPreviewMutationLocked() then return end
    cancelPendingRandomize()
    PlaySound("gsTitleOptionOK")
    if state.preview[state.currentSlot].mode == "hidden" then
        setPreviewToRestore(state.currentSlot)
    else
        setPreviewToHidden(state.currentSlot)
    end
    refreshSlotButton(state.currentSlot)
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end)

transmogTab.buttonRestore = CreateFrame("Button", transmogTabName.."ButtonRestore", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonRestore:SetPoint("TOPLEFT", 12, SLOT_ACTION_ROW_Y)
transmogTab.buttonRestore:SetSize(130, 21)
transmogTab.buttonRestore:SetText("Unassigned")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonRestore) end
addLeadingButtonIcon(transmogTab.buttonRestore, "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Opaque")
transmogTab.buttonRestore:SetScript("OnClick", function()
    if state.isPreviewMutationLocked() then return end
    cancelPendingRandomize()
    PlaySound("gsTitleOptionOK")
    if state.enchantingEquipSlot then
        state.weaponEnchantPreview[state.enchantingEquipSlot] = 0
        state.weaponEnchantExplicitNoPreview[state.enchantingEquipSlot] = true
        if refreshWeaponEnchantButtons then refreshWeaponEnchantButtons() end
        if refreshWeaponEnchantPicker then refreshWeaponEnchantPicker() end
    else
        setPreviewToRestore(state.currentSlot)
        refreshSlotButton(state.currentSlot)
        updateListSelection()
    end
    updatePreviewModel()
    updateActionButtons()
end)

local function getWeaponEnchantIcon(option)
    if option and option.id == 0 then
        return "Interface\\Icons\\INV_Scroll_03"
    end
    if option and option.spellId and type(GetSpellInfo) == "function" then
        local _, _, icon = GetSpellInfo(option.spellId)
        if icon then
            return icon
        end
    end
    return "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
end

refreshWeaponEnchantButtons = function()
    for _, equipSlot in ipairs({15, 16, 17}) do
        local button = state.weaponEnchantButtons[equipSlot]
        local slotName = WEAPON_NAME_BY_EQUIPMENT_SLOT[equipSlot]
        local equipped = state.server[slotName] and tonumber(state.server[slotName].realItemId) and tonumber(state.server[slotName].realItemId) > 0
        -- Do not expose a picker until the server has authoritatively confirmed
        -- this exact equipped weapon can receive a cosmetic enchant.
        local eligible = state.weaponEnchantEligible[equipSlot] == true
        if button then
            local enchantId = tonumber(state.weaponEnchantPreview[equipSlot]) or 0
            local option = WEAPON_ENCHANT_OPTION_BY_ID[enchantId] or WEAPON_ENCHANT_OPTION_BY_ID[0]
            if equipped and eligible then
                button:Enable()
            else
                button:Disable()
            end
            button:SetAlpha(equipped and eligible and 1 or 0.55)
            SetItemButtonTexture(button, equipped and eligible and getWeaponEnchantIcon(option) or "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            if isWeaponEnchantDirty(equipSlot) then button.pendingGlow:Show() else button.pendingGlow:Hide() end
        end
    end
end

-- A compact five-by-four enchant gallery mirrors the item browser rather than
-- opening a menu over the model. Each selection is preview-only until the
-- sidebar Apply action is pressed.
do
    local picker = CreateFrame("Frame", transmogTabName.."WeaponEnchantPicker", transmogTab)
    picker:SetPoint("TOPLEFT", transmogTab.list, "TOPLEFT", 0, 0)
    picker:SetPoint("BOTTOMRIGHT", transmogTab.list, "BOTTOMRIGHT", 0, 0)
    picker:Hide()
    picker.buttons = {}
    transmogTab.enchantPicker = picker

    for index = 1, 20 do
        local column = (index - 1) % 5
        local row = math.floor((index - 1) / 5)
        local button = CreateFrame("Button", transmogTabName.."WeaponEnchantChoice"..index, picker, "UIPanelButtonTemplate2")
        button:SetSize(76, 90)
        button:SetPoint("TOPLEFT", 4 + (column * 82), -4 - (row * 94))
        if ns.Theme then ns.Theme.SkinButton(button) end

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(38, 38)
        button.icon:SetPoint("TOP", 0, -8)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.label:SetPoint("TOPLEFT", button.icon, "BOTTOMLEFT", -16, -5)
        button.label:SetPoint("TOPRIGHT", button.icon, "BOTTOMRIGHT", 16, -5)
        button.label:SetJustifyH("CENTER")
        button.label:SetJustifyV("TOP")
        button.label:SetWordWrap(true)

        -- UI-ActionButton-Border only outlines the square enchant icon.  Use a
        -- real child-frame border so selection follows the full 76x90 card.
        button.selectedGlow = CreateFrame("Frame", nil, button)
        button.selectedGlow:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        button.selectedGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        button.selectedGlow:SetFrameLevel(button:GetFrameLevel() + 2)
        button.selectedGlow:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        button.selectedGlow:SetBackdropBorderColor(0.85, 0.18, 0.96, 1)
        button.selectedGlow:Hide()

        button:SetScript("OnClick", function(self)
            if not self.enchantId or not state.enchantingEquipSlot then
                return
            end
            if state.isPreviewMutationLocked() then
                return
            end
            cancelPendingRandomize()
            PlaySound("gsTitleOptionOK")
            state.weaponEnchantPreview[state.enchantingEquipSlot] = self.enchantId
            state.weaponEnchantExplicitNoPreview[state.enchantingEquipSlot] = self.enchantId == 0
            refreshWeaponEnchantButtons()
            refreshWeaponEnchantPicker()
            updatePreviewModel()
            updateActionButtons()
        end)
        button:SetScript("OnEnter", function(self)
            if not self.option then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.option.name, 1, 0.82, 0)
            GameTooltip:AddLine("Cosmetic only. Does not change weapon stats.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        picker.buttons[index] = button
    end
end

refreshWeaponEnchantPicker = function()
    local picker = transmogTab.enchantPicker
    if not picker or not state.enchantingEquipSlot then
        if picker then picker:Hide() end
        return
    end

    local pageCount = math.max(1, math.ceil(#WEAPON_ENCHANT_OPTIONS / 20))
    if state.enchantPage < 1 then state.enchantPage = 1 end
    if state.enchantPage > pageCount then state.enchantPage = pageCount end
    local firstIndex = ((state.enchantPage - 1) * 20) + 1
    local selectedEnchant = tonumber(state.weaponEnchantPreview[state.enchantingEquipSlot]) or 0

    for index, button in ipairs(picker.buttons) do
        local option = WEAPON_ENCHANT_OPTIONS[firstIndex + index - 1]
        if option then
            button.option = option
            button.enchantId = option.id
            button.icon:SetTexture(getWeaponEnchantIcon(option))
            button.label:SetText(option.name)
            if option.id == selectedEnchant then button.selectedGlow:Show() else button.selectedGlow:Hide() end
            if state.isPreviewMutationLocked() then button:Disable() else button:Enable() end
            button:Show()
        else
            button.option = nil
            button.enchantId = nil
            button:Hide()
        end
    end

    state.enchantHasMorePages = state.enchantPage < pageCount
    picker:Show()
    updatePageText()
end

hideWeaponEnchantPicker = function()
    if not state.enchantingEquipSlot then
        return
    end

    state.enchantingEquipSlot = nil
    if transmogTab.enchantPicker then transmogTab.enchantPicker:Hide() end
    if state.viewMode == "items" then
        transmogTab.buttonHide:Show()
        transmogTab.searchBox:Show()
        transmogTab.buttonSearch:Show()
        if trim(transmogTab.searchBox:GetText()) == "" then
            transmogTab.searchPlaceholder:Show()
            transmogTab.buttonClearSearch:Hide()
        else
            transmogTab.searchPlaceholder:Hide()
            transmogTab.buttonClearSearch:Show()
        end
    end
    state.refreshWeaponFilterButton()
end

showWeaponEnchantPicker = function(equipSlot)
    equipSlot = tonumber(equipSlot)
    local slotName = WEAPON_NAME_BY_EQUIPMENT_SLOT[equipSlot]
    if not slotName
        or state.weaponEnchantEligible[equipSlot] ~= true
        or not (state.server[slotName] and tonumber(state.server[slotName].realItemId) and tonumber(state.server[slotName].realItemId) > 0) then
        return
    end

    state.cancelAppearancePageActivity()
    state.cancelPageLookupActivity()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
    state.enchantingEquipSlot = equipSlot
    state.enchantPage = 1
    state.enchantHasMorePages = #WEAPON_ENCHANT_OPTIONS > 20
    state.refreshWeaponFilterButton()
    transmogTab.searchLabel:SetText(slotName.." Enchant")
    clearEditBoxFocus(transmogTab.searchBox)
    transmogTab.searchBox:Hide()
    transmogTab.searchPlaceholder:Hide()
    transmogTab.buttonSearch:Hide()
    transmogTab.buttonClearSearch:Hide()
    transmogTab.buttonHide:Hide()
    transmogTab.list:Hide()
    transmogTab.messageText:Hide()
    refreshWeaponEnchantPicker()
    updateActionButtons()
end

local function applyPendingChanges()
    if not state.enabled
        or not isServerStateReady()
        or state.isPreviewMutationLocked()
        or state.randomizePending
        or getDirtyCount() == 0
        or getPendingCost() > (tonumber(state.money) or 0) then
        return false
    end

    return applyAppearanceSetAsTransmog(snapshotCurrentTransmogSet(), snapshotCurrentWeaponEnchants())
end

local actionParent = mainFrame.sidebar or mainFrame
local function attachActionTooltip(button, title, body)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 0.84, 0.66, 0.086)
        GameTooltip:AddLine(body, 0.92, 0.89, 0.80, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
end

transmogTab.buttonRevert = CreateFrame("Button", transmogTabName.."ButtonRevert", actionParent, "UIPanelButtonTemplate2")
transmogTab.buttonRevert:Hide()
transmogTab.buttonRevert:SetPoint("BOTTOMLEFT", actionParent, "BOTTOMLEFT", 8, 38)
transmogTab.buttonRevert:SetSize(54, 22)
transmogTab.buttonRevert:SetText("Revert")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonRevert) end
attachActionTooltip(transmogTab.buttonRevert, "Revert", "Discard all pending item and enchant preview changes.")
transmogTab.buttonRevert:SetScript("OnClick", function()
    if state.isPreviewMutationLocked() then return end
    PlaySound("gsTitleOptionOK")
    revertAllPreview()
end)

transmogTab.buttonRevertAll = CreateFrame("Button", transmogTabName.."ButtonRevertAll", actionParent, "UIPanelButtonTemplate2")
transmogTab.buttonRevertAll:Hide()
transmogTab.buttonRevertAll:SetPoint("LEFT", transmogTab.buttonRevert, "RIGHT", 4, 0)
transmogTab.buttonRevertAll:SetSize(68, 22)
transmogTab.buttonRevertAll:SetText("Revert All")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonRevertAll, "danger") end
attachActionTooltip(transmogTab.buttonRevertAll, "Revert All", "Remove every applied appearance and cosmetic weapon enchant. Normal per-slot transmog fees apply.")
transmogTab.buttonRevertAll:SetScript("OnClick", function()
    if state.isPreviewMutationLocked()
        or not isServerStateReady()
        or state.getRestoreAllCost() > (tonumber(state.money) or 0)
        or not hasAppliedTransmogs() then
        return
    end

    PlaySound("gsTitleOptionOK")
    revertAllTransmogs()
    updateActionButtons()
end)

transmogTab.buttonApplyAll = CreateFrame("Button", transmogTabName.."ButtonApplyAll", actionParent, "UIPanelButtonTemplate2")
transmogTab.buttonApplyAll:Hide()
transmogTab.buttonApplyAll:SetPoint("LEFT", transmogTab.buttonRevertAll, "RIGHT", 4, 0)
transmogTab.buttonApplyAll:SetSize(54, 22)
transmogTab.buttonApplyAll:SetText("Apply")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonApplyAll) end
attachActionTooltip(transmogTab.buttonApplyAll, "Apply", "Apply all pending item and cosmetic weapon-enchant changes.")
transmogTab.buttonApplyAll:SetScript("OnClick", function()
    if applyPendingChanges() then
        PlaySound("gsTitleOptionOK")
    end
end)

transmogTab.buttonModeItems = CreateFrame("Button", transmogTabName.."ButtonModeItems", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonModeItems:SetPoint("TOPLEFT", 8, 4)
transmogTab.buttonModeItems:SetSize(58, 20)
transmogTab.buttonModeItems:SetText("Items")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonModeItems) end

transmogTab.buttonModeSets = CreateFrame("Button", transmogTabName.."ButtonModeSets", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonModeSets:SetPoint("LEFT", transmogTab.buttonModeItems, "RIGHT", 4, 0)
transmogTab.buttonModeSets:SetSize(58, 20)
transmogTab.buttonModeSets:SetText("Sets")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonModeSets) end

transmogTab.buttonModeCustomSets = CreateFrame("Button", transmogTabName.."ButtonModeCustomSets", transmogTab, "UIPanelButtonTemplate2")
transmogTab.buttonModeCustomSets:SetPoint("LEFT", transmogTab.buttonModeSets, "RIGHT", 4, 0)
transmogTab.buttonModeCustomSets:SetSize(88, 20)
transmogTab.buttonModeCustomSets:SetText("Custom Sets")
if ns.Theme then ns.Theme.SkinButton(transmogTab.buttonModeCustomSets) end
state.ensureSetsUI = function()
    if transmogTab.setsFrame then
        return transmogTab.setsFrame
    end

    assert(type(state.bindSetsUIHandlers) == "function", "AppearanceBuddy Sets UI handlers were not initialized")

    local setsFrame = CreateFrame("Frame", transmogTabName.."SetsFrame", transmogTab)
    setsFrame:SetPoint("TOPLEFT", 8, -34)
    setsFrame:SetPoint("BOTTOMRIGHT", -8, SETS_FRAME_BOTTOM_Y)
    setsFrame:Hide()

    local previewBackdrop = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    }

    setsFrame.buttonSourceSaved = CreateFrame("Button", transmogTabName.."ButtonSourceSaved", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonSourceSaved:SetPoint("TOPLEFT", 0, 0)
    setsFrame.buttonSourceSaved:SetSize(82, 20)
    setsFrame.buttonSourceSaved:SetText("Saved")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonSourceSaved) end

    setsFrame.buttonSourceCatalog = CreateFrame("Button", transmogTabName.."ButtonSourceCatalog", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonSourceCatalog:SetPoint("LEFT", setsFrame.buttonSourceSaved, "RIGHT", 6, 0)
    setsFrame.buttonSourceCatalog:SetSize(82, 20)
    setsFrame.buttonSourceCatalog:SetText("Catalog")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonSourceCatalog) end

    setsFrame.searchBox = CreateFrame("EditBox", transmogTabName.."SetsSearchBox", setsFrame, "InputBoxTemplate")
    setsFrame.searchBox:SetMaxLetters(64)
    setsFrame.searchBox:SetPoint("TOPLEFT", 2, -26)
    setsFrame.searchBox:SetSize(184, 18)
    setsFrame.searchBox:SetAutoFocus(false)
    setsFrame.searchBox:SetTextInsets(6, 22, 0, 0)
    if ns.Theme then ns.Theme.SkinEditBox(setsFrame.searchBox) end

    setsFrame.searchPlaceholder = setsFrame.searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setsFrame.searchPlaceholder:SetPoint("LEFT", 6, 0)
    setsFrame.searchPlaceholder:SetText("Search sets")

    setsFrame.buttonClearSearch = CreateFrame("Button", transmogTabName.."ButtonClearSetSearch", setsFrame.searchBox, "UIPanelButtonTemplate2")
    setsFrame.buttonClearSearch:SetFrameLevel(setsFrame.searchBox:GetFrameLevel() + 1)
    setsFrame.buttonClearSearch:SetPoint("RIGHT", setsFrame.searchBox, "RIGHT", -1, 0)
    setsFrame.buttonClearSearch:SetSize(16, 16)
    setsFrame.buttonClearSearch:SetText("x")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonClearSearch, "danger") end
    setsFrame.buttonClearSearch:Hide()

    local function updateSetSearchDecorations()
        if trim(setsFrame.searchBox:GetText()) == "" then
            setsFrame.searchPlaceholder:Show()
            setsFrame.buttonClearSearch:Hide()
        else
            setsFrame.searchPlaceholder:Hide()
            setsFrame.buttonClearSearch:Show()
        end
    end

    setsFrame.SyncSearchBox = function(self)
        self._appearanceBuddySyncingSearch = true
        self.searchBox:SetText(state.setSearchBySource[state.setSource] or "")
        self._appearanceBuddySyncingSearch = false
        updateSetSearchDecorations()
    end

    local searchDebounceFrame = CreateFrame("Frame")
    searchDebounceFrame.elapsed = 0

    local function applySetSearch()
        searchDebounceFrame:SetScript("OnUpdate", nil)
        searchDebounceFrame.elapsed = 0
        if state.setSource == SET_SOURCE_CATALOG then
            requestItemSetCatalog(1, state.setSearchBySource[SET_SOURCE_CATALOG])
        elseif rebuildSetLists then
            rebuildSetLists()
        end
    end

    local function scheduleSetSearch()
        searchDebounceFrame.elapsed = 0
        if searchDebounceFrame:GetScript("OnUpdate") == nil then
            searchDebounceFrame:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed
                if self.elapsed >= 0.20 then
                    applySetSearch()
                end
            end)
        end
    end

    setsFrame.ApplySearchNow = applySetSearch
    setsFrame.CancelSearchDebounce = function()
        searchDebounceFrame:SetScript("OnUpdate", nil)
        searchDebounceFrame.elapsed = 0
    end

    setsFrame.searchBox:SetScript("OnTextChanged", function(self)
        updateSetSearchDecorations()
        if setsFrame._appearanceBuddySyncingSearch then
            return
        end
        state.setSearchBySource[state.setSource] = self:GetText() or ""
        if state.setSource == SET_SOURCE_CATALOG
            and state.itemSetCatalogRequestPending
            and state.normalizeItemSetCatalogSearch(self:GetText()) ~= state.itemSetCatalogRequestSearch then
            state.itemSetCatalogRequestToken = state.itemSetCatalogRequestToken + 1
            state.itemSetCatalogRequestPending = false
            state.itemSetCatalogRequestStartedAt = 0
            state.itemSetCatalogRequestPage = 0
            updateSetButtons()
            if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
        end
        scheduleSetSearch()
    end)
    setsFrame.searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        applySetSearch()
    end)
    setsFrame.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    setsFrame.searchBox:HookScript("OnHide", clearEditBoxFocus)
    setsFrame.buttonClearSearch:SetScript("OnClick", function()
        PlaySound("gsTitleOptionOK")
        setsFrame.searchBox:SetText("")
        setsFrame.searchBox:ClearFocus()
    end)

    setsFrame.listTitle = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setsFrame.listTitle:SetPoint("TOPLEFT", 0, -52)
    setsFrame.listTitle:SetText("Saved Transmog Sets")

    setsFrame.listScroll = CreateFrame("ScrollFrame", transmogTabName.."SetsScroll", setsFrame, "UIPanelScrollFrameTemplate")
    setsFrame.listScroll:SetPoint("TOPLEFT", 0, -72)
    setsFrame.listScroll:SetPoint("BOTTOMLEFT", 0, 36)
    setsFrame.listScroll:SetWidth(SETS_LIST_SCROLL_WIDTH)

    setsFrame.list = ns.CreateListFrame(transmogTabName.."SetsList", nil, setsFrame.listScroll)
    setsFrame.list:SetPoint("TOPLEFT", 0, 0)
    setsFrame.list:SetWidth(SETS_LIST_WIDTH)
    setsFrame.listScroll:SetScrollChild(setsFrame.list)

    setsFrame.emptyText = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setsFrame.emptyText:SetPoint("TOPLEFT", setsFrame.listScroll, "TOPLEFT", 8, -18)
    setsFrame.emptyText:SetPoint("TOPRIGHT", setsFrame.listScroll, "TOPRIGHT", -8, -18)
    setsFrame.emptyText:SetJustifyH("CENTER")
    setsFrame.emptyText:SetTextColor(0.52, 0.49, 0.43)
    setsFrame.emptyText:Hide()
    local setsScrollBar = setsFrame.listScroll.ScrollBar or _G[transmogTabName.."SetsScrollScrollBar"]
    if setsScrollBar then
        -- UIPanelScrollFrameTemplate anchors its bar beyond the viewport.
        -- Bring it back to the row edge while retaining room before preview.
        local barOffsetX = SETS_LIST_WIDTH - SETS_LIST_SCROLL_WIDTH
        setsScrollBar:ClearAllPoints()
        setsScrollBar:SetPoint("TOPLEFT", setsFrame.listScroll, "TOPRIGHT", barOffsetX, -16)
        setsScrollBar:SetPoint("BOTTOMLEFT", setsFrame.listScroll, "BOTTOMRIGHT", barOffsetX, 16)
    end
    if ns.RefreshManagedScrollFrame then
        ns.RefreshManagedScrollFrame(setsFrame.listScroll)
    end
    setsFrame:HookScript("OnShow", function(self)
        state.resumeSetListIconQueries(self.list)
        if state.itemSetCatalogRequestPending and state.armRequestTimeoutPolling then
            state.armRequestTimeoutPolling()
        end
        if ns.RefreshManagedScrollFrame then
            ns.RefreshManagedScrollFrame(self.listScroll)
        end
    end)
    setsFrame:HookScript("OnHide", function(self)
        clearEditBoxFocus(self.searchBox)
        self:CancelSearchDebounce()
        if ns.RefreshManagedScrollFrame then
            ns.RefreshManagedScrollFrame(self.listScroll, false)
        end
    end)

    setsFrame.previewTitle = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setsFrame.previewTitle:SetPoint("TOPLEFT", SETS_PREVIEW_LEFT_X, -4)
    setsFrame.previewTitle:SetPoint("TOPRIGHT", -8, -4)
    setsFrame.previewTitle:SetJustifyH("LEFT")
    setsFrame.previewTitle:SetText("Set Preview")

    setsFrame.previewInfo = setsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    setsFrame.previewInfo:SetPoint("BOTTOMLEFT", SETS_PREVIEW_LEFT_X, 52)
    setsFrame.previewInfo:SetPoint("BOTTOMRIGHT", -8, 52)
    setsFrame.previewInfo:SetJustifyH("LEFT")
    setsFrame.previewInfo:SetJustifyV("TOP")

    setsFrame.previewModel = ns.CreateDressingRoom(nil, setsFrame)
    setsFrame.previewModel:SetPoint("TOPLEFT", SETS_PREVIEW_LEFT_X, -24)
    setsFrame.previewModel:SetPoint("BOTTOMRIGHT", -8, 84)
    setsFrame.previewModel:SetBackdrop(previewBackdrop)
    setsFrame.previewModel:SetBackdropColor(0.008, 0.008, 0.008, 0.985)
    setsFrame.previewModel:SetBackdropBorderColor(0.55, 0.396, 0.075, 1)
    setsFrame.previewModel:EnableDragRotation(false)
    setsFrame.previewModel:EnableMouseWheel(false)
    setsFrame.previewModel:SetUnit("player")
    setsFrame.previewModel:Reset()
    setStaticTransmogModelView(setsFrame.previewModel)
    updateSetPreviewBackground(setsFrame.previewModel)

    setsFrame.buttonCopyCurrent = CreateFrame("Button", transmogTabName.."ButtonCopyCurrentSet", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonCopyCurrent:SetPoint("BOTTOMLEFT", 0, 0)
    setsFrame.buttonCopyCurrent:SetSize(116, 22)
    setsFrame.buttonCopyCurrent:SetText("Copy Current...")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonCopyCurrent) end

    setsFrame.buttonRemoveSaved = CreateFrame("Button", transmogTabName.."ButtonRemoveSavedSet", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonRemoveSaved:SetPoint("LEFT", setsFrame.buttonCopyCurrent, "RIGHT", 6, 0)
    setsFrame.buttonRemoveSaved:SetSize(78, 22)
    setsFrame.buttonRemoveSaved:SetText("Remove")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonRemoveSaved, "danger") end

    setsFrame.buttonRefreshCatalog = CreateFrame("Button", transmogTabName.."ButtonRefreshCatalog", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonRefreshCatalog:SetPoint("BOTTOMLEFT", 0, 0)
    setsFrame.buttonRefreshCatalog:SetSize(116, 22)
    setsFrame.buttonRefreshCatalog:SetText("Refresh")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonRefreshCatalog) end

    setsFrame.buttonLoadMore = CreateFrame("Button", transmogTabName.."ButtonLoadMoreSets", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonLoadMore:SetPoint("LEFT", setsFrame.buttonRefreshCatalog, "RIGHT", 6, 0)
    setsFrame.buttonLoadMore:SetSize(66, 22)
    setsFrame.buttonLoadMore:SetText("More")
    setsFrame.buttonLoadMore:Hide()
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonLoadMore) end

    setsFrame.buttonApplySelected = CreateFrame("Button", transmogTabName.."ButtonApplySelectedSet", setsFrame, "UIPanelButtonTemplate2")
    setsFrame.buttonApplySelected:SetPoint("BOTTOMRIGHT", -8, 0)
    setsFrame.buttonApplySelected:SetSize(118, 22)
    setsFrame.buttonApplySelected:SetText("Apply Set")
    if ns.Theme then ns.Theme.SkinButton(setsFrame.buttonApplySelected) end

    setsFrame.buttonLoadMore:SetScript("OnClick", function()
        if state.requestNextItemSetCatalogPage() then
            PlaySound("gsTitleOptionOK")
        end
    end)

    setsFrame.listScroll:HookScript("OnVerticalScroll", function(self, offset)
        if state.viewMode ~= "sets" or state.setSource ~= SET_SOURCE_CATALOG
            or not state.itemSetCatalogHasMore or state.itemSetCatalogRequestPending then
            return
        end
        local maxScroll = math.max(0, (setsFrame.list:GetHeight() or 0) - (self:GetHeight() or 0))
        if maxScroll > 0 and maxScroll - (tonumber(offset) or 0) <= SETS_SCROLL_STEP then
            state.requestNextItemSetCatalogPage()
        end
    end)

    state.bindSetsUIHandlers(setsFrame)
    transmogTab.setsFrame = setsFrame
    return setsFrame
end

state.setUIController = {}
do
local itemModeWidgets = {
    transmogTab.searchLabel,
    transmogTab.searchBox,
    transmogTab.searchPlaceholder,
    transmogTab.buttonSearch,
    transmogTab.buttonClearSearch,
    transmogTab.pageText,
    transmogTab.buttonPrev,
    transmogTab.buttonNext,
    transmogTab.list,
    transmogTab.messageText,
    transmogTab.buttonApply,
    transmogTab.buttonHide,
    transmogTab.buttonRestore,
    transmogTab.buttonRandomize,
    transmogTab.buttonRandomUndo,
}

for _, info in ipairs(SLOT_DATA) do
    table.insert(itemModeWidgets, state.slotButtons[info.name])
end
for _, equipSlot in ipairs({15, 16, 17}) do
    table.insert(itemModeWidgets, state.weaponEnchantButtons[equipSlot])
end

state.setUIController.updateModeButtons = function()
    transmogTab.buttonModeItems:UnlockHighlight()
    transmogTab.buttonModeSets:UnlockHighlight()
    transmogTab.buttonModeCustomSets:UnlockHighlight()
    if ns.Theme then
        ns.Theme.SetSelected(transmogTab.buttonModeItems, false)
        ns.Theme.SetSelected(transmogTab.buttonModeSets, false)
        ns.Theme.SetSelected(transmogTab.buttonModeCustomSets, false)
    end
    if state.viewMode == "items" then
        transmogTab.buttonModeItems:LockHighlight()
        if ns.Theme then ns.Theme.SetSelected(transmogTab.buttonModeItems, true) end
    elseif state.viewMode == "sets" and state.setSource == SET_SOURCE_CATALOG then
        transmogTab.buttonModeSets:LockHighlight()
        if ns.Theme then ns.Theme.SetSelected(transmogTab.buttonModeSets, true) end
    elseif state.viewMode == "sets" then
        transmogTab.buttonModeCustomSets:LockHighlight()
        if ns.Theme then ns.Theme.SetSelected(transmogTab.buttonModeCustomSets, true) end
    end
end

state.setUIController.setItemModeVisible = function(visible)
    if not visible then
        clearEditBoxFocus(transmogTab.searchBox)
        state.cancelPendingSlotButtonIconQueries()
    end

    if not visible and hideWeaponEnchantPicker then
        hideWeaponEnchantPicker()
    end

    for _, widget in ipairs(itemModeWidgets) do
        if widget and widget ~= transmogTab.list and widget ~= transmogTab.messageText then
            if visible and not (widget == transmogTab.buttonHide and state.enchantingEquipSlot) then
                widget:Show()
            else
                widget:Hide()
            end
        end
    end

    if visible then
        if state.enchantingEquipSlot then
            transmogTab.messageText:Hide()
            transmogTab.list:Hide()
            if refreshWeaponEnchantPicker then refreshWeaponEnchantPicker() end
        elseif transmogTab.messageText:GetText() ~= "" and (#transmogTab.list.itemIds == 0 or not transmogTab.list.dressingRoomSetup) then
            transmogTab.messageText:Show()
            transmogTab.list:Hide()
        else
            transmogTab.messageText:Hide()
            transmogTab.list:Show()
        end
    else
        transmogTab.messageText:Hide()
        transmogTab.list:Hide()
        if transmogTab.enchantPicker then transmogTab.enchantPicker:Hide() end
    end
    state.refreshWeaponFilterButton()
end

state.setUIController.getSelectedSavedSet = function()
    local selectedName = state.selectedSavedSetName
    if not selectedName then
        return nil
    end

    for _, setData in ipairs(getSavedTransmogSets()) do
        if setData.name == selectedName then
            return setData
        end
    end

    return nil
end

state.setUIController.getSelectedCatalogSet = function()
    local selectedId = tonumber(state.selectedCatalogSetId)
    if not selectedId then
        return nil
    end

    return state.itemSetCatalogById[selectedId]
end

local function buildCatalogSetCostItems(details)
    local items = {}
    for index = 1, #SLOT_DATA do
        local unlockedItemId = type(details) == "table"
            and type(details.unlockedItems) == "table"
            and tonumber(details.unlockedItems[index])
            or 0
        local previewItemId = type(details) == "table"
            and type(details.fullItems) == "table"
            and tonumber(details.fullItems[index])
            or 0

        if unlockedItemId and unlockedItemId > 0 then
            items[index] = unlockedItemId
        elseif index <= 11 and (not previewItemId or previewItemId <= 0) then
            items[index] = 0
        else
            -- Locked catalog pieces are rejected by the server and cost zero;
            -- quote the exact current state instead of a restore, which could
            -- itself be a charged change when a transmog is already applied.
            local currentItemId = state.server[SLOT_DATA[index].name].itemId
            items[index] = currentItemId == nil and -1 or currentItemId
        end
    end
    return items
end

local function isCatalogSetComplete(setData)
    if type(setData) ~= "table" then
        return false
    end

    if setData.hasExactTotal == false then
        return false
    end

    local unlockedCount = tonumber(setData.unlockedCount) or 0
    local totalCount = tonumber(setData.totalCount) or 0
    return totalCount > 0 and unlockedCount >= totalCount
end

local function getCatalogSetRowLabel(setData)
    if type(setData) ~= "table" then
        return "Set"
    end

    local baseLabel = tostring(setData.displayName or setData.name or "Set")
    if isCatalogSetComplete(setData) then
        return "|cff40ff40"..baseLabel.."|r"
    end

    return baseLabel
end

local CATALOG_SLOT_LABELS = {
    ["Head"] = "Head",
    ["Shoulder"] = "Shoulders",
    ["Back"] = "Cloak",
    ["Chest"] = "Chest",
    ["Shirt"] = "Shirt",
    ["Tabard"] = "Tabard",
    ["Wrist"] = "Bracers",
    ["Hands"] = "Gloves",
    ["Waist"] = "Belt",
    ["Legs"] = "Legs",
    ["Feet"] = "Boots",
    ["Main Hand"] = "Main Hand",
    ["Off-hand"] = "Off-hand",
    ["Ranged"] = "Ranged",
}

local function getCatalogSetMissingSlots(setData)
    if type(setData) ~= "table" then
        return {}
    end

    local missing = {}
    for index, slotInfo in ipairs(SLOT_DATA) do
        local fullItemId = type(setData.fullItems) == "table" and tonumber(setData.fullItems[index]) or 0
        local unlockedItemId = type(setData.unlockedItems) == "table" and tonumber(setData.unlockedItems[index]) or 0

        if fullItemId > 0 and unlockedItemId <= 0 then
            missing[#missing + 1] = CATALOG_SLOT_LABELS[slotInfo.name] or slotInfo.name
        end
    end

    return missing
end

local function renderSetPreviewModelItems(model, itemIds)
    updateSetPreviewBackground()
    model:Reset()
    setStaticTransmogModelView(model)
    model:Undress()

    local retryItems = {}
    for index = 1, #SLOT_DATA do
        local itemId = type(itemIds) == "table" and tonumber(itemIds[index]) or nil
        if itemId and itemId > 0 and getItemPreviewLevelEligibility(itemId) == true then
            model:TryOn(itemId)
            retryItems[SLOT_DATA[index].name] = itemId
        end
    end

    for _, slotName in ipairs(SET_PREVIEW_RETRY_SLOT_ORDER) do
        local itemId = retryItems[slotName]
        if itemId and itemId > 0 then
            model:TryOn(itemId)
        end
    end

    if model.shadowformEnabled then
        model:EnableShadowform()
    end
end

state.cancelSetPreviewModelQueries = function(model)
    if not model then
        return
    end

    model.setPreviewToken = (model.setPreviewToken or 0) + 1
    for itemId, handle in pairs(model._appearanceBuddyItemQueryHandles or {}) do
        if handle and handle ~= true and handle.Cancel then
            handle:Cancel()
        end
        model._appearanceBuddyItemQueryHandles[itemId] = nil
    end
end

local function setPreviewModelItems(model, itemIds)
    local normalizedItems = {}
    local signatureParts = {}
    local pendingItemIds = {}
    local pendingItemList = {}
    local pendingItemIndexes = {}

    for index = 1, #SLOT_DATA do
        local itemId = type(itemIds) == "table" and tonumber(itemIds[index]) or 0
        if itemId and itemId > 0 then
            signatureParts[index] = tostring(itemId)
            local levelEligible = getItemPreviewLevelEligibility(itemId)
            if levelEligible == true then
                normalizedItems[index] = itemId
            else
                normalizedItems[index] = 0
            end
            if levelEligible == nil then
                if not pendingItemIds[itemId] then
                    pendingItemIds[itemId] = true
                    pendingItemList[#pendingItemList + 1] = itemId
                    pendingItemIndexes[itemId] = {}
                end
                pendingItemIndexes[itemId][#pendingItemIndexes[itemId] + 1] = index
            end
        else
            normalizedItems[index] = 0
            signatureParts[index] = "0"
        end
    end

    -- The same saved set must be reconsidered when the player gains a level.
    signatureParts[#SLOT_DATA + 1] = "level:"..tostring(getPlayerAppearancePreviewLevel() or 0)
    local signature = table.concat(signatureParts, ":")
    if model._appearanceBuddyPreviewSignature == signature then
        return
    end

    state.cancelSetPreviewModelQueries(model)
    model._appearanceBuddyPreviewSignature = signature
    model._appearanceBuddyItemQueryHandles = model._appearanceBuddyItemQueryHandles or {}
    local token = model.setPreviewToken
    local pendingCount = #pendingItemList
    local initialRenderComplete = false
    local finalRenderComplete = false

    local function itemQueryFinished(queriedItemId, success)
        queriedItemId = tonumber(queriedItemId) or 0
        if not model or model.setPreviewToken ~= token or not pendingItemIds[queriedItemId] then
            return
        end

        if success and getItemPreviewLevelEligibility(queriedItemId) == true then
            for _, index in ipairs(pendingItemIndexes[queriedItemId] or {}) do
                normalizedItems[index] = queriedItemId
            end
        end
        pendingItemIds[queriedItemId] = nil
        pendingItemIndexes[queriedItemId] = nil
        model._appearanceBuddyItemQueryHandles[queriedItemId] = nil
        pendingCount = pendingCount - 1
        if initialRenderComplete and pendingCount == 0 and not finalRenderComplete
            and (not model.IsVisible or model:IsVisible()) then
            finalRenderComplete = true
            renderSetPreviewModelItems(model, normalizedItems)
        end
    end

    for _, itemId in ipairs(pendingItemList) do
        model._appearanceBuddyItemQueryHandles[itemId] = true
        local handle = ns.QueryItem(itemId, function(queriedItemId, success)
            itemQueryFinished(queriedItemId, success)
        end)
        if handle and model._appearanceBuddyItemQueryHandles[itemId] then
            model._appearanceBuddyItemQueryHandles[itemId] = handle
        end
    end

    initialRenderComplete = true
    renderSetPreviewModelItems(model, normalizedItems)
end

state.onSetsFrameHidden = function(self)
    state.cancelSetPreviewModelQueries(self.previewModel)
    self.previewModel._appearanceBuddyPreviewSignature = nil
    if self.previewModel.StopCameraMotion then
        self.previewModel:StopCameraMotion()
    end
    self.previewModel:ClearModel()
    state.cancelSetListIconQueries(self.list)
    state.itemSetDetailRequests = {}
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

state.setUIController.requestCatalogSetDetails = function(catalogSet, retryCount)
    local itemSetId = catalogSet and tonumber(catalogSet.id)
    if not itemSetId or not state.enabled or not isCatalogSetViewVisible() then
        return nil
    end

    local cachedDetails = state.itemSetDetailsById[itemSetId]
    if cachedDetails then
        return cachedDetails
    end

    if state.itemSetDetailRequests[itemSetId] then
        return nil
    end

    if state.itemSetDetailFailures[itemSetId] then
        return nil
    end

    state.itemSetDetailRequestToken = state.itemSetDetailRequestToken + 1
    local token = state.itemSetDetailRequestToken
    state.itemSetDetailRequests[itemSetId] = {
        token = token,
        startedAt = GetTime and GetTime() or 0,
        retryCount = math.max(0, tonumber(retryCount) or 0),
    }
    if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
    AIO.Handle("Transmog", "GetUnlockedItemSetDetails", itemSetId, token)

    return nil
end

updateSetButtons = function()
    local setsFrame = transmogTab.setsFrame
    if not setsFrame then return end
    local hasSelection = false
    local applyLocked = state.applyingAppearanceSet
        or state.applyingUnlockedItemSet
        or state.itemSetCatalogRequestPending
        or not isServerStateReady()
        or (tonumber(state.setPreviewCost) or 0) > (tonumber(state.money) or 0)

    if state.setSource == SET_SOURCE_SAVED then
        hasSelection = state.setUIController.getSelectedSavedSet() ~= nil
        setsFrame.listTitle:SetText("Saved Transmog Sets")
        setsFrame.buttonSourceSaved:LockHighlight()
        setsFrame.buttonSourceCatalog:UnlockHighlight()
        setsFrame.buttonCopyCurrent:Show()
        setsFrame.buttonRefreshCatalog:Hide()
        setsFrame.buttonLoadMore:Hide()
        setsFrame.buttonRemoveSaved:Show()
        setsFrame.buttonApplySelected:SetText("Apply Set")
        if hasSelection then
            setsFrame.buttonRemoveSaved:Enable()
        else
            setsFrame.buttonRemoveSaved:Disable()
        end
        if isServerStateReady() and not state.isPreviewMutationLocked() then
            setsFrame.buttonCopyCurrent:Enable()
        else
            setsFrame.buttonCopyCurrent:Disable()
        end
    else
        local selectedSet = state.setUIController.getSelectedCatalogSet()
        local selectedId = selectedSet and tonumber(selectedSet.id) or nil
        local details = selectedId and state.itemSetDetailsById[selectedId] or nil
        if not details and selectedSet and type(selectedSet.fullItems) == "table" then
            details = selectedSet
        end
        hasSelection = selectedSet ~= nil and details ~= nil
        if state.itemSetCatalogTotal > 0 then
            setsFrame.listTitle:SetText(("Unlocked Item Sets (%d/%d)"):format(
                #state.itemSetCatalog,
                state.itemSetCatalogTotal
            ))
        else
            setsFrame.listTitle:SetText("Unlocked Item Sets")
        end
        setsFrame.buttonSourceSaved:UnlockHighlight()
        setsFrame.buttonSourceCatalog:LockHighlight()
        setsFrame.buttonCopyCurrent:Hide()
        setsFrame.buttonRemoveSaved:Hide()
        setsFrame.buttonRefreshCatalog:Show()
        setsFrame.buttonRefreshCatalog:SetText(state.itemSetCatalogDirty and "Refresh*" or "Refresh")
        if state.enabled and not state.itemSetCatalogRequestPending then
            setsFrame.buttonRefreshCatalog:Enable()
        else
            setsFrame.buttonRefreshCatalog:Disable()
        end
        if state.itemSetCatalogHasMore
            or (state.itemSetCatalogRequestPending and state.itemSetCatalogRequestPage > 1) then
            setsFrame.buttonLoadMore:Show()
            setsFrame.buttonLoadMore:SetText(state.itemSetCatalogRequestPending and "Loading" or "More")
            if state.itemSetCatalogHasMore and not state.itemSetCatalogRequestPending then
                setsFrame.buttonLoadMore:Enable()
            else
                setsFrame.buttonLoadMore:Disable()
            end
        else
            setsFrame.buttonLoadMore:Hide()
        end
        setsFrame.buttonApplySelected:SetText("Apply Unlocked")
    end

    if state.enabled and hasSelection and not applyLocked then
        setsFrame.buttonApplySelected:Enable()
    else
        setsFrame.buttonApplySelected:Disable()
    end
end

updateSetPreview = function()
    local setsFrame = transmogTab.setsFrame
    if not setsFrame or not setsFrame:IsVisible() or not isTransmogTabVisible() then return end
    updateSetPreviewBackground()
    state.setPreviewCost = 0
    if updateCostDisplay then updateCostDisplay() end

    if state.setSource == SET_SOURCE_SAVED then
        local savedSet = state.setUIController.getSelectedSavedSet()
        if not savedSet then
            setsFrame.previewTitle:SetText("Set Preview")
            setsFrame.previewInfo:SetText("Select a saved transmog set or copy the current preview into a new named set.")
            setsFrame.previewModel._appearanceBuddyPreviewSignature = nil
            setsFrame.previewModel._appearanceBuddyLoadingSetId = nil
            state.cancelSetPreviewModelQueries(setsFrame.previewModel)
            setsFrame.previewModel:Undress()
            return
        end

        local itemCount = 0
        local hiddenCount = 0
        local restoreCount = 0
        for index = 1, #SLOT_DATA do
            local value = tonumber(savedSet.items and savedSet.items[index]) or -1
            if value > 0 then
                itemCount = itemCount + 1
            elseif value == 0 then
                hiddenCount = hiddenCount + 1
            else
                restoreCount = restoreCount + 1
            end
        end

        setPreviewModelItems(setsFrame.previewModel, buildPreviewItemsFromTransmogSet(savedSet.items))
        setsFrame.previewModel._appearanceBuddyLoadingSetId = nil
        setsFrame.previewTitle:SetText(savedSet.name)
        setsFrame.previewInfo:SetText(("Saved transmog set\nCustom appearances: %d  |  Hidden: %d  |  Restore: %d"):format(itemCount, hiddenCount, restoreCount))
        state.setPreviewCost = getAppearanceSetCost(savedSet.items, savedSet.weaponEnchants)
        if updateCostDisplay then updateCostDisplay() end
        updateSetButtons()
    else
        local catalogSet = state.setUIController.getSelectedCatalogSet()
        if not catalogSet then
            setsFrame.previewTitle:SetText("Set Preview")
            if state.itemSetCatalogRequestPending then
                setsFrame.previewInfo:SetText("Fetching unlocked item sets...")
            elseif not state.itemSetCatalogLoaded then
                setsFrame.previewInfo:SetText("Automatic catalog scanning is disabled.\nClick Refresh to load unlocked item sets.")
            elseif #state.itemSetCatalog == 0 then
                setsFrame.previewInfo:SetText("No unlocked item sets are cached for this account.\nClick Refresh after unlocking additional appearance items.")
            else
                setsFrame.previewInfo:SetText("Select an unlocked item set to preview the full look. Applying it will use only the pieces your account has unlocked.")
            end
            setsFrame.previewModel._appearanceBuddyPreviewSignature = nil
            setsFrame.previewModel._appearanceBuddyLoadingSetId = nil
            state.cancelSetPreviewModelQueries(setsFrame.previewModel)
            setsFrame.previewModel:Undress()
            return
        end

        local itemSetId = tonumber(catalogSet.id)
        local details = itemSetId and state.itemSetDetailsById[itemSetId] or nil
        -- Supports an older server during the client/server transition.
        if not details and type(catalogSet.fullItems) == "table" then
            details = catalogSet
        end

        setsFrame.previewTitle:SetText(catalogSet.name or "Unlocked Item Set")
        if not details then
            if itemSetId and state.itemSetDetailFailures[itemSetId] then
                setsFrame.previewInfo:SetText("This set's appearance data did not arrive.\nSelect the set again to retry.")
            else
                state.setUIController.requestCatalogSetDetails(catalogSet)
                setsFrame.previewInfo:SetText("Loading this set's appearance data...")
            end
            if setsFrame.previewModel._appearanceBuddyLoadingSetId ~= itemSetId then
                setsFrame.previewModel._appearanceBuddyPreviewSignature = nil
                setsFrame.previewModel._appearanceBuddyLoadingSetId = itemSetId
                state.cancelSetPreviewModelQueries(setsFrame.previewModel)
                setsFrame.previewModel:Undress()
            end
            return
        end

        setsFrame.previewModel._appearanceBuddyLoadingSetId = nil
        setPreviewModelItems(setsFrame.previewModel, details.fullItems)
        local infoLines = {
            ("Unlocked pieces: %d/%d"):format(tonumber(catalogSet.unlockedCount) or 0, tonumber(catalogSet.totalCount) or 0)
        }
        local missingSlots = getCatalogSetMissingSlots(details)
        if #missingSlots > 0 then
            infoLines[#infoLines + 1] = "Missing: "..table.concat(missingSlots, ", ")
        end
        infoLines[#infoLines + 1] = "Preview hides non-set slots. Apply uses only unlocked appearances."
        setsFrame.previewInfo:SetText(table.concat(infoLines, "\n"))
        state.setPreviewCost = getAppearanceSetCost(buildCatalogSetCostItems(details), nil)
        if updateCostDisplay then updateCostDisplay() end
        updateSetButtons()
    end
end

local function getSetListRevision()
    if state.setSource == SET_SOURCE_SAVED then
        return state.savedSetRevision
    end

    return state.itemSetCatalogRevision
end

local function getSetListSelectionValue()
    if state.setSource == SET_SOURCE_SAVED then
        return state.selectedSavedSetName
    end

    return tonumber(state.selectedCatalogSetId)
end

local function setSetListSelectionValue(value)
    if state.setSource == SET_SOURCE_SAVED then
        state.selectedSavedSetName = value
    else
        state.selectedCatalogSetId = tonumber(value)
    end
end

local function buttonMatchesSetListSelection(button, value)
    if not button or value == nil then
        return false
    end

    if state.setSource == SET_SOURCE_SAVED then
        return button.setName == value
    end

    return tonumber(button.itemSetId) == tonumber(value)
end

local function syncSetListSelection(listFrame)
    local selectionValue = getSetListSelectionValue()
    local currentButton = listFrame:GetButton(listFrame:GetSelected() or 0)
    if buttonMatchesSetListSelection(currentButton, selectionValue) then
        return true
    end

    local wasRebuilding = listFrame._appearanceBuddyRebuilding
    listFrame._appearanceBuddyRebuilding = true
    listFrame:Deselect()

    local matched = false
    if selectionValue ~= nil then
        for index = 1, listFrame:GetSize() do
            local button = listFrame:GetButton(index)
            if buttonMatchesSetListSelection(button, selectionValue) then
                listFrame:Select(index)
                matched = true
                break
            end
        end
    end

    listFrame._appearanceBuddyRebuilding = wasRebuilding
    if not matched and selectionValue ~= nil then
        setSetListSelectionValue(nil)
    end

    return matched
end

local function textMatchesSetSearch(value, query)
    if query == "" then
        return true
    end
    return string.find(string.lower(tostring(value or "")), query, 1, true) ~= nil
end

local function savedSetMatchesSearch(setData, query)
    return textMatchesSetSearch(setData and setData.name, query)
end

local function catalogSetMatchesSearch(setData, query)
    return textMatchesSetSearch(setData and setData.displayName, query)
        or textMatchesSetSearch(setData and setData.name, query)
        or textMatchesSetSearch(setData and setData.id, query)
end

rebuildSetLists = function(force)
    local setsFrame = transmogTab.setsFrame
    if not setsFrame or not setsFrame:IsVisible() or not isTransmogTabVisible() then return false end
    local listFrame = setsFrame.list
    local revision = getSetListRevision()
    local searchText = trim(state.setSearchBySource[state.setSource] or "")
    local searchQuery = string.lower(searchText)
    local sourceChanged = listFrame._appearanceBuddySource ~= state.setSource
    local searchChanged = listFrame._appearanceBuddySearch ~= searchQuery

    if not force
        and listFrame._appearanceBuddySource == state.setSource
        and listFrame._appearanceBuddyRevision == revision
        and listFrame._appearanceBuddySearch == searchQuery then
        syncSetListSelection(listFrame)
        updateSetButtons()
        updateSetPreview()
        return false
    end

    listFrame._appearanceBuddyRebuilding = true
    listFrame:BeginBatch()
    listFrame:Clear()
    local visibleCount = 0

    if state.setSource == SET_SOURCE_SAVED then
        sortSavedTransmogSets()
        for _, setData in ipairs(getSavedTransmogSets()) do
            if savedSetMatchesSearch(setData, searchQuery) then
                visibleCount = visibleCount + 1
                local buttonId = listFrame:AddItem(setData.name)
                local button = listFrame:GetButton(buttonId)
                button.setName = setData.name
                button.savedSet = setData
                button.itemSetId = nil
                button.fullLabelText = setData.name
                ensureSetListButtonTooltip(button)
                setSetListButtonIcon(button, getSetListIconItemId(setData))
                if button.subtitle then button.subtitle:SetText("Saved outfit") end
            end
        end
    else
        for _, setData in ipairs(state.itemSetCatalog) do
            if catalogSetMatchesSearch(setData, searchQuery) then
                visibleCount = visibleCount + 1
                local buttonId = listFrame:AddItem(getCatalogSetRowLabel(setData))
                local button = listFrame:GetButton(buttonId)
                button.setName = nil
                button.savedSet = nil
                button.itemSetId = tonumber(setData.id)
                button.fullLabelText = tostring(setData.displayName or setData.name or "Set")
                ensureSetListButtonTooltip(button)
                setSetListButtonIcon(button, getSetListIconItemId(setData), false)
                if button.subtitle then button.subtitle:SetText(isCatalogSetComplete(setData) and "Unlocked set" or "Collection set") end
            end
        end
    end

    listFrame:EndBatch()
    listFrame._appearanceBuddySource = state.setSource
    listFrame._appearanceBuddyRevision = revision
    listFrame._appearanceBuddySearch = searchQuery
    if visibleCount == 0 then
        if state.setSource == SET_SOURCE_SAVED then
            setsFrame.emptyText:SetText(searchText ~= "" and "No saved sets match your search." or "No saved outfits yet.")
        elseif state.itemSetCatalogRequestPending then
            setsFrame.emptyText:SetText("Loading item sets...")
        elseif not state.itemSetCatalogLoaded then
            setsFrame.emptyText:SetText("Catalog not loaded. Click Refresh.")
        else
            setsFrame.emptyText:SetText(searchText ~= "" and "No catalog sets match your search." or "No item sets available.")
        end
        setsFrame.emptyText:Show()
    else
        setsFrame.emptyText:Hide()
    end
    setsFrame.listScroll:UpdateScrollChildRect()
    do
        local maxScroll = math.max(0, (listFrame:GetHeight() or 0) - (setsFrame.listScroll:GetHeight() or 0))
        local currentScroll = 0
        if not sourceChanged and not searchChanged and not state.resetSetListScroll then
            currentScroll = setsFrame.listScroll:GetVerticalScroll() or 0
        end
        if currentScroll > maxScroll then
            currentScroll = maxScroll
        end
        if currentScroll < 0 then
            currentScroll = 0
        end
        setsFrame.listScroll:SetVerticalScroll(currentScroll)
        state.resetSetListScroll = false
    end
    if ns.RefreshManagedScrollFrame then
        ns.RefreshManagedScrollFrame(setsFrame.listScroll)
    end

    syncSetListSelection(listFrame)
    listFrame._appearanceBuddyRebuilding = false

    if state.setSource == SET_SOURCE_SAVED and rebuildSidebarSets then rebuildSidebarSets() end
    updateSetButtons()
    updateSetPreview()
    return true
end

state.onSetListSelect = function(self, id)
    if self._appearanceBuddyRebuilding then
        return
    end

    local button = self:GetButton(id)
    if state.setSource == SET_SOURCE_SAVED then
        state.selectedSavedSetName = button and button.setName or nil
    else
        state.selectedCatalogSetId = button and tonumber(button.itemSetId) or nil
        if state.selectedCatalogSetId then
            state.itemSetDetailFailures[state.selectedCatalogSetId] = nil
        end
    end

    if button and button.catalogIconItemId then
        setSetListButtonIcon(button, button.catalogIconItemId, true)
    end

    updateSetButtons()
    updateSetPreview()
end

local function saveCurrentPreviewAsNamedSet(name)
    if state.isPreviewMutationLocked() then
        return
    end
    name = trim(name)
    if name == "" then
        return
    end

    local savedSets = getSavedTransmogSets()
    local snapshot = snapshotCurrentTransmogSet()
    local weaponEnchants = snapshotCurrentWeaponEnchants()
    local existing = nil
    local normalizedName = string.lower(name)

    for index, setData in ipairs(savedSets) do
        if string.lower(tostring(setData.name or "")) == normalizedName then
            existing = index
            break
        end
    end

    local selectedName = name
    if existing then
        savedSets[existing].items = snapshot
        savedSets[existing].weaponEnchants = weaponEnchants
        selectedName = savedSets[existing].name
    else
        if #savedSets >= ns.MAX_SAVED_TRANSMOG_SETS then
            local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
            if chatFrame then
                chatFrame:AddMessage(("|ccff6ff98<Appearance Buddy>|r: saved-set limit reached (%d). Remove a set before saving another."):format(ns.MAX_SAVED_TRANSMOG_SETS))
            end
            return false
        end
        table.insert(savedSets, {
            name = name,
            items = snapshot,
            weaponEnchants = weaponEnchants,
        })
    end

    state.savedSetRevision = state.savedSetRevision + 1
    state.setSource = SET_SOURCE_SAVED
    state.selectedSavedSetName = selectedName
    rebuildSetLists()
    updateSetButtons()
    updateSetPreview()
    return true
end

local function restoreSavedSetPopupEditHandler(popup)
    if popup and popup.appearanceBuddySetNameHandlerActive and popup.wideEditBox then
        popup.wideEditBox:SetScript("OnTextChanged", popup.originalOnChange)
        popup.originalOnChange = nil
        popup.appearanceBuddySetNameHandlerActive = nil
    end
end

state.setUIController.showSaveCurrentSetDialog = function()
    if state.isPreviewMutationLocked() then
        SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: wait for the current appearance change to finish before saving a transmog set.")
        return
    end
    if not isServerStateReady() then
        SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: wait for transmog data to finish syncing before saving a transmog set.")
        return
    end

    StaticPopupDialogs["APPEARANCE_BUDDY_TRANSMOG_SET_SAVE_DIALOG"] = {
        text = "Enter transmog set name:",
        button1 = "Save",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        hasEditBox = true,
        hasWideEditBox = true,
        maxLetters = 50,
        preferredIndex = 3,
        OnShow = function(self)
            restoreSavedSetPopupEditHandler(self)
            self.button1:Disable()
            self.wideEditBox:SetText("")
            self.originalOnChange = self.wideEditBox:GetScript("OnTextChanged")
            self.appearanceBuddySetNameHandlerActive = true
            self.wideEditBox:SetScript("OnTextChanged", function(editBox, ...)
                local text = trim(editBox:GetText())
                if text == "" then
                    self.button1:Disable()
                else
                    self.button1:Enable()
                end
                if self.originalOnChange then
                    self.originalOnChange(editBox, ...)
                end
            end)
        end,
        OnAccept = function(self)
            local enteredName = trim(self.wideEditBox:GetText())
            restoreSavedSetPopupEditHandler(self)
            saveCurrentPreviewAsNamedSet(enteredName)
        end,
        OnCancel = function(self)
            restoreSavedSetPopupEditHandler(self)
        end,
        OnHide = function(self)
            restoreSavedSetPopupEditHandler(self)
        end,
    }

    StaticPopup_Show("APPEARANCE_BUDDY_TRANSMOG_SET_SAVE_DIALOG")
end

local function removeSavedSet(savedSet)
    if type(savedSet) ~= "table" then return false end

    local savedSets = getSavedTransmogSets()
    local wasSelected = state.setUIController.getSelectedSavedSet() == savedSet
    local removed = false
    for index, setData in ipairs(savedSets) do
        if setData == savedSet then
            table.remove(savedSets, index)
            removed = true
            break
        end
    end

    if removed then
        state.savedSetRevision = state.savedSetRevision + 1
    end
    if wasSelected then
        state.selectedSavedSetName = nil
    end
    if removed then
        rebuildSetLists(true)
        if rebuildSidebarSets then rebuildSidebarSets(true) end
    end
    return removed
end

StaticPopupDialogs["APPEARANCE_BUDDY_REMOVE_SAVED_SET_CONFIRM"] = {
    text = "Permanently remove saved set %s?\n\nThis cannot be undone.",
    button1 = "Remove",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        data = data or self.data
        if type(data) == "table" and removeSavedSet(data.savedSet) then
            PlaySound("gsTitleOptionOK")
        end
    end,
}

state.setUIController.showSavedSetRemovalConfirmation = function(savedSet)
    if type(savedSet) ~= "table" then return end
    local setName = tostring(savedSet.name or "")
    if setName == "" then return end

    StaticPopup_Show("APPEARANCE_BUDDY_REMOVE_SAVED_SET_CONFIRM", setName, nil, {
        savedSet = savedSet,
    })
end

state.setUIController.updateViewMode = function()
    local isItems = state.viewMode == "items"

    state.setUIController.updateModeButtons()
    state.setUIController.setItemModeVisible(isItems)

    if isItems then
        local setsFrame = transmogTab.setsFrame
        if setsFrame then
            setsFrame:Hide()
            if ns.RefreshManagedScrollFrame then
                ns.RefreshManagedScrollFrame(setsFrame.listScroll, false)
            end
        end
        transmogTab.buttonApply:Show()
        if state.enchantingEquipSlot then
            transmogTab.buttonHide:Hide()
        else
            transmogTab.buttonHide:Show()
        end
        transmogTab.buttonRestore:Show()
        transmogTab.buttonRevert:Show()
        transmogTab.buttonRevertAll:Show()
        transmogTab.buttonApplyAll:Show()
        if not state.enabled then
            showListMessage(state.disabledReason or "Transmog is unavailable.")
        else
            loadCurrentSlotItems()
        end
        updateActionButtons()
    else
        state.cancelAppearancePageActivity()
        state.cancelPageLookupActivity()
        local setsFrame = state.ensureSetsUI()
        transmogTab.buttonRevert:Hide()
        transmogTab.buttonRevertAll:Hide()
        transmogTab.buttonApplyAll:Hide()
        setsFrame:Show()
        if setsFrame.CancelSearchDebounce then
            setsFrame:CancelSearchDebounce()
        end
        if setsFrame.SyncSearchBox then
            setsFrame:SyncSearchBox()
        end
        if ns.RefreshManagedScrollFrame then
            ns.RefreshManagedScrollFrame(setsFrame.listScroll)
        end
        rebuildSetLists()
        if state.setSource == SET_SOURCE_CATALOG and state.enabled then
            refreshItemSetCatalogIfNeeded(false)
        end
    end
end

state.setUIController.setSetSource = function(source)
    if source ~= SET_SOURCE_SAVED and source ~= SET_SOURCE_CATALOG then
        return
    end

    if state.setSource == SET_SOURCE_CATALOG and source ~= SET_SOURCE_CATALOG then
        state.itemSetDetailRequests = {}
    end
    state.setSource = source
    local setsFrame = state.ensureSetsUI()
    if setsFrame.CancelSearchDebounce then
        setsFrame:CancelSearchDebounce()
    end
    if setsFrame.SyncSearchBox then
        setsFrame:SyncSearchBox()
    end
    rebuildSetLists()
    state.setUIController.updateModeButtons()

    if source == SET_SOURCE_CATALOG and state.enabled then
        refreshItemSetCatalogIfNeeded(false)
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

end

-- Persistent saved-look rail.  It is intentionally a second view of the
-- existing saved-set data, not a parallel data store: selecting a row opens
-- that exact set in the original Sets workflow.
do
    local sidebar = mainFrame.sidebar
    if sidebar then
        transmogTab.sidebar = sidebar
        sidebar.currentGear = CreateFrame("Button", transmogTabName.."SidebarCurrentGear", sidebar, "UIPanelButtonTemplate2")
        sidebar.currentGear:SetPoint("TOPLEFT", 8, -8)
        sidebar.currentGear:SetPoint("TOPRIGHT", -8, -8)
        sidebar.currentGear:SetHeight(28)
        sidebar.currentGear:SetText("Show currently equipped gear")
        if ns.Theme then ns.Theme.SkinButton(sidebar.currentGear) end
        sidebar.currentGear.icon = sidebar.currentGear:CreateTexture(nil, "ARTWORK")
        sidebar.currentGear.icon:SetPoint("LEFT", sidebar.currentGear, "LEFT", 7, 0)
        sidebar.currentGear.icon:SetSize(18, 18)
        sidebar.currentGear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        sidebar.RefreshCurrentGearIcon = function(self)
            local texture = type(GetInventoryItemTexture) == "function" and GetInventoryItemTexture("player", 5)
            self.currentGear.icon:SetTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest")
        end
        sidebar:RefreshCurrentGearIcon()
        local currentGearLabel = sidebar.currentGear:GetFontString()
        if currentGearLabel then
            currentGearLabel:SetFontObject(GameFontNormalSmall)
            local fontPath, fontSize, fontFlags = currentGearLabel:GetFont()
            if fontPath and fontSize then
                currentGearLabel:SetFont(fontPath, math.max(8, fontSize - 1), fontFlags)
            end
            currentGearLabel:ClearAllPoints()
            currentGearLabel:SetPoint("LEFT", sidebar.currentGear, "LEFT", 28, 0)
            currentGearLabel:SetPoint("RIGHT", sidebar.currentGear, "RIGHT", -4, 0)
            currentGearLabel:SetJustifyH("LEFT")
        end
        if ns.Theme then ns.Theme.CreateDivider(sidebar, "TOPLEFT", sidebar, "TOPLEFT", 8, -38, 184, 1) end

        sidebar.listScroll = CreateFrame("ScrollFrame", transmogTabName.."SidebarSetsScroll", sidebar, "UIPanelScrollFrameTemplate")
        sidebar.listScroll:SetPoint("TOPLEFT", 7, -43)
        sidebar.listScroll:SetPoint("BOTTOMRIGHT", -25, 98)
        sidebar.list = ns.CreateListFrame(transmogTabName.."SidebarSetsList", nil, sidebar.listScroll)
        sidebar.list:SetPoint("TOPLEFT", 0, 0)
        sidebar.list:SetWidth(166)
        sidebar.listScroll:SetScrollChild(sidebar.list)

        sidebar.emptyText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sidebar.emptyText:SetPoint("TOPLEFT", sidebar.listScroll, "TOPLEFT", 10, -18)
        sidebar.emptyText:SetPoint("TOPRIGHT", sidebar.listScroll, "TOPRIGHT", -10, -18)
        sidebar.emptyText:SetJustifyH("CENTER")
        sidebar.emptyText:SetText("No saved outfits yet.")
        sidebar.emptyText:SetTextColor(0.52, 0.49, 0.43)

        sidebar.buttonNew = CreateFrame("Button", transmogTabName.."SidebarNewSet", sidebar, "UIPanelButtonTemplate2")
        sidebar.buttonNew:SetPoint("BOTTOMLEFT", 8, 66)
        sidebar.buttonNew:SetPoint("BOTTOMRIGHT", -8, 66)
        sidebar.buttonNew:SetHeight(22)
        sidebar.buttonNew:SetText("New Outfit")
        if ns.Theme then ns.Theme.SkinButton(sidebar.buttonNew) end

        sidebar.buttonSave = CreateFrame("Button", transmogTabName.."SidebarSaveSet", sidebar, "UIPanelButtonTemplate2")
        sidebar.buttonSave:SetPoint("BOTTOMLEFT", 8, 10)
        sidebar.buttonSave:SetWidth(76)
        sidebar.buttonSave:SetHeight(22)
        sidebar.buttonSave:SetText("Save Outfit")
        if ns.Theme then ns.Theme.SkinButton(sidebar.buttonSave) end

        sidebar.costFrame = CreateFrame("Frame", transmogTabName.."SidebarCost", sidebar)
        sidebar.costFrame:SetPoint("BOTTOMRIGHT", -7, 11)
        sidebar.costFrame:SetSize(107, 20)
        sidebar.costFrame.groups = {}

        -- WotLK coinage can reach six gold digits. Reserve that width instead
        -- of letting FontString replace the quoted amount with an ellipsis.
        local coinData = {
            { key = "gold", x = 0, width = 42, icon = "Interface\\MoneyFrame\\UI-GoldIcon" },
            { key = "silver", x = 54, width = 14, icon = "Interface\\MoneyFrame\\UI-SilverIcon" },
            { key = "copper", x = 80, width = 14, icon = "Interface\\MoneyFrame\\UI-CopperIcon" },
        }
        for _, data in ipairs(coinData) do
            local value = sidebar.costFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            value:SetPoint("LEFT", sidebar.costFrame, "LEFT", data.x, 0)
            value:SetWidth(data.width)
            value:SetJustifyH("RIGHT")
            local icon = sidebar.costFrame:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("LEFT", value, "RIGHT", 1, 0)
            icon:SetSize(10, 10)
            icon:SetTexture(data.icon)
            sidebar.costFrame.groups[data.key] = { value = value, icon = icon }
        end

        sidebar.costHit = CreateFrame("Button", nil, sidebar.costFrame)
        sidebar.costHit:SetAllPoints()
        sidebar.costHit:SetScript("OnEnter", function(self)
            local cost = getDisplayedCost()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Transmogrification Cost", 0.84, 0.66, 0.086)
            if not state.costSynced then
                GameTooltip:AddLine("Waiting for the server price quote.", 0.52, 0.49, 0.43, true)
            elseif cost > (tonumber(state.money) or 0) then
                GameTooltip:AddLine("Not enough money.", 0.89, 0.08, 0.10)
            else
                GameTooltip:AddLine("Charged only when Apply Changes succeeds.", 0.52, 0.49, 0.43, true)
            end
            GameTooltip:Show()
        end)
        sidebar.costHit:SetScript("OnLeave", GameTooltip_Hide)

        updateCostDisplay = function()
            if not sidebar.costFrame then return end
            local cost = getDisplayedCost()
            local gold = math.floor(cost / 10000)
            local silver = math.floor((cost % 10000) / 100)
            local copper = cost % 100
            local values = { gold = gold, silver = silver, copper = copper }
            local insufficient = cost > (tonumber(state.money) or 0)
            for key, group in pairs(sidebar.costFrame.groups) do
                group.value:SetText(state.costSynced and (values[key] or 0) or "-")
                if not state.costSynced then
                    group.value:SetTextColor(0.52, 0.49, 0.43)
                elseif insufficient then
                    group.value:SetTextColor(0.89, 0.08, 0.10)
                else
                    group.value:SetTextColor(0.92, 0.89, 0.80)
                end
            end
        end
        updateCostDisplay()

        rebuildSidebarSets = function(force)
            local list = sidebar.list
            if not force and sidebar._appearanceBuddySavedSetRevision == state.savedSetRevision then
                return false
            end

            local selectedName = state.selectedSavedSetName
            list._appearanceBuddyRebuilding = true
            list:BeginBatch()
            list:Clear()
            sortSavedTransmogSets()

            local savedSets = getSavedTransmogSets()
            for index, setData in ipairs(savedSets) do
                local buttonId = list:AddItem(setData.name)
                local button = list:GetButton(buttonId)
                button.setName = setData.name
                button.savedSet = setData
                button.fullLabelText = setData.name
                ensureSetListButtonTooltip(button)
                setSetListButtonIcon(button, getSetListIconItemId(setData))
                if button.subtitle then button.subtitle:SetText("Saved outfit") end
                if selectedName and setData.name == selectedName then
                    button:LockHighlight()
                    if ns.Theme then ns.Theme.SetSelected(button, true) end
                    list.selected = buttonId
                end
            end

            list:EndBatch()
            sidebar._appearanceBuddySavedSetRevision = state.savedSetRevision
            if #savedSets == 0 then sidebar.emptyText:Show() else sidebar.emptyText:Hide() end
            sidebar.listScroll:UpdateScrollChildRect()
            if ns.RefreshManagedScrollFrame then ns.RefreshManagedScrollFrame(sidebar.listScroll) end
            list._appearanceBuddyRebuilding = false
            return true
        end

        sidebar.list.onSelect = function(list, id)
            if list._appearanceBuddyRebuilding then return end
            if state.isPreviewMutationLocked() then
                if rebuildSidebarSets then rebuildSidebarSets(true) end
                return
            end
            local button = list:GetButton(id)
            if not button or not button.setName then return end
            state.selectedSavedSetName = button.setName
            state.setSource = SET_SOURCE_SAVED
            state.viewMode = "items"
            local savedSet = state.setUIController.getSelectedSavedSet()
            if savedSet then
                stageAppearanceSetPreview(savedSet.items, savedSet.weaponEnchants)
            end
            state.setUIController.updateViewMode()
        end

        sidebar.currentGear:SetScript("OnClick", function()
            if state.isPreviewMutationLocked() then return end
            PlaySound("gsTitleOptionOK")
            state.selectedSavedSetName = nil
            state.viewMode = "items"
            revertAllPreview()
            if rebuildSidebarSets then rebuildSidebarSets(true) end
            state.setUIController.updateViewMode()
        end)

        local function openSavedSetEditor()
            state.viewMode = "sets"
            state.setUIController.setSetSource(SET_SOURCE_SAVED)
            state.setUIController.updateViewMode()
        end
        sidebar.buttonNew:SetScript("OnClick", function()
            PlaySound("gsTitleOptionOK")
            openSavedSetEditor()
            state.setUIController.showSaveCurrentSetDialog()
        end)
        sidebar.buttonSave:SetScript("OnClick", function()
            PlaySound("gsTitleOptionOK")
            openSavedSetEditor()
            state.setUIController.showSaveCurrentSetDialog()
        end)
        sidebar:HookScript("OnShow", function()
            -- SavedVariables are available by the first effective show. Build
            -- rows only then, and only when the persisted revision changed.
            if rebuildSidebarSets then rebuildSidebarSets() end
            state.resumeSetListIconQueries(sidebar.list)
        end)
        sidebar:HookScript("OnHide", function()
            state.cancelSetListIconQueries(sidebar.list)
        end)
    end
end

transmogTab.buttonModeItems:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    state.viewMode = "items"
    state.setUIController.updateViewMode()
end)

transmogTab.buttonModeSets:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    state.viewMode = "sets"
    state.setUIController.setSetSource(SET_SOURCE_CATALOG)
    state.setUIController.updateViewMode()
end)

transmogTab.buttonModeCustomSets:SetScript("OnClick", function()
    PlaySound("gsTitleOptionOK")
    state.viewMode = "sets"
    state.setUIController.setSetSource(SET_SOURCE_SAVED)
    state.setUIController.updateViewMode()
end)

local function onSavedSetListRightClick(list, id, button)
    if not IsControlKeyDown() then
        return
    end

    local setButton = button or (list and list:GetButton(id))
    if setButton and setButton.savedSet then
        state.setUIController.showSavedSetRemovalConfirmation(setButton.savedSet)
    end
end

if transmogTab.sidebar and transmogTab.sidebar.list then
    transmogTab.sidebar.list.onRightClick = onSavedSetListRightClick
end

state.bindSetsUIHandlers = function(setsFrame)
    setsFrame:HookScript("OnHide", state.onSetsFrameHidden)
    setsFrame.list.onSelect = state.onSetListSelect
    setsFrame.list.onRightClick = onSavedSetListRightClick

    setsFrame.buttonSourceSaved:SetScript("OnClick", function()
        PlaySound("gsTitleOptionOK")
        state.setUIController.setSetSource(SET_SOURCE_SAVED)
    end)

    setsFrame.buttonSourceCatalog:SetScript("OnClick", function()
        PlaySound("gsTitleOptionOK")
        state.setUIController.setSetSource(SET_SOURCE_CATALOG)
    end)

    setsFrame.buttonCopyCurrent:SetScript("OnClick", function()
        PlaySound("gsTitleOptionOK")
        state.setUIController.showSaveCurrentSetDialog()
    end)

    setsFrame.buttonRemoveSaved:SetScript("OnClick", function()
        if not state.selectedSavedSetName then
            return
        end

        PlaySound("gsTitleOptionOK")
        state.setUIController.showSavedSetRemovalConfirmation(
            state.setUIController.getSelectedSavedSet()
        )
    end)

    setsFrame.buttonRefreshCatalog:SetScript("OnClick", function()
        if not state.enabled then
            return
        end

        PlaySound("gsTitleOptionOK")
        refreshItemSetCatalogIfNeeded(true)
    end)

    setsFrame.buttonApplySelected:SetScript("OnClick", function()
        if state.setSource == SET_SOURCE_SAVED then
            local savedSet = state.setUIController.getSelectedSavedSet()
            if savedSet then
                PlaySound("gsTitleOptionOK")
                applyAppearanceSetAsTransmog(savedSet.items, savedSet.weaponEnchants)
            end
        else
            local catalogSet = state.setUIController.getSelectedCatalogSet()
            if catalogSet then
                PlaySound("gsTitleOptionOK")
                applyUnlockedCatalogSet(catalogSet.id)
            end
        end
    end)
end

local handlers = {}
state.wire = assert(ns.TransmogWire, "AppearanceBuddy transmog wire validators were not loaded")
local getWireValue = state.wire.Value
local getWireInteger = state.wire.Integer

do
    local tooltipEquipmentRefreshFrame = CreateFrame("Frame")

    local function getTooltipEquipmentTime()
        if type(GetTime) ~= "function" then
            return 0
        end
        return tonumber(GetTime()) or 0
    end

    local function stopTooltipEquipmentPolling()
        if tooltipEquipmentRefreshFrame then
            tooltipEquipmentRefreshFrame:SetScript("OnUpdate", nil)
        end
    end

    state.pollTooltipEquipmentState = function()
        local now = getTooltipEquipmentTime()
        if state.tooltipEquipmentRequestPending then
            local startedAt = tonumber(state.tooltipEquipmentRequestStartedAt) or 0
            if now > 0 and startedAt <= 0 then
                state.tooltipEquipmentRequestStartedAt = now
            elseif now > 0 and now - startedAt >= 5 then
                state.tooltipEquipmentRequestPending = false
                state.tooltipEquipmentRequestStartedAt = 0
                state.tooltipEquipmentRetryAt = now + 1
            end
            return
        end

        local retryAt = tonumber(state.tooltipEquipmentRetryAt) or 0
        if retryAt > 0 and now > 0 and now >= retryAt then
            state.tooltipEquipmentRetryAt = 0
            state.requestTooltipEquipmentState()
        elseif retryAt <= 0 then
            stopTooltipEquipmentPolling()
        end
    end

    state.ensureTooltipEquipmentPolling = function()
        if not tooltipEquipmentRefreshFrame or tooltipEquipmentRefreshFrame:GetScript("OnUpdate") then
            return
        end
        tooltipEquipmentRefreshFrame.elapsed = 0
        tooltipEquipmentRefreshFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + (tonumber(elapsed) or 0)
            if self.elapsed < 0.25 then
                return
            end
            self.elapsed = 0
            state.pollTooltipEquipmentState()
        end)
    end

    state.requestTooltipEquipmentState = function()
        if not state.enabled or state.tooltipEquipmentRequestPending then
            return false
        end

        state.tooltipEquipmentRequestToken = state.tooltipEquipmentRequestToken + 1
        state.tooltipEquipmentRequestPending = true
        state.tooltipEquipmentRequestStartedAt = getTooltipEquipmentTime()
        state.tooltipEquipmentRetryAt = 0
        state.ensureTooltipEquipmentPolling()
        AIO.Handle("Transmog", "GetTooltipEquipmentState", state.tooltipEquipmentRequestToken)
        return true
    end

    state.invalidateTooltipEquipmentState = function()
        state.tooltipEquipmentBySlot = {}
        state.tooltipEquipmentRequestToken = state.tooltipEquipmentRequestToken + 1
        state.tooltipEquipmentRequestPending = false
        state.tooltipEquipmentRequestStartedAt = 0
        state.tooltipEquipmentRetryAt = 0
        stopTooltipEquipmentPolling()
    end
end
local getWireBoolean = state.wire.Boolean

state.stageOptionalLoadResult = function(loadSucceeded, errorMessage)
    if loadSucceeded == nil and errorMessage == nil then
        return true, ""
    end

    local succeeded = getWireBoolean(loadSucceeded)
    local message = state.wire.Text(errorMessage, 192, true)
    if succeeded == nil or message == nil then
        return nil
    end
    return succeeded, message
end

state.stageAppearancePageFailureMetadata = function(errorCode, retryAfter)
    if errorCode == nil and retryAfter == nil then
        return "", 0
    end

    local code = state.wire.Text(errorCode, 32, true)
    local delay = state.wire.Number(retryAfter, 0, 60)
    if code == nil or delay == nil
        or (code ~= "" and code ~= APPEARANCE_PAGE_POLICY.rateLimitErrorCode)
        or (code == "" and delay ~= 0) then
        return nil
    end
    return code, delay
end

state.integerArrayIsZero = function(values)
    for index = 1, #values do
        if values[index] ~= 0 then return false end
    end
    return true
end

state.finishAppearancePageFailure = function(message)
    local request = state.appearancePageRequest
    if request then
        TransmogPaging.Fail(state.appearancePager, request.generation)
    end
    state.appearancePageRequest = nil
    state.appearancePageRequestPending = false
    state.appearancePageRequestStartedAt = 0
    state.appearancePageRequestRetryCount = 0
    showListMessage(message ~= "" and message or "Appearance data could not be loaded. Search or change slots to retry.")
    updatePageText()
    updateActionButtons()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

state.finishPageLookupFailure = function(message, shouldFallbackToFirstPage)
    state.pageLookupRequestPending = false
    state.pageLookupRequestStartedAt = 0
    state.pageLookupRequestRetryCount = 0
    state.pageLookupRateLimitRetryAt = 0
    state.pageLookupRateLimitRetryCount = 0
    state.pageLookupSlot = nil
    state.pageLookupAnchor = nil
    state.pageLookupFilter = nil
    state.pageLookupPageSize = nil
    if shouldFallbackToFirstPage and state.enabled and state.viewMode == "items"
        and isTransmogTabVisible() then
        state.currentPage = 1
        if requestCurrentSlotItems(false) then
            return
        end
    end
    showListMessage(message ~= "" and message or "The current appearance could not be located. Change slots to retry.")
    updateActionButtons()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

state.finishStateSyncFailure = function(message)
    state.syncRequestPending = false
    state.syncRequestStartedAt = 0
    state.syncRequestRetryCount = 0
    state.costRequestPending = false
    state.postMutationModelRebindPending = false
    state.postMutationModelRebindRequestToken = 0

    local failureMessage = message ~= "" and message
        or "Transmog state could not be loaded. Close and reopen this window to retry."
    state.syncFailureMessage = failureMessage
    state.itemListInvalidatedBySyncFailure = true
    showListMessage(failureMessage)
    local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if chatFrame then
        chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..failureMessage)
    end
    updateActionButtons()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

handlers.TransmogStateV2Failed = function(player, requestToken, protocolVersion, errorMessage)
    local responseToken, message = state.wire.StateSyncFailure(
        requestToken,
        protocolVersion,
        errorMessage
    )
    if responseToken == nil or not state.syncRequestPending
        or responseToken ~= state.syncRequestToken then
        return
    end

    state.finishStateSyncFailure(message)
end

handlers.TooltipEquipmentState = function(player, requestToken, protocolVersion, itemIds)
    local token = getWireInteger(requestToken, 0, 2147483647)
    local version = getWireInteger(protocolVersion, 1, 1)
    if token == nil or version == nil or not state.tooltipEquipmentRequestPending
        or token ~= state.tooltipEquipmentRequestToken
        or type(itemIds) ~= "table" then
        return
    end

    local staged = {}
    for _, info in ipairs(SLOT_DATA) do
        local itemId = getWireInteger(getWireValue(itemIds, info.slotId), 0, 4294967295)
        if itemId == nil then
            return
        end
        staged[info.slotId] = itemId
    end

    state.tooltipEquipmentBySlot = staged
    state.tooltipEquipmentRequestPending = false
    state.tooltipEquipmentRequestStartedAt = 0
    state.tooltipEquipmentRetryAt = 0
end

handlers.TooltipEquipmentStateFailed = function(player, requestToken, protocolVersion, retryAfter)
    local token = getWireInteger(requestToken, 0, 2147483647)
    local version = getWireInteger(protocolVersion, 1, 1)
    local retrySeconds = state.wire.Number(retryAfter, 0, 5)
    if token == nil or version == nil or retrySeconds == nil
        or not state.tooltipEquipmentRequestPending
        or token ~= state.tooltipEquipmentRequestToken then
        return
    end

    local now = type(GetTime) == "function" and (tonumber(GetTime()) or 0) or 0
    state.tooltipEquipmentRequestPending = false
    state.tooltipEquipmentRequestStartedAt = 0
    state.tooltipEquipmentRetryAt = now > 0 and now + math.max(0.25, retrySeconds) or 0
    state.ensureTooltipEquipmentPolling()
end

handlers.TransmogStateV2 = function(player, requestToken, protocolVersion, slots, enchants, eligibleSlots, explicitNoSlots, slotCosts, money)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    if not state.syncRequestPending
        or responseToken ~= state.syncRequestToken
        or getWireInteger(protocolVersion, 2, 2) ~= 2
        or type(slots) ~= "table"
        or type(enchants) ~= "table"
        or type(eligibleSlots) ~= "table"
        or type(explicitNoSlots) ~= "table"
        or type(slotCosts) ~= "table" then
        return
    end

    local shouldRebindPostMutationModels = state.postMutationModelRebindPending
        and responseToken == state.postMutationModelRebindRequestToken

    local isFirstSnapshot = not state.hasServerSnapshot
    local previousCurrentSlot = state.currentSlot
    local previousCurrentServerState = state.server[previousCurrentSlot]
    local stagedServer = {}
    local initialSlots = {}
    local stagedCosts = {}
    for _, info in ipairs(SLOT_DATA) do
        local record = getWireValue(slots, info.slotId)
        local mode, normalizedItem, realItemId = state.wire.TransmogSlotState(record)
        if not mode then return end

        local previousServerState = state.server[info.name]
        local previewState = state.preview[info.name]
        initialSlots[info.name] = previewState
            and previewState.mode == "restore"
            and previewState.itemId == nil
            and previewState.effectiveId == nil
            and previousServerState
            and previousServerState.itemId == nil
            and previousServerState.realItemId == nil

        stagedServer[info.name] = normalizeServerState(normalizedItem, realItemId)

        local quotedCost = getWireInteger(getWireValue(slotCosts, info.slotId), 0, 2147483647)
        if quotedCost == nil then return end
        stagedCosts[info.name] = quotedCost
    end

    local stagedEnchants = {}
    local stagedExplicitNo = {}
    local stagedEligible = {}
    for _, equipSlot in ipairs({15, 16, 17}) do
        local enchantId = getWireInteger(getWireValue(enchants, equipSlot), 0, 65535)
        local eligible = getWireBoolean(getWireValue(eligibleSlots, equipSlot))
        local explicitNo = getWireBoolean(getWireValue(explicitNoSlots, equipSlot))
        if enchantId == nil or not WEAPON_ENCHANT_OPTION_BY_ID[enchantId]
            or eligible == nil or explicitNo == nil or (explicitNo and enchantId ~= 0) then
            return
        end
        stagedEnchants[equipSlot] = enchantId
        stagedEligible[equipSlot] = eligible
        stagedExplicitNo[equipSlot] = explicitNo
    end

    local stagedMoney = getWireInteger(money, 0, 4294967295)
    if stagedMoney == nil then return end

    local hadWeaponEnchantState = state.weaponEnchantSynced
    state.server = stagedServer
    state.tooltipEquipmentBySlot = {}
    for _, info in ipairs(SLOT_DATA) do
        state.tooltipEquipmentBySlot[info.slotId] = stagedServer[info.name].realItemId
    end
    state.tooltipEquipmentRequestPending = false
    state.tooltipEquipmentRequestStartedAt = 0
    state.tooltipEquipmentRetryAt = 0
    state.slotCosts = stagedCosts
    state.money = stagedMoney
    for _, equipSlot in ipairs({15, 16, 17}) do
        state.weaponEnchantServer[equipSlot] = stagedEnchants[equipSlot]
        state.weaponEnchantEligible[equipSlot] = stagedEligible[equipSlot]
        state.weaponEnchantExplicitNoServer[equipSlot] = stagedExplicitNo[equipSlot]
    end

    for _, info in ipairs(SLOT_DATA) do
        local serverState = state.server[info.name]
        local hasEquippedItem = (tonumber(serverState.realItemId) or 0) > 0
        if not hasEquippedItem or initialSlots[info.name]
            or state.isPreviewMutationLocked() or not isSlotDirty(info.name) then
            copyServerToPreview(info.name)
        elseif state.preview[info.name].mode == "restore" then
            state.preview[info.name].effectiveId = serverState.realItemId
        elseif state.preview[info.name].mode == "item"
            and serverState.realItemId
            and state.preview[info.name].itemId == serverState.realItemId then
            setPreviewToRestore(info.name)
        end
    end
    for _, equipSlot in ipairs({15, 16, 17}) do
        if not hadWeaponEnchantState or state.isPreviewMutationLocked() or not isWeaponEnchantDirty(equipSlot) then
            copyWeaponEnchantServerToPreview(equipSlot)
        end
    end

    state.synced = true
    state.weaponEnchantSynced = true
    state.costSynced = true
    state.hasServerSnapshot = true
    state.syncFailureMessage = nil
    state.costRequestPending = false
    state.syncRequestPending = false
    state.syncRequestStartedAt = 0
    state.syncRequestRetryCount = 0

    local currentServerState = state.server[state.currentSlot]
    if isFirstSnapshot
        and (not currentServerState or (tonumber(currentServerState.realItemId) or 0) <= 0) then
        for _, info in ipairs(SLOT_DATA) do
            if (tonumber(state.server[info.name].realItemId) or 0) > 0 then
                selectSlot(info.name)
                break
            end
        end
    end

    currentServerState = state.server[state.currentSlot]
    local previousItemId = previousCurrentServerState and tonumber(previousCurrentServerState.itemId)
    local currentItemId = currentServerState and tonumber(currentServerState.itemId)
    local previousRealItemId = previousCurrentServerState and tonumber(previousCurrentServerState.realItemId) or 0
    local currentRealItemId = currentServerState and tonumber(currentServerState.realItemId) or 0
    local itemListNeedsReload = isFirstSnapshot
        or state.itemListInvalidatedBySyncFailure
        or state.appearanceLevelChanged
        or state.currentSlot ~= previousCurrentSlot
        or previousItemId ~= currentItemId
        or previousRealItemId ~= currentRealItemId
    state.appearanceLevelChanged = false

    refreshAllSlotButtons()
    if refreshWeaponEnchantButtons then refreshWeaponEnchantButtons() end
    if refreshWeaponEnchantPicker then refreshWeaponEnchantPicker() end
    if mainFrame:IsShown() then updatePreviewModel() end
    updateActionButtons()
    if isTransmogTabVisible() then
        if state.viewMode == "items" then
            if itemListNeedsReload then
                loadCurrentSlotItems()
            else
                updateListSelection()
            end
        else
            updateSetPreview()
            updateSetButtons()
        end
    end
    if shouldRebindPostMutationModels then
        state.postMutationModelRebindPending = false
        state.postMutationModelRebindRequestToken = 0
        schedulePostMutationModelRebind()
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

handlers.InitTab = function(player, itemIds, page, hasMorePages, slotId, requestToken, totalItemCount, weaponFilter, loadSucceeded, errorMessage, errorCode, retryAfter)
    local responseSlotId = getWireInteger(slotId, 1, 1000000)
    local responseSlot = responseSlotId and SLOT_NAME_BY_ID[responseSlotId] or nil
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    local responseFilter = state.wire.Text(weaponFilter, 32, false)
    local request = state.appearancePageRequest
    local context = state.appearancePageContext
    if not state.appearancePageRequestPending or not request or not context
        or responseToken ~= request.token
        or request.generation ~= state.appearancePageGeneration
        or not state.appearancePageContextsEqual(context, request)
        or not state.isAppearancePageContextCurrent(context)
        or responseSlot ~= request.slotName
        or responseFilter ~= request.weaponFilter then
        return
    end

    local stagedItems, stagedPage, stagedHasMore, stagedTotal = state.wire.AppearancePage(
        itemIds,
        page,
        hasMorePages,
        totalItemCount,
        request.pageSize
    )
    local succeeded, message = state.stageOptionalLoadResult(loadSucceeded, errorMessage)
    local responseErrorCode, responseRetryAfter = state.stageAppearancePageFailureMetadata(errorCode, retryAfter)
    if not stagedItems or succeeded == nil or responseErrorCode == nil
        or (succeeded and (responseErrorCode ~= "" or responseRetryAfter ~= 0)) then
        return
    end
    if not succeeded then
        if responseErrorCode == APPEARANCE_PAGE_POLICY.rateLimitErrorCode then
            state.appearancePageRequest = nil
            state.appearancePageRequestPending = false
            state.appearancePageRequestStartedAt = 0
            state.appearancePageRequestRetryCount = 0
            if TransmogPaging.RateLimited(
                state.appearancePager,
                request.generation,
                state.getAppearancePageTime(),
                responseRetryAfter
            ) then
                showListMessage("Loading appearances...")
                updatePageText()
                updateActionButtons()
                if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
                return
            end
        end
        state.finishAppearancePageFailure(message)
        return
    end

    TransmogPaging.Complete(
        state.appearancePager,
        request.generation,
        stagedPage,
        stagedTotal,
        request.pageSize,
        state.getAppearancePageTime()
    )
    state.appearancePageRequest = nil
    state.appearancePageRequestPending = false
    state.appearancePageRequestStartedAt = 0
    state.appearancePageRequestRetryCount = 0
    state.currentPage = stagedPage
    state.hasMorePages = stagedHasMore
    state.totalItemCount = stagedTotal
    if request.search == "" and responseFilter == "all" then
        rememberSlotPage(responseSlot, state.currentPage)
    end

    updatePageText()
    updateCandidateList(stagedItems)
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

local function getDeletedAppearanceIdSet(deletedItemIds)
    local deletedItemIdsById = {}
    if type(deletedItemIds) == "table" then
        for key, value in pairs(deletedItemIds) do
            local itemId = tonumber(value)
            if not itemId or itemId <= 0 then
                itemId = tonumber(key)
            end
            if itemId and itemId > 0 then
                deletedItemIdsById[itemId] = true
            end
        end
    else
        local itemId = tonumber(deletedItemIds)
        if itemId and itemId > 0 then
            deletedItemIdsById[itemId] = true
        end
    end
    return deletedItemIdsById
end

local function reconcileRemovedAppearancesInSavedSets(deletedItemIdsById)
    local changed = false
    for _, setData in ipairs(getSavedTransmogSets()) do
        local items = setData and setData.items
        if type(items) == "table" then
            for index = 1, #SLOT_DATA do
                local itemId = tonumber(items[index])
                if itemId and deletedItemIdsById[itemId] then
                    -- -1 means restore the equipped item; zero would hide it.
                    items[index] = -1
                    changed = true
                end
            end
        end
    end
    return changed
end

handlers.DeleteUnlockedAppearanceResult = function(player, slotId, deletedItemIds, success, message)
    local responseSlotId = getWireInteger(slotId, 1, 1000000)
    local responseSlot = responseSlotId and SLOT_NAME_BY_ID[responseSlotId] or nil
    local stagedItemIds, stagedCount = state.wire.IntegerArray(deletedItemIds, 4096, 1, 4294967295)
    local succeeded = getWireBoolean(success)
    local stagedMessage = state.wire.Text(message, 256, true)
    if not responseSlot or not stagedItemIds or succeeded == nil or stagedMessage == nil
        or (succeeded and stagedCount == 0)
        or (not succeeded and stagedCount ~= 0) then
        return
    end

    if not succeeded then
        if stagedMessage ~= "" and (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME) then
            (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME):AddMessage("|ccff6ff98<Appearance Buddy>|r: "..stagedMessage)
        end
        return
    end

    local deletedItemIdsById = getDeletedAppearanceIdSet(stagedItemIds)
    if reconcileRemovedAppearancesInSavedSets(deletedItemIdsById) then
        state.savedSetRevision = state.savedSetRevision + 1
        if rebuildSetLists then rebuildSetLists(true) end
        if rebuildSidebarSets then rebuildSidebarSets(true) end
    end

    invalidateItemSetCatalog()

    -- Deletion is display-wide: the same visual can be active in more than the
    -- slot that owned the clicked card. Reconcile every local slot immediately,
    -- then replace it with one authoritative V2 snapshot below.
    for _, info in ipairs(SLOT_DATA) do
        local slotName = info.name
        local serverState = state.server[slotName]
        local serverItemId = serverState and tonumber(serverState.itemId)
        if serverItemId and deletedItemIdsById[serverItemId] then
            state.server[slotName] = normalizeServerState(nil, serverState.realItemId)
        end

        local previewState = state.preview[slotName]
        local previewItemId = previewState and tonumber(previewState.itemId)
        if previewState and previewState.mode == "item" and previewItemId and deletedItemIdsById[previewItemId] then
            setPreviewToRestore(slotName)
        end

        refreshSlotButton(slotName)
    end

    requestServerState()

    if isTransmogTabVisible() then
        updatePreviewModel()
        updateListSelection()
        updateActionButtons()
        if state.viewMode == "sets" then
            updateSetPreview()
            updateSetButtons()
        end
    end

    -- Removal is display-wide, and the user can change slots while the
    -- confirmation is open, so refresh whichever item list is visible without
    -- discarding their current page.
    if isTransmogTabVisible() and state.viewMode == "items" then
        requestCurrentSlotItems(false)
    end

    if stagedMessage == "" then
        stagedMessage = "Appearance removed permanently."
    end
    if SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME then
        (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME):AddMessage("|ccff6ff98<Appearance Buddy>|r: "..stagedMessage)
    end
end

handlers.SetTransmogCostStateClient = function(player, slotCosts, money, requestToken)
    if state.protocolVersion >= 2 then return end
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    if not state.costRequestPending
        or responseToken ~= state.costRequestToken
        or type(slotCosts) ~= "table" then
        return
    end

    local stagedCosts = {}
    for _, info in ipairs(SLOT_DATA) do
        local cost = getWireInteger(getWireValue(slotCosts, info.slotId), 0, 2147483647)
        if cost == nil then return end
        stagedCosts[info.name] = cost
    end
    local stagedMoney = getWireInteger(money, 0, 4294967295)
    if stagedMoney == nil then return end

    state.costRequestPending = false
    state.slotCosts = stagedCosts
    state.money = stagedMoney
    state.costSynced = true
    updateActionButtons()
    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetPreview()
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

handlers.FreeTransmogModeChanged = function(player, enabled, slotCosts, money)
    local freeEnabled = getWireBoolean(enabled)
    if freeEnabled == nil or type(slotCosts) ~= "table" then
        return
    end

    local stagedCosts = {}
    for _, info in ipairs(SLOT_DATA) do
        local cost = getWireInteger(getWireValue(slotCosts, info.slotId), 0, 2147483647)
        if cost == nil then return end
        stagedCosts[info.name] = cost
    end
    local stagedMoney = getWireInteger(money, 0, 4294967295)
    if stagedMoney == nil then return end

    state.slotCosts = stagedCosts
    state.money = stagedMoney
    state.costSynced = true
    updateActionButtons()
    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetPreview()
    elseif updateCostDisplay then
        updateCostDisplay()
    end
end

handlers.RandomAppearancePreview = function(player, itemIds, requestToken, loadSucceeded, errorMessage)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    if not state.randomizePending or responseToken ~= state.randomRequestToken then
        return
    end

    local stagedItems = state.wire.IntegerArray(itemIds, #SLOT_DATA, 0, 4294967295, #SLOT_DATA)
    local succeeded, message = state.stageOptionalLoadResult(loadSucceeded, errorMessage)
    if not stagedItems or succeeded == nil then
        return
    end
    if not succeeded and not state.integerArrayIsZero(stagedItems) then
        return
    end

    local snapshot = state.randomizeSnapshot
    state.randomizePending = false
    state.randomRequestStartedAt = 0
    if not succeeded then
        state.randomizeSnapshot = nil
        refreshAllSlotButtons()
        refreshWeaponEnchantButtons()
        updatePreviewModel()
        updateListSelection()
        updateActionButtons()
        local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if chatFrame then
            chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: "
                ..(message ~= "" and message or "Random appearances could not be loaded. Please try again."))
        end
        return
    end

    for index, info in ipairs(SLOT_DATA) do
        local itemId = stagedItems[index]
        local hasEquippedItem = state.server[info.name] and (tonumber(state.server[info.name].realItemId) or 0) > 0
        if hasEquippedItem and itemId > 0 then
            setPreviewToItem(info.name, itemId)
        end
    end

    local previewChanged = false
    if snapshot and type(snapshot.preview) == "table" then
        for _, info in ipairs(SLOT_DATA) do
            local before = snapshot.preview[info.name]
            local after = state.preview[info.name]
            if not before
                or before.mode ~= after.mode
                or before.itemId ~= after.itemId
                or before.effectiveId ~= after.effectiveId then
                previewChanged = true
                break
            end
        end
    end

    if not previewChanged then
        state.randomizeSnapshot = nil
        local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if chatFrame then
            chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: no alternate unlocked appearances are available for your equipped gear.")
        end
    end

    refreshAllSlotButtons()
    refreshWeaponEnchantButtons()
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end

handlers.RandomAppearancePreviewThrottled = function(player, requestToken, retryAfter)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    local retrySeconds = state.wire.Number(retryAfter, 0, 60)
    if not state.randomizePending
        or responseToken ~= state.randomRequestToken
        or retrySeconds == nil then
        return
    end

    state.randomizePending = false
    state.randomRequestStartedAt = 0
    state.randomizeSnapshot = nil

    local now = state.getRandomizeTime()
    retrySeconds = math.max(state.randomizeMinIntervalSeconds, retrySeconds)
    if now > 0 then
        state.randomizeCooldownUntil = math.max(
            tonumber(state.randomizeCooldownUntil) or 0,
            now + retrySeconds
        )
    end
    refreshAllSlotButtons()
    refreshWeaponEnchantButtons()
    updatePreviewModel()
    updateListSelection()
    updateActionButtons()
end

handlers.SetCurrentSlotItemPageClient = function(player, slotId, page, requestToken, weaponFilter, loadSucceeded, errorMessage, errorCode, retryAfter)
    local responseSlotId = getWireInteger(slotId, 1, 1000000)
    local responseSlot = responseSlotId and SLOT_NAME_BY_ID[responseSlotId] or nil
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    local responsePage = getWireInteger(page, 1, 1000000)
    local responseFilter = state.wire.Text(weaponFilter, 32, false)
    local succeeded, message = state.stageOptionalLoadResult(loadSucceeded, errorMessage)
    local responseErrorCode, responseRetryAfter = state.stageAppearancePageFailureMetadata(errorCode, retryAfter)
    local currentSearch = state.search

    if not state.pageLookupRequestPending
        or responseToken ~= state.pageLookupToken
        or not responsePage
        or succeeded == nil
        or responseErrorCode == nil
        or (succeeded and (responseErrorCode ~= "" or responseRetryAfter ~= 0)) then
        return
    end

    if responseSlot ~= state.currentSlot or currentSearch ~= "" or responseFilter ~= state.getWeaponFilterKey(responseSlot) then
        return
    end

    if state.pageLookupSlot ~= responseSlot then
        return
    end

    if state.pageLookupFilter ~= responseFilter then
        return
    end

    if (tonumber(state.pageLookupAnchor) or 0) ~= getCurrentSlotPageAnchor(responseSlot) then
        return
    end

    if not succeeded then
        if responseErrorCode == APPEARANCE_PAGE_POLICY.rateLimitErrorCode then
            state.pageLookupRateLimitRetryCount = state.pageLookupRateLimitRetryCount + 1
            if state.pageLookupRateLimitRetryCount <= state.pageLookupRateLimitMaxRetries then
                local retryDelay = math.max(
                    APPEARANCE_PAGE_POLICY.minimumIntervalSeconds,
                    responseRetryAfter + APPEARANCE_PAGE_POLICY.retryMarginSeconds
                )
                state.pageLookupRequestStartedAt = 0
                state.pageLookupRateLimitRetryAt = state.getAppearancePageTime() + retryDelay
                showListMessage("Locating current appearance...")
                updateActionButtons()
                if state.armRequestTimeoutPolling then state.armRequestTimeoutPolling() end
                return
            end
        end
        state.finishPageLookupFailure(message, true)
        return
    end

    state.currentPage = responsePage
    if responseFilter == "all" then
        rememberSlotPage(responseSlot, state.currentPage, state.pageLookupAnchor)
    end
    state.pageLookupSlot = nil
    state.pageLookupAnchor = nil
    state.pageLookupFilter = nil
    state.pageLookupPageSize = nil
    state.pageLookupRequestPending = false
    state.pageLookupRequestStartedAt = 0
    state.pageLookupRequestRetryCount = 0
    state.pageLookupRateLimitRetryAt = 0
    state.pageLookupRateLimitRetryCount = 0
    requestCurrentSlotItems(false)
end

handlers.SetTransmogItemIdClient = function(player, slotId, itemId, realItemId)
    if state.protocolVersion >= 2 then return end
    local responseSlotId = getWireInteger(slotId, 1, 1000000)
    local slotName = responseSlotId and SLOT_NAME_BY_ID[responseSlotId] or nil
    local stagedItemId
    if itemId ~= nil then
        stagedItemId = getWireInteger(itemId, 0, 4294967295)
    end
    local stagedRealItemId = getWireInteger(realItemId, 0, 4294967295)
    if not slotName or (itemId ~= nil and stagedItemId == nil) or stagedRealItemId == nil then
        return
    end

    local stagedServerState = normalizeServerState(stagedItemId, stagedRealItemId)

    local previousServerState = state.server[slotName]
    local previewState = state.preview[slotName]
    local previewUntouched = previewState
        and previewState.mode == "restore"
        and previewState.itemId == nil
        and previewState.effectiveId == nil
    local isInitialSlotSync = previewUntouched
        and previousServerState
        and previousServerState.itemId == nil
        and previousServerState.realItemId == nil

    state.synced = true
    state.server[slotName] = stagedServerState

    local currentServerState = state.server[state.currentSlot]
    local currentSlotEmpty = not currentServerState or (tonumber(currentServerState.realItemId) or 0) <= 0
    if currentSlotEmpty and (tonumber(state.server[slotName].realItemId) or 0) > 0 and slotName ~= state.currentSlot then
        selectSlot(slotName)
        if isTransmogTabVisible() and state.viewMode == "items" then
            loadCurrentSlotItems()
        end
    end

    local hasEquippedItem = (tonumber(state.server[slotName].realItemId) or 0) > 0
    if not hasEquippedItem or state.applyingAppearanceSet or state.applyingUnlockedItemSet or isInitialSlotSync or not isSlotDirty(slotName) then
        copyServerToPreview(slotName)
    elseif state.preview[slotName].mode == "restore" then
        state.preview[slotName].effectiveId = state.server[slotName].realItemId
    elseif state.preview[slotName].mode == "item" and state.server[slotName].realItemId and state.preview[slotName].itemId == state.server[slotName].realItemId then
        setPreviewToRestore(slotName)
    end

    refreshSlotButton(slotName)
    if WEAPON_EQUIPMENT_SLOT_BY_NAME[slotName] and refreshWeaponEnchantButtons then
        refreshWeaponEnchantButtons()
    end

    if mainFrame:IsShown() then
        updatePreviewModel()
    end

    if isTransmogTabVisible() then
        updateActionButtons()
        if slotName == state.currentSlot then
            if state.viewMode == "items" and (tonumber(state.server[slotName].realItemId) or 0) <= 0 then
                loadCurrentSlotItems()
            else
                updateListSelection()
            end
        end
        if state.viewMode == "sets" then
            updateSetPreview()
        end
    end
end

handlers.SetWeaponEnchantStateClient = function(player, enchants, eligibleSlots, explicitNoSlots)
    if state.protocolVersion >= 2 then return end
    if type(enchants) ~= "table"
        or type(eligibleSlots) ~= "table"
        or type(explicitNoSlots) ~= "table" then
        return
    end

    local stagedEnchants = {}
    local stagedEligible = {}
    local stagedExplicitNo = {}
    for _, equipSlot in ipairs({15, 16, 17}) do
        local enchantId = getWireInteger(getWireValue(enchants, equipSlot), 0, 65535)
        local eligible = getWireBoolean(getWireValue(eligibleSlots, equipSlot))
        local explicitNo = getWireBoolean(getWireValue(explicitNoSlots, equipSlot))
        if enchantId == nil or not WEAPON_ENCHANT_OPTION_BY_ID[enchantId]
            or eligible == nil or explicitNo == nil or (explicitNo and enchantId ~= 0) then
            return
        end
        stagedEnchants[equipSlot] = enchantId
        stagedEligible[equipSlot] = eligible
        stagedExplicitNo[equipSlot] = explicitNo
    end

    for _, equipSlot in ipairs({15, 16, 17}) do
        local previewWasDirty = isWeaponEnchantDirty(equipSlot)
        state.weaponEnchantServer[equipSlot] = stagedEnchants[equipSlot]
        state.weaponEnchantExplicitNoServer[equipSlot] = stagedExplicitNo[equipSlot]
        state.weaponEnchantEligible[equipSlot] = stagedEligible[equipSlot]
        if state.applyingAppearanceSet or not previewWasDirty then
            copyWeaponEnchantServerToPreview(equipSlot)
        end
    end

    if state.enchantingEquipSlot
        and state.weaponEnchantEligible[state.enchantingEquipSlot] ~= true
        and hideWeaponEnchantPicker then
        hideWeaponEnchantPicker()
    end

    if refreshWeaponEnchantButtons then refreshWeaponEnchantButtons() end
    if refreshWeaponEnchantPicker then refreshWeaponEnchantPicker() end
    if mainFrame:IsShown() then
        updatePreviewModel()
    end
    if isTransmogTabVisible() then
        updateActionButtons()
    end
end

handlers.LoadTransmogsAfterSave = function()
    if mainFrame:IsShown() and state.synced then
        updatePreviewModel()
    end
end

handlers.ScanInventoryUnlocksResult = function(player, requestToken, addedCount, errorMessage)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    local stagedAddedCount = getWireInteger(addedCount, 0, 10000)
    local stagedErrorMessage = state.wire.Text(errorMessage, 256, true)
    if not state.scanRequestPending
        or responseToken ~= state.scanRequestToken
        or stagedAddedCount == nil
        or stagedErrorMessage == nil then
        return
    end
    state.scanRequestPending = false
    state.scanRequestStartedAt = 0

    local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if chatFrame then
        if stagedErrorMessage ~= "" then
            chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..stagedErrorMessage)
        else
            chatFrame:AddMessage(("|ccff6ff98<Appearance Buddy>|r: inventory scan complete; %d new appearance%s unlocked."):format(
                stagedAddedCount,
                stagedAddedCount == 1 and "" or "s"
            ))
        end
    end

    if stagedAddedCount > 0 then
        invalidateItemSetCatalog()
        if isTransmogTabVisible() and state.viewMode == "items" then
            requestCurrentSlotItems(false)
        end
        if isCatalogSetViewVisible() then
            refreshItemSetCatalogIfNeeded(true)
        end
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

state.sanitizeItemSetText = function(value, fallback, maxLength)
    if value == nil then value = fallback end
    return state.wire.Text(value, maxLength, false)
end

state.stageItemSetItems = function(values)
    return state.wire.IntegerArray(values, #SLOT_DATA, 0, 4294967295, #SLOT_DATA)
end

state.stageItemSetDetails = function(fullItems, unlockedItems)
    return state.wire.PairedItemArrays(fullItems, unlockedItems, #SLOT_DATA)
end

state.stageItemSetCatalogPage = function(itemSets, maxRecords, existingIds)
    if type(itemSets) ~= "table" then
        return nil, "catalog payload was not a table"
    end

    local count = #itemSets
    if count > maxRecords then
        return nil, "catalog page exceeded its record limit"
    end
    for key in pairs(itemSets) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > count then
            return nil, "catalog page was sparse or contained non-array fields"
        end
    end

    local staged = {}
    local seenIds = {}
    for index = 1, count do
        local source = itemSets[index]
        if type(source) ~= "table" then
            return nil, "catalog record was not a table"
        end

        local itemSetId = getWireInteger(source.id, -2147483647, 2147483647)
        local name = state.sanitizeItemSetText(source.name, "Unlocked Item Set", 128)
        local displayName = state.sanitizeItemSetText(source.displayName, name, 192)
        local unlockedCount = getWireInteger(source.unlockedCount, 0, 255)
        local totalCount = getWireInteger(source.totalCount, 0, 255)
        local iconItemId = getWireInteger(source.iconItemId == nil and 0 or source.iconItemId, 0, 4294967295)
        local isVirtual = false
        local hasExactTotal = false
        if source.isVirtual ~= nil then
            isVirtual = getWireBoolean(source.isVirtual)
        end
        if source.hasExactTotal ~= nil then
            hasExactTotal = getWireBoolean(source.hasExactTotal)
        end
        if not itemSetId or itemSetId == 0 or not name or not displayName
            or unlockedCount == nil or totalCount == nil or iconItemId == nil
            or isVirtual == nil or hasExactTotal == nil
            or seenIds[itemSetId] or (existingIds and existingIds[itemSetId])
            or (hasExactTotal and unlockedCount > totalCount) then
            return nil, "catalog record failed validation"
        end

        local record = {
            id = itemSetId,
            name = name,
            displayName = displayName,
            unlockedCount = unlockedCount,
            totalCount = totalCount,
            isVirtual = isVirtual,
            hasExactTotal = hasExactTotal,
            iconItemId = iconItemId,
        }
        if source.fullItems ~= nil or source.unlockedItems ~= nil then
            record.fullItems, record.unlockedItems = state.stageItemSetDetails(
                source.fullItems,
                source.unlockedItems
            )
            if not record.fullItems or not record.unlockedItems then
                return nil, "legacy catalog details failed validation"
            end
        end
        seenIds[itemSetId] = true
        staged[index] = record
    end
    return staged
end

state.finishItemSetCatalogFailure = function(message)
    state.itemSetCatalogRequestToken = state.itemSetCatalogRequestToken + 1
    state.itemSetCatalogRequestPending = false
    state.itemSetCatalogRequestStartedAt = 0
    state.itemSetCatalogRequestPage = 0
    state.resetSetListScroll = false
    updateSetButtons()
    local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if chatFrame then
        chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..tostring(message).." Click Refresh to retry.")
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

state.rejectItemSetCatalogResponse = function(reason)
    state.finishItemSetCatalogFailure("item-set data was rejected ("..tostring(reason)..").")
end

handlers.InitItemSets = function(player, itemSets, requestToken, page, hasMore, total, normalizedSearch, loadSucceeded, errorMessage)
    if not state.itemSetCatalogRequestPending
        or getWireInteger(requestToken, 0, 2147483647) ~= state.itemSetCatalogRequestToken then
        return
    end

    local legacyResponse = page == nil and hasMore == nil and total == nil and normalizedSearch == nil
    local responsePage = legacyResponse and state.itemSetCatalogRequestPage or getWireInteger(page, 1, 100000)
    local stagedSearch = legacyResponse and "" or state.wire.Text(normalizedSearch, 64, true)
    local responseSearch = legacyResponse
        and state.itemSetCatalogRequestSearch
        or (stagedSearch and state.normalizeItemSetCatalogSearch(stagedSearch) or nil)
    local responseHasMore
    local responseTotal
    if legacyResponse then
        responseHasMore = false
    else
        responseHasMore = getWireBoolean(hasMore)
        responseTotal = getWireInteger(total, 0, 1000000)
    end
    local succeeded, message = state.stageOptionalLoadResult(loadSucceeded, errorMessage)
    if responsePage ~= state.itemSetCatalogRequestPage
        or responseSearch ~= state.itemSetCatalogRequestSearch
        or responseHasMore == nil
        or succeeded == nil then
        state.rejectItemSetCatalogResponse("page metadata did not match the request")
        return
    end

    local existingIds = responsePage > 1 and state.itemSetCatalogById or nil
    local responseItems, validationError = state.stageItemSetCatalogPage(
        itemSets,
        legacyResponse and 5000 or state.itemSetCatalogPageSize,
        existingIds
    )
    if not responseItems then
        state.rejectItemSetCatalogResponse(validationError)
        return
    end

    if not succeeded then
        if #responseItems ~= 0 or responseHasMore or responseTotal ~= 0 then
            state.rejectItemSetCatalogResponse("failure payload was inconsistent")
            return
        end
        state.finishItemSetCatalogFailure(
            message ~= "" and message or "The item-set catalog could not be loaded."
        )
        return
    end

    local priorCount = responsePage == 1 and 0 or #state.itemSetCatalog
    local stagedCount = priorCount + #responseItems
    responseTotal = responseTotal or stagedCount
    if responseTotal < stagedCount
        or (responseHasMore and responseTotal <= stagedCount)
        or (not responseHasMore and responseTotal ~= stagedCount)
        or (responsePage > 1 and state.itemSetCatalogTotal > 0
            and responseTotal ~= state.itemSetCatalogTotal) then
        state.rejectItemSetCatalogResponse("page totals were inconsistent")
        return
    end

    if responsePage == 1 then
        state.itemSetCatalog = {}
        state.itemSetCatalogById = {}
        state.itemSetDetailRequests = {}
        state.itemSetDetailFailures = {}
    end
    for _, setData in ipairs(responseItems) do
        state.itemSetCatalog[#state.itemSetCatalog + 1] = setData
        state.itemSetCatalogById[setData.id] = setData
    end
    state.itemSetCatalogLoaded = true
    state.itemSetCatalogPage = responsePage
    state.itemSetCatalogHasMore = responseHasMore
    state.itemSetCatalogTotal = responseTotal or #state.itemSetCatalog
    state.itemSetCatalogSearch = responseSearch
    state.itemSetCatalogRequestPending = false
    state.itemSetCatalogRequestStartedAt = 0
    state.itemSetCatalogRequestPage = 0
    state.itemSetCatalogLastRefreshAt = GetTime and GetTime() or 0
    state.itemSetCatalogDirty = false
    state.itemSetCatalogDirtyAt = 0
    state.itemSetCatalogLevelChanged = false
    state.itemSetCatalogRevision = state.itemSetCatalogRevision + 1

    if isCatalogSetViewVisible() then
        rebuildSetLists()
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

handlers.ItemSetDetails = function(player, itemSetId, token, fullItems, unlockedItems, loadSucceeded, errorMessage)
    itemSetId = getWireInteger(itemSetId, -2147483647, 2147483647)
    token = getWireInteger(token, 0, 2147483647)
    local request = itemSetId and state.itemSetDetailRequests[itemSetId]
    if not itemSetId or not request or request.token ~= token then
        return
    end

    local stagedFullItems, stagedUnlockedItems = state.stageItemSetDetails(fullItems, unlockedItems)
    local succeeded, message = state.stageOptionalLoadResult(loadSucceeded, errorMessage)
    if not stagedFullItems or not stagedUnlockedItems or succeeded == nil
        or (not succeeded and (not state.integerArrayIsZero(stagedFullItems)
            or not state.integerArrayIsZero(stagedUnlockedItems))) then
        return
    end

    state.itemSetDetailRequests[itemSetId] = nil
    if not succeeded then
        state.itemSetDetailFailures[itemSetId] = true
        if isCatalogSetViewVisible()
            and tonumber(state.selectedCatalogSetId) == itemSetId then
            updateSetPreview()
        end
        local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if chatFrame and message ~= "" then
            chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..message)
        end
        if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
        return
    end

    state.itemSetDetailFailures[itemSetId] = nil
    state.itemSetDetailsById[itemSetId] = {
        fullItems = stagedFullItems,
        unlockedItems = stagedUnlockedItems,
    }

    if isCatalogSetViewVisible()
        and tonumber(state.selectedCatalogSetId) == itemSetId then
        updateSetPreview()
    end
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
end

handlers.ItemSetCatalogInvalidated = function()
    invalidateItemSetCatalog()
    if isCatalogSetViewVisible() then
        updateSetButtons()
    end
end

do
    local requestTimeoutFrame = CreateFrame("Frame")
    requestTimeoutFrame.elapsed = 0

    local function hasPendingTimedRequest()
        local catalogViewVisible = isCatalogSetViewVisible()
        return (catalogViewVisible and state.itemSetCatalogRequestPending)
            or (catalogViewVisible and next(state.itemSetDetailRequests) ~= nil)
            or state.syncRequestPending
            or state.isPreviewMutationLocked()
            or state.scanRequestPending
            or state.pageLookupRequestPending
            or state.appearancePageRequestPending
            or TransmogPaging.HasScheduledRequest(state.appearancePager)
    end

    local function requestTimeoutFrame_OnUpdate(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.10 then
            return
        end
        self.elapsed = 0

        if not state.itemSetCatalogRequestPending
            and next(state.itemSetDetailRequests) == nil
            and not state.syncRequestPending
            and not state.isPreviewMutationLocked()
            and not state.scanRequestPending
            and not state.pageLookupRequestPending
            and not state.appearancePageRequestPending
            and not TransmogPaging.HasScheduledRequest(state.appearancePager) then
            self:SetScript("OnUpdate", nil)
            return
        end

        local now = GetTime and GetTime() or 0
        if now <= 0 then
            return
        end

        state.dispatchQueuedAppearancePage(now)

        if state.syncRequestPending
            and (now - (state.syncRequestStartedAt or 0)) >= state.syncRequestTimeoutSeconds then
            if state.syncRequestRetryCount < state.syncRequestMaxRetries then
                state.syncRequestRetryCount = state.syncRequestRetryCount + 1
                requestServerState(true)
            else
                state.finishStateSyncFailure("Transmog state did not synchronize. Reload or restart transmog.lua, then reopen the window.")
            end
        end

        if state.isPreviewMutationLocked()
            and (now - (state.mutationRequestStartedAt or now)) >= state.mutationRequestTimeoutSeconds then
            state.applyingAppearanceSet = false
            state.applyingUnlockedItemSet = false
            state.mutationRequestStartedAt = 0
            state.mutationRequestToken = state.mutationRequestToken + 1
            requestServerState()
            local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
            if chatFrame then
                chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: the appearance result timed out. No paid request was retried; authoritative state is being refreshed.")
            end
        end

        if state.scanRequestPending
            and (now - (state.scanRequestStartedAt or now)) >= 8 then
            state.scanRequestPending = false
            state.scanRequestStartedAt = 0
            state.scanRequestToken = state.scanRequestToken + 1
            local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
            if chatFrame then
                chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: inventory scan timed out; no result was accepted.")
            end
        end

        if state.pageLookupRequestPending and state.pageLookupRateLimitRetryAt > 0 then
            if now >= state.pageLookupRateLimitRetryAt then
                requestCurrentSlotItemPage(state.pageLookupSlot, state.pageLookupAnchor, true)
            end
        elseif state.pageLookupRequestPending
            and state.pageLookupRequestStartedAt > 0
            and (now - state.pageLookupRequestStartedAt) >= state.pageLookupRequestTimeoutSeconds then
            if state.pageLookupRequestRetryCount < 1 then
                state.pageLookupRequestRetryCount = state.pageLookupRequestRetryCount + 1
                requestCurrentSlotItemPage(state.pageLookupSlot, state.pageLookupAnchor, true)
            else
                state.pageLookupRequestPending = false
                state.pageLookupRequestStartedAt = 0
                state.pageLookupToken = state.pageLookupToken + 1
                state.pageLookupSlot = nil
                state.pageLookupAnchor = nil
                state.pageLookupFilter = nil
                state.pageLookupPageSize = nil
                state.pageLookupRateLimitRetryAt = 0
                state.pageLookupRateLimitRetryCount = 0
                state.currentPage = 1
                requestCurrentSlotItems(false)
            end
        end

        if state.appearancePageRequestPending
            and (now - (state.appearancePageRequestStartedAt or now)) >= state.appearancePageRequestTimeoutSeconds then
            if state.appearancePageRequestRetryCount < 1 then
                state.appearancePageRequestRetryCount = state.appearancePageRequestRetryCount + 1
                requestCurrentSlotItems(false, true)
            else
                state.requestToken = state.requestToken + 1
                state.finishAppearancePageFailure("Appearance list did not respond. Change slots or search again to retry.")
            end
        end

        if isCatalogSetViewVisible()
            and state.itemSetCatalogRequestPending
            and (now - (state.itemSetCatalogRequestStartedAt or 0))
                >= state.itemSetCatalogRequestTimeoutSeconds then
            local failedPage = state.itemSetCatalogRequestPage
            state.itemSetCatalogRequestPending = false
            state.itemSetCatalogRequestStartedAt = 0
            state.itemSetCatalogRequestPage = 0

            if isCatalogSetViewVisible() then
                if rebuildSetLists then rebuildSetLists(true) end
                local setsFrame = transmogTab.setsFrame
                if failedPage == 1 and setsFrame then
                    setsFrame.previewTitle:SetText("Item Sets Unavailable")
                    setsFrame.previewInfo:SetText("No response from the server item-set handler.\nReload or restart transmog.lua, then click Refresh.")
                    setsFrame.previewModel:Undress()
                end
                updateSetButtons()
            end
        end

        if isCatalogSetViewVisible() and next(state.itemSetDetailRequests) ~= nil then
            local expiredRequests = {}
            for itemSetId, request in pairs(state.itemSetDetailRequests) do
                if (now - (request.startedAt or now)) >= ITEM_SET_DETAIL_REQUEST_TIMEOUT then
                    expiredRequests[#expiredRequests + 1] = {
                        itemSetId = itemSetId,
                        token = request.token,
                        retryCount = request.retryCount or 0,
                    }
                end
            end

            for _, expired in ipairs(expiredRequests) do
                local request = state.itemSetDetailRequests[expired.itemSetId]
                if request and request.token == expired.token then
                    state.itemSetDetailRequests[expired.itemSetId] = nil

                    local catalogSet = state.itemSetCatalogById[expired.itemSetId]
                    local isSelected = isCatalogSetViewVisible()
                        and tonumber(state.selectedCatalogSetId) == expired.itemSetId
                    if catalogSet and isSelected and expired.retryCount < ITEM_SET_DETAIL_MAX_RETRIES then
                        state.setUIController.requestCatalogSetDetails(catalogSet, expired.retryCount + 1)
                    elseif isSelected then
                        state.itemSetDetailFailures[expired.itemSetId] = true
                        updateSetPreview()
                    end
                end
            end
        end

        if not hasPendingTimedRequest() then
            self:SetScript("OnUpdate", nil)
        end
    end

    state.armRequestTimeoutPolling = function()
        if requestTimeoutFrame:GetScript("OnUpdate") == nil then
            requestTimeoutFrame.elapsed = 0
            requestTimeoutFrame:SetScript("OnUpdate", requestTimeoutFrame_OnUpdate)
        end
    end

    state.refreshRequestTimeoutPolling = function()
        if hasPendingTimedRequest() then
            state.armRequestTimeoutPolling()
        else
            requestTimeoutFrame.elapsed = 0
            requestTimeoutFrame:SetScript("OnUpdate", nil)
        end
    end
end

state.stageMutationResult = function(appliedCount, hiddenCount, restoredCount, chargedCost, missingSlots, errorMessage, money, suppressStateSync)
    local stagedSuppressStateSync = false
    if suppressStateSync ~= nil then
        stagedSuppressStateSync = getWireBoolean(suppressStateSync)
        if stagedSuppressStateSync == nil then return nil end
    end
    local staged = {
        appliedCount = getWireInteger(appliedCount, 0, #SLOT_DATA),
        hiddenCount = getWireInteger(hiddenCount, 0, #SLOT_DATA),
        restoredCount = getWireInteger(restoredCount, 0, #SLOT_DATA),
        chargedCost = getWireInteger(chargedCost, 0, 4294967295),
        missingSlots = state.wire.Text(missingSlots, 256, true),
        errorMessage = state.wire.Text(errorMessage, 256, true),
        money = getWireInteger(money, 0, 4294967295),
        suppressStateSync = stagedSuppressStateSync,
    }
    if staged.appliedCount == nil
        or staged.hiddenCount == nil
        or staged.restoredCount == nil
        or staged.chargedCost == nil
        or staged.missingSlots == nil
        or staged.errorMessage == nil
        or staged.money == nil
        or staged.appliedCount + staged.hiddenCount + staged.restoredCount > #SLOT_DATA
        or (staged.suppressStateSync and (staged.appliedCount > 0
            or staged.hiddenCount > 0 or staged.restoredCount > 0
            or staged.chargedCost > 0)) then
        return nil
    end
    return staged
end

handlers.AppearanceSetResult = function(player, appliedCount, hiddenCount, missingSlots, restoredCount, chargedCost, errorMessage, money, requestToken, suppressStateSync)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    if not state.applyingAppearanceSet or responseToken ~= state.mutationRequestToken then
        return
    end

    local result = state.stageMutationResult(
        appliedCount,
        hiddenCount,
        restoredCount,
        chargedCost,
        missingSlots,
        errorMessage,
        money,
        suppressStateSync
    )
    if not result then
        return
    end

    state.applyingAppearanceSet = false
    state.mutationRequestStartedAt = 0

    appliedCount = result.appliedCount
    hiddenCount = result.hiddenCount
    restoredCount = result.restoredCount
    chargedCost = result.chargedCost
    errorMessage = result.errorMessage
    missingSlots = result.missingSlots
    state.money = result.money

    local parts = {}
    if appliedCount > 0 then
        table.insert(parts, ("%d appearance%s applied"):format(appliedCount, appliedCount == 1 and "" or "s"))
    end
    if hiddenCount > 0 then
        table.insert(parts, ("%d slot%s hidden"):format(hiddenCount, hiddenCount == 1 and "" or "s"))
    end
    if restoredCount > 0 then
        table.insert(parts, ("%d slot%s restored"):format(restoredCount, restoredCount == 1 and "" or "s"))
    end
    if missingSlots ~= "" then
        table.insert(parts, "Unavailable or restricted slots: "..missingSlots)
    end
    if chargedCost > 0 then
        table.insert(parts, ("Cost: %s"):format(GetCoinTextureString and GetCoinTextureString(chargedCost) or chargedCost))
    end
    if errorMessage ~= "" then
        table.insert(parts, errorMessage)
    end
    if #parts == 0 then
        table.insert(parts, "No appearance set changes were applied")
    end

    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetButtons()
    end

    local changedAppearance = appliedCount > 0 or hiddenCount > 0 or restoredCount > 0
    if changedAppearance then
        state.randomizeSnapshot = nil
    end
    if not result.suppressStateSync then
        if changedAppearance then
            requestPostMutationStateSync()
        else
            requestServerState()
        end
    end
    updateActionButtons()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
    if SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME then
        (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME):AddMessage(
            "|ccff6ff98<Appearance Buddy>|r: "..table.concat(parts, ". ")
        )
    end

end

handlers.UnlockedItemSetResult = function(player, setName, appliedCount, hiddenCount, missingSlots, chargedCost, errorMessage, money, requestToken, suppressStateSync)
    local responseToken = getWireInteger(requestToken, 0, 2147483647)
    if not state.applyingUnlockedItemSet or responseToken ~= state.mutationRequestToken then
        return
    end

    if missingSlots == nil and type(hiddenCount) == "string" then
        missingSlots = hiddenCount
        hiddenCount = 0
    end

    local stagedSetName = state.wire.Text(setName, 128, false)
    local result = state.stageMutationResult(
        appliedCount,
        hiddenCount,
        0,
        chargedCost,
        missingSlots,
        errorMessage,
        money,
        suppressStateSync
    )
    if not stagedSetName or not result then
        return
    end

    state.applyingUnlockedItemSet = false
    state.mutationRequestStartedAt = 0
    setName = stagedSetName
    appliedCount = result.appliedCount
    hiddenCount = result.hiddenCount
    chargedCost = result.chargedCost
    errorMessage = result.errorMessage
    missingSlots = result.missingSlots
    state.money = result.money

    local parts = {
        ("%s applied to %d slot%s"):format(setName, appliedCount, appliedCount == 1 and "" or "s")
    }
    if hiddenCount > 0 then
        table.insert(parts, ("%d non-set armor slot%s hidden"):format(hiddenCount, hiddenCount == 1 and "" or "s"))
    end
    if missingSlots ~= "" then
        table.insert(parts, "Unavailable or restricted slots: "..missingSlots)
    end
    if chargedCost > 0 then
        table.insert(parts, ("Cost: %s"):format(GetCoinTextureString and GetCoinTextureString(chargedCost) or chargedCost))
    end
    if errorMessage ~= "" then
        table.insert(parts, errorMessage)
    end

    if isTransmogTabVisible() and state.viewMode == "sets" then
        updateSetButtons()
    end
    local changedAppearance = appliedCount > 0 or hiddenCount > 0
    if not result.suppressStateSync then
        if changedAppearance then
            requestPostMutationStateSync()
        else
            requestServerState()
        end
    end
    updateActionButtons()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end
    if SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME then
        (SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME):AddMessage(
            "|ccff6ff98<Appearance Buddy>|r: "..table.concat(parts, ". ")
        )
    end

end

-- Sent by the server when a player interacts with a transmogrifier NPC.
handlers.TransmogFrame = function()
    if ns.mainFrame and ns.mainFrame.ShowTransmog then
        ns.mainFrame:ShowTransmog()
    elseif ns.mainFrame and not ns.mainFrame:IsShown() then
        ns.mainFrame:Show()
    end
end

if state.enabled then
    local ok, err = pcall(function()
        AIO.AddHandlers("Transmog", handlers)
    end)

    if not ok then
        state.enabled = false
        state.disabledReason = "Transmog bridge unavailable. Disable the legacy transmog client if it is still loaded."
    end
else
    state.disabledReason = "AIO is not available, so Appearance Buddy cannot reach the server transmog handlers."
end

ns.ApplyAppearanceSetAsTransmog = applyAppearanceSetAsTransmog
ns.IsTransmogAvailable = function()
    return state.enabled
end

transmogTab:EnableMouseWheel(true)
transmogTab:SetScript("OnMouseWheel", handlePageScroll)
transmogTab.list:EnableMouseWheel(true)
transmogTab.list:SetScript("OnMouseWheel", handlePageScroll)
transmogTab.searchBox:EnableMouseWheel(true)
transmogTab.searchBox:SetScript("OnMouseWheel", handlePageScroll)
mainFrame:EnableMouseWheel(true)
mainFrame:SetScript("OnMouseWheel", handlePageScroll)

do
    local dressingRoom = mainFrame.dressingRoom
    local originalOnMouseWheel = dressingRoom:GetScript("OnMouseWheel")

    dressingRoom:SetScript("OnMouseWheel", function(self, delta)
        if originalOnMouseWheel then
            originalOnMouseWheel(self, delta)
        end
    end)
end

transmogTab:SetScript("OnShow", function()
    if ns.SetAppearanceBuddyPreviewControlsVisible then
        ns.SetAppearanceBuddyPreviewControlsVisible(false)
    end

    state.previousUnit = mainFrame.dressingRoom.GetUnitToken and mainFrame.dressingRoom:GetUnitToken() or "player"
    saveDressingRoomView()
    setTransmogDressingRoomStatic(true)
    mainFrame.dressingRoom:SetUnit("player")
    setTransmogDressingRoomView()

    selectSlot(state.currentSlot)
    refreshAllSlotButtons()
    refreshWeaponEnchantButtons()
    if rebuildSidebarSets then rebuildSidebarSets() end
    updateActionButtons()

    if state.enabled and not isServerStateReady() and not state.syncRequestPending then
        requestServerState()
    elseif state.enabled
        and state.viewMode == "items"
        and transmogTab.list:IsShown()
        and type(transmogTab.list.itemIds) == "table"
        and #transmogTab.list.itemIds > 0 then
        transmogTab.list.skipUndress = state.showEquippedGear
            or state.currentSlot == "Main Hand"
            or state.currentSlot == "Off-hand"
        transmogTab.list:Update()
    end

    updatePreviewModel()
    state.setUIController.updateViewMode()
    refreshItemSetCatalogIfNeeded(false)
    local setsFrame = transmogTab.setsFrame
    if setsFrame and ns.RefreshManagedScrollFrame then
        if state.viewMode == "sets" then
            ns.RefreshManagedScrollFrame(setsFrame.listScroll)
        else
            ns.RefreshManagedScrollFrame(setsFrame.listScroll, false)
        end
    end
end)

transmogTab:SetScript("OnHide", function()
    if cancelPostMutationModelRebind then
        cancelPostMutationModelRebind()
    end
    clearTransmogSearchFocus()
    setTransmogDressingRoomStatic(false)
    state.cancelPendingSlotButtonIconQueries()
    state.cancelPreviewModelItemQueries()
    if transmogTab.list.CancelQueries then
        transmogTab.list:CancelQueries(true)
    end
    state.cancelAppearancePageActivity()
    state.cancelPageLookupActivity()
    if state.refreshRequestTimeoutPolling then state.refreshRequestTimeoutPolling() end

    -- Randomize is a transient preview. If the main window closes, restore
    -- the pre-random state and reject any response that arrives afterward.
    -- Switching to another tab deliberately retains the normal preview.
    if not mainFrame:IsShown()
        and not state.isPreviewMutationLocked()
        and (state.randomizePending or state.randomizeSnapshot) then
        restoreRandomizedAppearance()
    end

    if ns.SetAppearanceBuddyPreviewControlsVisible then
        -- The Settings page shares this mannequin. Do not reveal legacy slot
        -- and action controls while leaving the Transmogrify view.
        ns.SetAppearanceBuddyPreviewControlsVisible(false)
    end

    -- These controls live on the persistent sidebar, so hide them whenever
    -- the Transmogrify tab itself is not active.
    transmogTab.buttonRevertAll:Hide()
    transmogTab.buttonRevert:Hide()
    transmogTab.buttonApplyAll:Hide()

    -- Keep the transmog preview on the model when switching tabs, but restore
    -- the normal camera immediately so a later return to Transmog snapshots
    -- the real normal-view position instead of the static Transmog view.
    if not mainFrame:IsShown() then
        if ns.RefreshDressingRoomFromSlots then
            ns.RefreshDressingRoomFromSlots(state.previousUnit)
        end
    end
    restoreDressingRoomView()

    local setsFrame = transmogTab.setsFrame
    if setsFrame and ns.RefreshManagedScrollFrame then
        ns.RefreshManagedScrollFrame(setsFrame.listScroll, false)
    end
end)

-- The Transmog tab may already be hidden when the player closes the main
-- window from Settings. Handle the parent close too so a random reply cannot
-- survive until the next time the Transmog tab is opened.
mainFrame:HookScript("OnHide", function()
    if cancelPostMutationModelRebind then
        cancelPostMutationModelRebind()
    end
    if not state.isPreviewMutationLocked()
        and (state.randomizePending or state.randomizeSnapshot) then
        restoreRandomizedAppearance()
    end
end)

local POST_MUTATION_MODEL_REBIND_DELAY = 0.10
local postMutationModelRebindFrame = CreateFrame("Frame")
postMutationModelRebindFrame.elapsed = 0
postMutationModelRebindFrame.pending = false

local function postMutationModelRebindFrame_OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < POST_MUTATION_MODEL_REBIND_DELAY then
        return
    end

    self.elapsed = 0
    self.pending = false
    self:SetScript("OnUpdate", nil)

    if not mainFrame:IsShown()
        or not isTransmogTabVisible()
        or state.isPreviewMutationLocked() then
        return
    end

    -- PLAYER_VISIBLE_ITEM updates arrive after the Apply result. Rebind each
    -- custom DressUpModel after that client update settles so ClearModel cannot
    -- leave it on the temporary empty player model.
    mainFrame.dressingRoom:Reset()
    setTransmogDressingRoomView()
    updatePreviewModel()

    if state.viewMode == "items"
        and transmogTab.list:IsShown()
        and type(transmogTab.list.itemIds) == "table"
        and #transmogTab.list.itemIds > 0 then
        transmogTab.list.skipUndress = state.showEquippedGear
            or state.currentSlot == "Main Hand"
            or state.currentSlot == "Off-hand"
        transmogTab.list:Update()
    elseif state.viewMode == "sets" then
        local setsFrame = transmogTab.setsFrame
        if setsFrame and setsFrame.previewModel then
            setsFrame.previewModel._appearanceBuddyPreviewSignature = nil
        end
        updateSetPreview()
    end
end

cancelPostMutationModelRebind = function()
    postMutationModelRebindFrame.elapsed = 0
    postMutationModelRebindFrame.pending = false
    postMutationModelRebindFrame:SetScript("OnUpdate", nil)
end

schedulePostMutationModelRebind = function()
    postMutationModelRebindFrame.elapsed = 0
    postMutationModelRebindFrame.pending = true
    postMutationModelRebindFrame:SetScript("OnUpdate", postMutationModelRebindFrame_OnUpdate)
end

local equipmentSyncFrame = CreateFrame("Frame")
equipmentSyncFrame.pending = false
equipmentSyncFrame.elapsed = 0
local function equipmentSyncFrame_OnUpdate(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.10 then return end
    self.pending = false
    self.elapsed = 0
    self:SetScript("OnUpdate", nil)
    if transmogTab:IsVisible() and not state.isPreviewMutationLocked() then
        requestServerState()
    end
end

local function scheduleEquipmentSync()
    equipmentSyncFrame.pending = true
    equipmentSyncFrame.elapsed = 0
    if equipmentSyncFrame:GetScript("OnUpdate") == nil then
        equipmentSyncFrame:SetScript("OnUpdate", equipmentSyncFrame_OnUpdate)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addon then
            self:UnregisterEvent("ADDON_LOADED")
            -- This module loads before SavedVariables are available. Re-sanitize
            -- the real persisted table now that WoW has loaded it.
            savedTransmogSetsSanitized = false
            state.savedSetRevision = state.savedSetRevision + 1
        end
        return
    end

    if not state.enabled then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        state.markServerStateStale(true)
        state.invalidateTooltipEquipmentState()
        state.requestTooltipEquipmentState()
        if transmogTab:IsVisible() then
            requestServerState()
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if transmogTab.sidebar and transmogTab.sidebar.RefreshCurrentGearIcon then
            transmogTab.sidebar:RefreshCurrentGearIcon()
        end
        if state.randomizeSnapshot and not state.isPreviewMutationLocked() then
            restoreRandomizedAppearance()
        else
            state.randomizePending = false
            state.randomRequestToken = state.randomRequestToken + 1
            state.randomRequestStartedAt = 0
            state.randomizeSnapshot = nil
        end
        state.markServerStateStale(true)
        state.invalidateTooltipEquipmentState()
        state.requestTooltipEquipmentState()
        if transmogTab:IsVisible() and not state.isPreviewMutationLocked() then
            scheduleEquipmentSync()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        -- Catalog and saved-set data can outlive a level-up. Mark both the
        -- authoritative list and local preview cache stale so newly eligible
        -- appearances appear, while the level guard keeps all others hidden.
        state.appearanceLevelChanged = true
        state.itemSetCatalogLevelChanged = true
        invalidateItemSetCatalog()
        state.markServerStateStale(true)
        if transmogTab:IsVisible() then
            requestServerState()
        end
        if rebuildSidebarSets then
            rebuildSidebarSets(true)
        end
        if isCatalogSetViewVisible() then
            refreshItemSetCatalogIfNeeded(true)
        elseif isTransmogTabVisible() and state.viewMode == "sets" then
            if rebuildSetLists then rebuildSetLists(true) end
            updateSetPreview()
        end
    elseif event == "PLAYER_MONEY" then
        state.money = type(GetMoney) == "function" and (tonumber(GetMoney()) or state.money) or state.money
        updateActionButtons()
    end
end)

copyAllServerToPreview()
copyAllWeaponEnchantServerToPreview()
selectSlot(state.currentSlot)
refreshAllSlotButtons()
refreshWeaponEnchantButtons()
updatePageText()
updateActionButtons()
state.setUIController.updateModeButtons()
state.setUIController.setItemModeVisible(state.viewMode == "items")
do
    local setsFrame = transmogTab.setsFrame
    if setsFrame and state.viewMode == "items" then
        setsFrame:Hide()
        if ns.RefreshManagedScrollFrame then
            ns.RefreshManagedScrollFrame(setsFrame.listScroll, false)
        end
    elseif setsFrame then
        setsFrame:Show()
        if ns.RefreshManagedScrollFrame then
            ns.RefreshManagedScrollFrame(setsFrame.listScroll)
        end
    end
end
