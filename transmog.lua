local AIO = AIO or require("AIO")
local TransmogHandlers = AIO.AddHandlers("Transmog", {})

local SLOTS = 10
local CALC = 281

local VISIBLE_SLOTS = {
    283, 287, 289, 291, 293, 295, 297, 299, 301, 311, 313, 315, 317, 319
}

local VISIBLE_SLOT_SET = {}
for _, slot in ipairs(VISIBLE_SLOTS) do
    VISIBLE_SLOT_SET[slot] = true
end

local UNUSABLE_INVENTORY_TYPES = {[2]=true, [11]=true, [12]=true, [18]=true, [24]=true, [27]=true, [28]=true}

local INVENTORY_TYPE_MAP = {
    [283] = "= 1", [287] = "= 3", [289] = "= 4", [291] = "IN (5,20)", [293] = "= 6",
    [295] = "= 7", [297] = "= 8", [299] = "= 9", [301] = "= 10", [311] = "= 16",
    [313] = "IN (13,17,21)", [315] = "IN (13,17,22,23,14)", [317] = "IN (15,25,26)", [319] = "= 19"
}

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
    [315] = {[13] = true, [14] = true, [17] = true, [22] = true, [23] = true},
    [317] = {[15] = true, [25] = true, [26] = true},
    [319] = {[19] = true},
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
    [23] = 13,
    [15] = 14,
    [25] = 14,
    [26] = 14,
}

local function NormalizePage(page)
    page = tonumber(page) or 1
    if page < 1 then
        page = 1
    end

    return math.floor(page)
end

local function NormalizePageSize(pageSize)
    pageSize = tonumber(pageSize) or SLOTS
    pageSize = math.floor(pageSize)
    if pageSize < 1 then
        pageSize = 1
    elseif pageSize > 50 then
        pageSize = 50
    end

    return pageSize
end

local function EscapeString(str)
    if not str then return "" end
    return str:gsub("'", "''"):gsub("\\", "\\\\")
end

local function NormalizeVisibleSlot(slot)
    slot = tonumber(slot)
    if not slot then
        return nil
    end

    slot = math.floor(slot)
    if not VISIBLE_SLOT_SET[slot] then
        return nil
    end

    return slot
end

