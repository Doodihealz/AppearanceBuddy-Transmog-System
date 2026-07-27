local _, ns = ...

-- Pure validation for values received over AIO. Keep transport data outside
-- live UI state until an entire response has passed its contract.
local Wire = {}
ns.TransmogWire = Wire

local floor = math.floor
local huge = math.huge

function Wire.Value(values, key)
    if type(values) ~= "table" then
        return nil
    end

    local value = values[key]
    if value == nil then
        value = values[tostring(key)]
    end
    return value
end

function Wire.Integer(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value <= -huge or value >= huge
        or value ~= floor(value) or value < minimum or value > maximum then
        return nil
    end
    return value
end

function Wire.Number(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value <= -huge or value >= huge
        or value < minimum or value > maximum then
        return nil
    end
    return value
end

function Wire.Boolean(value)
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    return nil
end

function Wire.Text(value, maxLength, allowEmpty)
    if type(value) ~= "string" or #value > maxLength then
        return nil
    end

    value = value:gsub("[%c|]", " ")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    if not allowEmpty and value == "" then
        return nil
    end
    return value
end

local function getArrayIndex(key, maxCount)
    local index
    if type(key) == "number" then
        index = Wire.Integer(key, 1, maxCount)
    elseif type(key) == "string" and key:match("^[1-9]%d*$") then
        index = tonumber(key)
        if not index or index > maxCount or tostring(index) ~= key then
            return nil
        end
    end
    return index
end

-- Accept numeric or canonical decimal keys because AIO versions may preserve
-- array keys differently. Mixed duplicate representations are rejected.
function Wire.IntegerArray(values, maxCount, minimum, maximum, exactCount)
    if type(values) ~= "table" then
        return nil
    end

    local staged = {}
    local seen = {}
    local count = 0
    local highest = 0
    for key, value in pairs(values) do
        local index = getArrayIndex(key, maxCount)
        local integer = Wire.Integer(value, minimum, maximum)
        if not index or integer == nil or seen[index] then
            return nil
        end

        seen[index] = true
        staged[index] = integer
        count = count + 1
        if index > highest then
            highest = index
        end
    end

    local requiredCount = exactCount or count
    if count ~= requiredCount or highest ~= requiredCount then
        return nil
    end
    for index = 1, requiredCount do
        if not seen[index] then
            return nil
        end
    end
    return staged, count
end

function Wire.PairedItemArrays(fullItems, unlockedItems, exactCount)
    exactCount = Wire.Integer(exactCount, 1, 50)
    if not exactCount then return nil end

    local stagedFullItems = Wire.IntegerArray(
        fullItems,
        exactCount,
        0,
        4294967295,
        exactCount
    )
    local stagedUnlockedItems = Wire.IntegerArray(
        unlockedItems,
        exactCount,
        0,
        4294967295,
        exactCount
    )
    if not stagedFullItems or not stagedUnlockedItems then return nil end

    for index = 1, exactCount do
        if stagedFullItems[index] == 0 and stagedUnlockedItems[index] ~= 0 then
            return nil
        end
    end
    return stagedFullItems, stagedUnlockedItems
end

function Wire.TransmogSlotState(record)
    if type(record) ~= "table" then return nil end

    local mode = record.mode
    local realItemId = Wire.Integer(record.realItemId, 0, 4294967295)
    local itemId = Wire.Integer(record.itemId, 0, 4294967295)
    if (mode ~= "original" and mode ~= "hidden" and mode ~= "appearance")
        or realItemId == nil
        or itemId == nil
        or ((mode == "original" or mode == "hidden") and itemId ~= 0)
        or (mode == "appearance" and itemId <= 0) then
        return nil
    end

    local normalizedItemId = itemId
    if mode == "original" then
        normalizedItemId = nil
    end
    return mode, normalizedItemId, realItemId
end

function Wire.StateSyncFailure(requestToken, protocolVersion, errorMessage)
    local token = Wire.Integer(requestToken, 0, 2147483647)
    local version = Wire.Integer(protocolVersion, 2, 2)
    local message = Wire.Text(errorMessage, 192, false)
    if token == nil or version == nil or message == nil then
        return nil
    end
    return token, message
end

function Wire.AppearancePage(itemIds, page, hasMore, total, pageSize)
    pageSize = Wire.Integer(pageSize, 1, 50)
    local stagedItems, itemCount
    if pageSize then
        stagedItems, itemCount = Wire.IntegerArray(itemIds, pageSize, 1, 4294967295)
    end
    local stagedPage = Wire.Integer(page, 1, 1000000)
    local stagedHasMore = Wire.Boolean(hasMore)
    local stagedTotal = Wire.Integer(total, 0, 1000000)
    if not stagedItems or not stagedPage or stagedHasMore == nil or not stagedTotal then
        return nil
    end

    local offset = (stagedPage - 1) * pageSize
    if stagedTotal == 0 then
        if stagedPage ~= 1 or itemCount ~= 0 or stagedHasMore then
            return nil
        end
    else
        if offset >= stagedTotal then
            return nil
        end
        local expectedCount = math.min(pageSize, stagedTotal - offset)
        if itemCount ~= expectedCount
            or stagedHasMore ~= (offset + itemCount < stagedTotal) then
            return nil
        end
    end

    return stagedItems, stagedPage, stagedHasMore, stagedTotal
end

return Wire
