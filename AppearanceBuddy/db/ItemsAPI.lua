local _, ns = ...

local FORMAT_VERSION = 1
local index = assert(ns.itemAppearanceIndex, "AppearanceBuddy item index was not loaded")
local slotIds = assert(ns.itemAppearanceSlotIds, "AppearanceBuddy slot index was not loaded")
local subclassNames = assert(ns.itemAppearanceSubclassNames, "AppearanceBuddy subclass index was not loaded")
local keyBase = assert(ns.itemAppearanceKeyBase, "AppearanceBuddy item key base was not loaded")

assert(ns.itemAppearanceFormatVersion == FORMAT_VERSION, "Unsupported AppearanceBuddy item index format")

local floor = math.floor

local function lookupAppearance(slotName, itemId)
    local slotId = slotIds[slotName]
    if not slotId or itemId ~= itemId or itemId <= 0 or itemId >= keyBase or itemId ~= floor(itemId) then
        return nil
    end

    local key = (slotId - 1) * keyBase + itemId
    local encoded = index[key]
    if not encoded then
        return nil
    end

    local canonicalItemId = encoded % keyBase
    local subclassId = (encoded - canonicalItemId) / keyBase
    return canonicalItemId, subclassNames[subclassId]
end

-- O(1) canonical-appearance lookup. This is the addon's sole item-index API.
function ns.FindAppearance(slotName, itemId)
    assert(type(slotName) == "string", "'slotName' must be a string")
    assert(type(itemId) == "number", "'itemId' must be a number")
    return lookupAppearance(slotName, itemId)
end