-- ---------------------------------------------------------------------------
-- Bootstrap: create the required tables if they do not already exist.
-- account_transmog lives in the auth DB; character_transmog in the chars DB.
-- ---------------------------------------------------------------------------
do
    AuthDBQuery([[
        CREATE TABLE IF NOT EXISTS `account_transmog` (
            `account_id`       INT UNSIGNED    NOT NULL,
            `unlocked_item_id` INT UNSIGNED    NOT NULL,
            `display_id`       INT UNSIGNED    NOT NULL DEFAULT 0,
            `inventory_type`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
            `item_name`        VARCHAR(255)    NOT NULL DEFAULT '',
            PRIMARY KEY (`account_id`, `unlocked_item_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    CharDBQuery([[
        CREATE TABLE IF NOT EXISTS `character_transmog` (
            `player_guid` INT UNSIGNED NOT NULL,
            `slot`        INT UNSIGNED NOT NULL,
            `item`        INT UNSIGNED     NULL DEFAULT NULL,
            `real_item`   INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (`player_guid`, `slot`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
-- ---------------------------------------------------------------------------

local ITEM_TEMPLATE_CACHE = {}
local ITEM_SET_TEMPLATE_CACHE = {}
local VIRTUAL_SET_TEMPLATE_CACHE = {}
local ACCOUNT_APPEARANCE_CACHE = {}
local ACCOUNT_ITEM_SET_CATALOG_CACHE = {}

local function InvalidateAccountCaches(accountGUID)
    accountGUID = tonumber(accountGUID)
    if not accountGUID then
        return
    end

    ACCOUNT_APPEARANCE_CACHE[accountGUID] = nil
    ACCOUNT_ITEM_SET_CATALOG_CACHE[accountGUID] = nil
end

local function CreateAccountAppearanceCache(accountGUID)
    local cache = {
        accountId = tonumber(accountGUID) or 0,
        all = {},
        bySlot = {},
        bySlotIndex = {},
        bySlotDisplay = {},
    }

    for _, slot in ipairs(VISIBLE_SLOTS) do
        cache.bySlot[slot] = {}
        cache.bySlotIndex[slot] = {}
        cache.bySlotDisplay[slot] = {}
    end

    return cache
end

local function AddAccountAppearanceRecord(cache, record)
    table.insert(cache.all, record)

    for slot, allowedInventoryTypes in pairs(SLOT_INVENTORY_TYPES) do
        if allowedInventoryTypes[record.inventoryType] then
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
end

local function GetAccountAppearanceCache(accountGUID)
    accountGUID = tonumber(accountGUID)
    if not accountGUID then
        return CreateAccountAppearanceCache(0)
    end

    local cached = ACCOUNT_APPEARANCE_CACHE[accountGUID]
    if cached then
        return cached
    end

    local cache = CreateAccountAppearanceCache(accountGUID)
    local unlockedItems = AuthDBQuery(string.format(
        "SELECT unlocked_item_id, display_id, inventory_type, item_name FROM account_transmog WHERE account_id = %d ORDER BY unlocked_item_id",
        accountGUID
    ))

    if unlockedItems then
        repeat
            local itemId = tonumber(unlockedItems:GetUInt32(0)) or 0
            local displayId = tonumber(unlockedItems:GetUInt32(1)) or 0
            local inventoryType = tonumber(unlockedItems:GetUInt32(2)) or 0
            local itemName = unlockedItems:GetString(3) or ""

            if itemId > 0 and inventoryType > 0 then
                AddAccountAppearanceRecord(cache, {
                    itemId = itemId,
                    displayId = displayId,
                    inventoryType = inventoryType,
                    itemName = itemName,
                    lowerName = string.lower(itemName),
                })
            end
        until not unlockedItems:NextRow()
    end

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

local function GetStoredRealItemId(playerGUID, slot)
    local oldItem = CharDBQuery(string.format(
        "SELECT real_item FROM character_transmog WHERE player_guid = %d AND slot = %d",
        playerGUID, slot
    ))
    if not oldItem then
        return 0
    end

    return tonumber(oldItem:GetUInt32(0)) or 0
end

local function UpsertTransmogSlot(playerGUID, slot, item, realItemId)
    local itemValue = item == nil and "NULL" or tostring(tonumber(item) or 0)
    realItemId = tonumber(realItemId) or 0

    CharDBQuery(string.format(
        "INSERT INTO character_transmog (`player_guid`, `slot`, `item`, `real_item`) VALUES (%d, %d, %s, %d) ON DUPLICATE KEY UPDATE item = VALUES(item), real_item = VALUES(real_item)",
        playerGUID, slot, itemValue, realItemId
    ))
end

local function GetItemTemplateInfo(itemId)
    itemId = tonumber(itemId)
    if not itemId or itemId <= 0 then
        return nil
    end

    local cached = ITEM_TEMPLATE_CACHE[itemId]
    if cached then
        return cached
    end

    local query = WorldDBQuery(string.format(
        "SELECT itemset, InventoryType, name, displayid FROM item_template WHERE entry = %u LIMIT 1",
        itemId
    ))
    if not query then
        return nil
    end

    cached = {
        itemset = tonumber(query:GetUInt32(0)) or 0,
        inventoryType = tonumber(query:GetUInt32(1)) or 0,
        name = query:GetString(2) or "",
        displayId = tonumber(query:GetUInt32(3)) or 0,
    }

    ITEM_TEMPLATE_CACHE[itemId] = cached
    return cached
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

local function GetVirtualSetTemplate(baseName)
    baseName = tostring(baseName or ""):gsub("%s+$", "")
    if baseName == "" then
        return nil
    end

    local cached = VIRTUAL_SET_TEMPLATE_CACHE[baseName]
    if cached then
        return cached
    end

    local safeBaseName = EscapeString(baseName):gsub("%%", "\\%%"):gsub("_", "\\_")
    local query = WorldDBQuery(string.format(
        "SELECT entry, name, InventoryType FROM item_template WHERE InventoryType IN (1,3,4,5,6,7,8,9,10,16,19,20) AND name LIKE '%s %%' ORDER BY entry",
        safeBaseName
    ))
    if not query then
        return nil
    end

    local fullItems = {}
    local itemNames = {}
    local totalCount = 0

    repeat
        local entry = tonumber(query:GetUInt32(0)) or 0
        local name = query:GetString(1) or ""
        local inventoryType = tonumber(query:GetUInt32(2)) or 0
        local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[inventoryType]

        if slotIndex and IsArmorSetSlotIndex(slotIndex) and GetVirtualSetBaseName(name) == baseName then
            if not fullItems[slotIndex] or fullItems[slotIndex] == 0 then
                fullItems[slotIndex] = entry
                totalCount = totalCount + 1
                table.insert(itemNames, name)
            end
        end
    until not query:NextRow()

    if totalCount == 0 then
        return nil
    end

    for index = 1, #APPEARANCE_SET_SLOTS do
        fullItems[index] = tonumber(fullItems[index]) or 0
    end

    cached = {
        id = GetVirtualSetId(baseName),
        name = DeriveItemSetName(itemNames),
        fullItems = fullItems,
        totalCount = totalCount,
    }

    VIRTUAL_SET_TEMPLATE_CACHE[baseName] = cached
    return cached
end

local function GetItemSetTemplate(itemsetId)
    itemsetId = tonumber(itemsetId)
    if not itemsetId or itemsetId <= 0 then
        return nil
    end

    local cached = ITEM_SET_TEMPLATE_CACHE[itemsetId]
    if cached then
        return cached
    end

    local query = WorldDBQuery(string.format(
        "SELECT entry, name, InventoryType FROM item_template WHERE itemset = %u ORDER BY entry",
        itemsetId
    ))
    if not query then
        return nil
    end

    local fullItems = {}
    local itemNames = {}
    local totalCount = 0

    repeat
        local entry = tonumber(query:GetUInt32(0)) or 0
        local name = query:GetString(1) or ""
        local inventoryType = tonumber(query:GetUInt32(2)) or 0
        local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[inventoryType]

        if slotIndex and (not fullItems[slotIndex] or fullItems[slotIndex] == 0) then
            fullItems[slotIndex] = entry
            totalCount = totalCount + 1
            table.insert(itemNames, name)
        end
    until not query:NextRow()

    if totalCount == 0 then
        return nil
    end

    for index = 1, #APPEARANCE_SET_SLOTS do
        fullItems[index] = tonumber(fullItems[index]) or 0
    end

    cached = {
        id = itemsetId,
        name = DeriveItemSetName(itemNames),
        fullItems = fullItems,
        totalCount = totalCount,
    }

    ITEM_SET_TEMPLATE_CACHE[itemsetId] = cached
    return cached
end

local function GetUnlockedAppearanceItemId(accountGUID, slot, itemId)
    itemId = tonumber(itemId)
    slot = NormalizeVisibleSlot(slot)
    if not itemId or itemId <= 0 or not slot then
        return nil
    end

    local inventoryTypes = INVENTORY_TYPE_MAP[slot]
    local itemTemplate = GetItemTemplateInfo(itemId)
    if not inventoryTypes or not itemTemplate then
        return nil
    end

    local displayId = tonumber(itemTemplate.displayId)
    if not displayId or displayId <= 0 then
        return nil
    end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local displayBucket = appearanceCache.bySlotDisplay[slot][displayId]
    if not displayBucket then
        return nil
    end

    if displayBucket.items[itemId] then
        return itemId
    end

    return tonumber(displayBucket.firstItemId) or nil
end

local function IsAppearanceUnlocked(accountGUID, slot, itemId)
    return GetUnlockedAppearanceItemId(accountGUID, slot, itemId) ~= nil
end

local function BuildAccountItemSetCatalog(accountGUID)
    accountGUID = tonumber(accountGUID)
    if not accountGUID then
        return {}
    end

    local cachedCatalog = ACCOUNT_ITEM_SET_CATALOG_CACHE[accountGUID]
    if cachedCatalog then
        return cachedCatalog
    end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local grouped = {}

    for _, record in ipairs(appearanceCache.all) do
        local itemId = tonumber(record.itemId) or 0
        local itemTemplate = GetItemTemplateInfo(itemId)
        if itemTemplate then
            local slotIndex = INVENTORY_TYPE_TO_SLOT_INDEX[itemTemplate.inventoryType]
            local groupKey = nil
            local groupId = nil
            local groupName = nil
            local setTemplate = nil
            local isVirtual = false
            local hasExactTotal = false

            if itemTemplate.itemset and itemTemplate.itemset > 0 then
                setTemplate = slotIndex and GetItemSetTemplate(itemTemplate.itemset) or nil
                if slotIndex and setTemplate then
                    groupKey = "itemset:"..itemTemplate.itemset
                    groupId = itemTemplate.itemset
                    groupName = setTemplate.name
                    hasExactTotal = true
                end
            elseif IsArmorSetSlotIndex(slotIndex) then
                local baseName = GetVirtualSetBaseName(record.itemName or itemTemplate.name)
                if baseName then
                    setTemplate = GetVirtualSetTemplate(baseName)
                    groupKey = "virtual:"..baseName
                    groupId = GetVirtualSetId(baseName)
                    groupName = setTemplate and setTemplate.name or baseName
                    isVirtual = true
                    hasExactTotal = setTemplate ~= nil
                end
            end

            if groupKey then
                local group = grouped[groupKey]
                if not group then
                    group = {
                        id = groupId,
                        name = groupName,
                        displayName = groupName,
                        fullItems = {},
                        unlockedItems = {},
                        unlockedCount = 0,
                        totalCount = setTemplate and (tonumber(setTemplate.totalCount) or 0) or 0,
                        isVirtual = isVirtual,
                        hasExactTotal = hasExactTotal,
                    }

                    for index = 1, #APPEARANCE_SET_SLOTS do
                        group.fullItems[index] = setTemplate and (tonumber(setTemplate.fullItems[index]) or 0) or 0
                        group.unlockedItems[index] = 0
                    end

                    grouped[groupKey] = group
                end

                if group.unlockedItems[slotIndex] == 0 then
                    group.unlockedItems[slotIndex] = itemId
                    group.unlockedCount = group.unlockedCount + 1

                    if group.fullItems[slotIndex] == 0 then
                        group.fullItems[slotIndex] = itemId
                        if group.isVirtual then
                            group.totalCount = group.totalCount + 1
                        end
                    end
                end
            end
        end
    end

    local result = {}
    for _, group in pairs(grouped) do
        local minimumPieces = group.isVirtual and 3 or 1
        if group.totalCount > 0 and group.unlockedCount >= minimumPieces then
            if group.isVirtual and not group.hasExactTotal then
                group.displayName = string.format("%s (%d pieces)", group.name, group.unlockedCount)
            else
                group.displayName = string.format("%s (%d/%d)", group.name, group.unlockedCount, group.totalCount)
            end
            table.insert(result, group)
        end
    end

    table.sort(result, function(a, b)
        if a.name == b.name then
            return tonumber(a.id) < tonumber(b.id)
        end
        return tostring(a.name) < tostring(b.name)
    end)

    ACCOUNT_ITEM_SET_CATALOG_CACHE[accountGUID] = result
    return result
end

local function CalculateSlot(slot)
    if slot == 0 then
        slot = 1
    elseif slot >= 2 then
        slot = slot + 1
    end
    return CALC + (slot * 2)
end

local function CalculateSlotReverse(slot)
    local reverseSlot = (slot - CALC) / 2
    if reverseSlot == 1 then
        return 0
    end
    return reverseSlot
end

local function InitializePlayerTransmog(playerGUID)
    local values = {}
    for _, slot in ipairs(VISIBLE_SLOTS) do
        table.insert(values, string.format("(%d, %d, NULL, 0)", playerGUID, slot))
    end
    CharDBQuery("INSERT IGNORE INTO character_transmog (player_guid, slot, item, real_item) VALUES " .. table.concat(values, ", "))
end

local function AddTransmogToAccount(player, itemTemplate)
    local accountGUID = player:GetAccountId()
    local itemId = itemTemplate:GetItemId()
    local displayId = itemTemplate:GetDisplayId()
    local inventoryType = itemTemplate:GetInventoryType()
    local itemName = EscapeString(itemTemplate:GetName())
    
    local query = string.format(
        "INSERT IGNORE INTO account_transmog (account_id, unlocked_item_id, display_id, inventory_type, item_name) " ..
        "VALUES (%d, %d, %d, %d, '%s')",
        accountGUID, itemId, displayId, inventoryType, itemName
    )
    AuthDBQuery(query)
    InvalidateAccountCaches(accountGUID)
end

local function IsTransmoggableItem(class, inventoryType)
    return (class == 2 or class == 4) and not UNUSABLE_INVENTORY_TYPES[inventoryType]
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

local function QueueTransmogToAccount(player, itemTemplate, values, seenItemIds)
    if not player or not itemTemplate or type(values) ~= "table" then
        return false
    end

    local accountGUID = player:GetAccountId()
    local itemId = itemTemplate:GetItemId()
    if seenItemIds and seenItemIds[itemId] then
        return false
    end

    local displayId = itemTemplate:GetDisplayId()
    local inventoryType = itemTemplate:GetInventoryType()
    local itemName = EscapeString(itemTemplate:GetName())
    values[#values + 1] = string.format("(%d, %d, %d, %d, '%s')", accountGUID, itemId, displayId, inventoryType, itemName)

    if seenItemIds then
        seenItemIds[itemId] = true
    end

    return true
end

local function TryUnlockAppearanceFromItem(player, item, values, seenItemIds)
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
        return QueueTransmogToAccount(player, itemTemplate, values, seenItemIds)
    end

    AddTransmogToAccount(player, itemTemplate)
    return true
end

local function ScanPlayerInventoryForTransmogUnlocks(player)
    if not player then
        return
    end

    local accountGUID = player:GetAccountId()
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

        TryUnlockAppearanceFromItem(player, item, values, seenItemIds)
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
        AuthDBQuery(
            "INSERT IGNORE INTO account_transmog (account_id, unlocked_item_id, display_id, inventory_type, item_name) VALUES "
            .. table.concat(values, ", ")
        )
        InvalidateAccountCaches(accountGUID)
    end
end

function Transmog_OnCharacterCreate(event, player)
    InitializePlayerTransmog(player:GetGUIDLow())
end

function Transmog_OnCharacterDelete(event, guid)
    CharDBQuery("DELETE FROM character_transmog WHERE player_guid = " .. guid)
end

function Transmog_OnLootItem(event, player, item, count)
    -- Event 32 can expose unstable item userdata when other scripts mutate loot.
    -- Process only on post-store/create/reward style events.
    if event == 32 then return end
    if event ~= 51 and event ~= 52 and event ~= 53 and event ~= 56 then return end
    if not player or not item or not item.GetItemTemplate then return end

    local okTpl, tpl = pcall(item.GetItemTemplate, item)
    if not okTpl or not tpl then return end

    local okClass, class       = pcall(tpl.GetClass, tpl)
    local okType,  inventoryType = pcall(tpl.GetInventoryType, tpl)
    if not okClass or not okType then return end

    if IsTransmoggableItem(class, inventoryType) then
        AddTransmogToAccount(player, tpl)
    end
end

function Transmog_OnEquipItem(event, player, item, bag, slot)
    local playerGUID   = player:GetGUIDLow()
    local itemTemplate = item:GetItemTemplate()
    local class        = item:GetClass()
    local inventoryType = itemTemplate:GetInventoryType()

    if not IsTransmoggableItem(class, inventoryType) then return end

    AddTransmogToAccount(player, itemTemplate)

    local constSlot = CalculateSlot(slot)
    local itemId    = itemTemplate:GetItemId()

    CharDBQuery(string.format(
        "INSERT INTO character_transmog (`player_guid`, `slot`, `real_item`) VALUES (%d, %d, %d) ON DUPLICATE KEY UPDATE real_item = VALUES(real_item)",
        playerGUID, constSlot, itemId
    ))

    local transmog = CharDBQuery(string.format(
        "SELECT item FROM character_transmog WHERE player_guid = %d AND slot = %d AND item IS NOT NULL",
        playerGUID, constSlot
    ))
    if not transmog then return end

    local transmogItem = transmog:GetUInt32(0)
    if not transmogItem or (transmogItem == 0 and player:GetUInt32Value(147) ~= 1) then return end

    player:SetUInt32Value(constSlot, transmogItem)
end

function TransmogHandlers.OnUnequipItem(player)
    local playerGUID = player:GetGUIDLow()

    local transmogs = CharDBQuery(string.format(
        "SELECT slot, item, real_item FROM character_transmog WHERE player_guid = %d AND item IS NOT NULL",
        playerGUID
    ))
    if not transmogs then return end

    repeat
        local row  = transmogs:GetRow()
        local slot = tonumber(row["slot"])
        if slot and player:GetUInt32Value(slot) == 0 then
            local item     = tonumber(row["item"]) or 0
            local realItem = tonumber(row["real_item"]) or 0
            UpsertTransmogSlot(playerGUID, slot, item, realItem)
            player:SetUInt32Value(slot, item)
        end
    until not transmogs:NextRow()
end

function Transmog_Load(player)
    local playerGUID = player:GetGUIDLow()

    local transmogs = CharDBQuery(string.format(
        "SELECT slot, item FROM character_transmog WHERE player_guid = %d",
        playerGUID
    ))
    if not transmogs then
        AIO.Handle(player, "Transmog", "LoadTransmogsAfterSave")
        return
    end

    repeat
        local row  = transmogs:GetRow()
        local item = row["item"]
        if item ~= nil and item ~= '' then
            player:SetUInt32Value(tonumber(row["slot"]), item)
        end
    until not transmogs:NextRow()

    AIO.Handle(player, "Transmog", "LoadTransmogsAfterSave")
end

function TransmogHandlers.LoadPlayer(player)
    InitializePlayerTransmog(player:GetGUIDLow())
    ScanPlayerInventoryForTransmogUnlocks(player)
    Transmog_Load(player)
    player:SetUInt32Value(147, 1)
end

function TransmogHandlers.ScanInventoryUnlocks(player)
    ScanPlayerInventoryForTransmogUnlocks(player)
end

function TransmogHandlers.EquipTransmogItem(player, item, slot)
    local playerGUID = player:GetGUIDLow()
    slot = NormalizeVisibleSlot(slot)
    if not slot then
        return
    end

    if item ~= nil then
        item = tonumber(item) or 0
    end

    local oldItemId = GetStoredRealItemId(playerGUID, slot)

    if item == nil then
        UpsertTransmogSlot(playerGUID, slot, nil, oldItemId)
        player:SetUInt32Value(slot, oldItemId)
        return
    end

    if item == 0 then
        UpsertTransmogSlot(playerGUID, slot, 0, oldItemId)
        player:SetUInt32Value(slot, 0)
        return
    end

    UpsertTransmogSlot(playerGUID, slot, item, oldItemId)
    player:SetUInt32Value(slot, item)
end

function TransmogHandlers.ApplyAppearanceSet(player, itemIds)
    if type(itemIds) ~= "table" then
        AIO.Handle(player, "Transmog", "AppearanceSetResult", 0, 0, "", 0)
        return
    end

    local playerGUID = player:GetGUIDLow()
    local accountGUID = player:GetAccountId()
    local appliedCount = 0
    local hiddenCount = 0
    local restoredCount = 0
    local missingSlots = {}

    for index, info in ipairs(APPEARANCE_SET_SLOTS) do
        local requestedItemId = tonumber(itemIds[index]) or -1
        local realItemId = GetStoredRealItemId(playerGUID, info.slot)

        if requestedItemId < 0 then
            UpsertTransmogSlot(playerGUID, info.slot, nil, realItemId)
            player:SetUInt32Value(info.slot, realItemId)
            restoredCount = restoredCount + 1
        elseif requestedItemId == 0 then
            UpsertTransmogSlot(playerGUID, info.slot, 0, realItemId)
            player:SetUInt32Value(info.slot, 0)
            hiddenCount = hiddenCount + 1
        else
            local unlockedItemId = GetUnlockedAppearanceItemId(accountGUID, info.slot, requestedItemId)
            if unlockedItemId then
                UpsertTransmogSlot(playerGUID, info.slot, unlockedItemId, realItemId)
                player:SetUInt32Value(info.slot, unlockedItemId)
                appliedCount = appliedCount + 1
            else
                table.insert(missingSlots, info.name)
            end
        end
    end

    TransmogHandlers.SetTransmogItemIds(player)
    AIO.Handle(player, "Transmog", "AppearanceSetResult", appliedCount, hiddenCount, table.concat(missingSlots, ", "), restoredCount)
end

function TransmogHandlers.GetUnlockedItemSets(player)
    AIO.Handle(player, "Transmog", "InitItemSets", BuildAccountItemSetCatalog(player:GetAccountId()))
end

function TransmogHandlers.ApplyUnlockedItemSet(player, itemsetId)
    itemsetId = tonumber(itemsetId)
    if not itemsetId or itemsetId == 0 then
        AIO.Handle(player, "Transmog", "UnlockedItemSetResult", "Item set", 0, "")
        return
    end

    local selectedSet = nil
    for _, setData in ipairs(BuildAccountItemSetCatalog(player:GetAccountId())) do
        if tonumber(setData.id) == itemsetId then
            selectedSet = setData
            break
        end
    end

    if not selectedSet then
        AIO.Handle(player, "Transmog", "UnlockedItemSetResult", "Item set", 0, "")
        return
    end

    local playerGUID = player:GetGUIDLow()
    local appliedCount = 0
    local hiddenCount = 0
    local missingSlots = {}

    for index, info in ipairs(APPEARANCE_SET_SLOTS) do
        local unlockedItemId = tonumber(selectedSet.unlockedItems[index]) or 0
        local previewItemId = tonumber(selectedSet.fullItems[index]) or 0
        local realItemId = GetStoredRealItemId(playerGUID, info.slot)

        if unlockedItemId > 0 then
            UpsertTransmogSlot(playerGUID, info.slot, unlockedItemId, realItemId)
            player:SetUInt32Value(info.slot, unlockedItemId)
            appliedCount = appliedCount + 1
        elseif previewItemId <= 0 and IsArmorSetSlotIndex(index) then
            UpsertTransmogSlot(playerGUID, info.slot, 0, realItemId)
            player:SetUInt32Value(info.slot, 0)
            hiddenCount = hiddenCount + 1
        elseif previewItemId > 0 then
            table.insert(missingSlots, info.name)
        end
    end

    TransmogHandlers.SetTransmogItemIds(player)
    AIO.Handle(player, "Transmog", "UnlockedItemSetResult", selectedSet.name, appliedCount, hiddenCount, table.concat(missingSlots, ", "))
end

function TransmogHandlers.UnequipTransmogItem(player, slot)
    local playerGUID = player:GetGUIDLow()
    slot = NormalizeVisibleSlot(slot)
    if not slot then
        return
    end

    local oldItemId = GetStoredRealItemId(playerGUID, slot)
    UpsertTransmogSlot(playerGUID, slot, 0, oldItemId)
    player:SetUInt32Value(slot, 0)
end

function TransmogHandlers.displayTransmog(player, spellid)
    AIO.Handle(player, "Transmog", "TransmogFrame")
    return false
end

function TransmogHandlers.SetTransmogItemIds(player)
    local playerGUID = player:GetGUIDLow()

    local transmogs = CharDBQuery(string.format(
        "SELECT slot, item, real_item FROM character_transmog WHERE player_guid = %d",
        playerGUID
    ))
    if not transmogs then return end

    repeat
        local row  = transmogs:GetRow()
        local slot = NormalizeVisibleSlot(row["slot"])
        if slot then
            local item = row["item"]
            if item == '' then
                item = nil
            elseif item ~= nil then
                item = tonumber(item) or 0
            end
            AIO.Handle(player, "Transmog", "SetTransmogItemIdClient", slot, item, tonumber(row["real_item"]) or 0)
        end
    until not transmogs:NextRow()
end

local function BuildPagedItemIds(records, page, pageSize)
    local pageOffset = (page > 1) and (pageSize * (page - 1)) or 0
    local result = {}
    local total = #records

    if pageOffset >= total then
        return result, false
    end

    local lastIndex = math.min(total, pageOffset + pageSize)
    for index = pageOffset + 1, lastIndex do
        result[#result + 1] = tonumber(records[index].itemId) or 0
    end

    return result, total > lastIndex
end

local function SearchAppearanceRecords(records, search)
    local normalizedSearch = string.lower(tostring(search or ""))
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

function TransmogHandlers.SetCurrentSlotItemPage(player, slot, itemId, pageSize, requestToken)
    local accountGUID = player:GetAccountId()
    slot = NormalizeVisibleSlot(slot)
    itemId = tonumber(itemId) or 0
    pageSize = NormalizePageSize(pageSize)

    if not slot or itemId <= 0 then
        AIO.Handle(player, "Transmog", "SetCurrentSlotItemPageClient", slot or 0, 1, requestToken)
        return
    end

    local inventoryTypes = INVENTORY_TYPE_MAP[slot]
    local resolvedItemId = inventoryTypes and GetUnlockedAppearanceItemId(accountGUID, slot, itemId) or nil
    if not inventoryTypes or not resolvedItemId or resolvedItemId <= 0 then
        AIO.Handle(player, "Transmog", "SetCurrentSlotItemPageClient", slot, 1, requestToken)
        return
    end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local itemIndex = appearanceCache.bySlotIndex[slot][resolvedItemId]
    local page = itemIndex and (math.floor((itemIndex - 1) / pageSize) + 1) or 1
    AIO.Handle(player, "Transmog", "SetCurrentSlotItemPageClient", slot, page, requestToken)
end

function TransmogHandlers.SetCurrentSlotItemIds(player, slot, page, pageSize, requestToken)
    local accountGUID = player:GetAccountId()
    slot = NormalizeVisibleSlot(slot)
    page = NormalizePage(page)
    if requestToken == nil then
        requestToken = pageSize
        pageSize = SLOTS
    end
    pageSize = NormalizePageSize(pageSize)

    local inventoryTypes = INVENTORY_TYPE_MAP[slot]
    
    if not inventoryTypes then return end

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local slotRecords = appearanceCache.bySlot[slot] or {}
    local currentSlotItemIds, hasMorePages = BuildPagedItemIds(slotRecords, page, pageSize)

    AIO.Handle(player, "Transmog", "InitTab", currentSlotItemIds, page, hasMorePages, slot, requestToken)
end

function TransmogHandlers.SetSearchCurrentSlotItemIds(player, slot, page, search, pageSize, requestToken)
    if not search or search == '' then return end

    slot = NormalizeVisibleSlot(slot)
    page = NormalizePage(page)
    if requestToken == nil then
        requestToken = pageSize
        pageSize = SLOTS
    end
    pageSize = NormalizePageSize(pageSize)

    local inventoryTypes = INVENTORY_TYPE_MAP[slot]
    
    if not inventoryTypes then return end
    local accountGUID = player:GetAccountId()

    local appearanceCache = GetAccountAppearanceCache(accountGUID)
    local slotRecords = appearanceCache.bySlot[slot] or {}
    local matches = SearchAppearanceRecords(slotRecords, search)
    local currentSlotItemIds, hasMorePages = BuildPagedItemIds(matches, page, pageSize)

    AIO.Handle(player, "Transmog", "InitTab", currentSlotItemIds, page, hasMorePages, slot, requestToken)
end

function TransmogHandlers.SetEquipmentTransmogInfo(player, slot, currentTooltipSlot)
    slot = NormalizeVisibleSlot(slot)
    if not slot then return end

    local transmog = CharDBQuery(string.format(
        "SELECT COUNT(*) FROM character_transmog WHERE player_guid = %d AND slot = %d AND item IS NOT NULL AND item != 0",
        player:GetGUIDLow(), slot
    ))

    if transmog and transmog:GetUInt32(0) > 0 then
        AIO.Handle(player, "Transmog", "SetEquipmentTransmogInfoClient", currentTooltipSlot)
    end
end

RegisterPlayerEvent(1, Transmog_OnCharacterCreate)
RegisterPlayerEvent(2, Transmog_OnCharacterDelete)
RegisterPlayerEvent(32, Transmog_OnLootItem)
RegisterPlayerEvent(51, Transmog_OnLootItem)
RegisterPlayerEvent(52, Transmog_OnLootItem)
RegisterPlayerEvent(53, Transmog_OnLootItem)
RegisterPlayerEvent(56, Transmog_OnLootItem)
RegisterPlayerEvent(29, Transmog_OnEquipItem)
