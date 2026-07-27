local addon, ns = ...
local previewSetup = ns.previewSetup

-- The worgoblin module exposes Cataclysm race file names through UnitRace on
-- a 3.3.5 client. Reuse the closest calibrated WotLK model profiles instead
-- of duplicating the large generated preview database.
local RACE_FILE_NAME_FALLBACKS = {
    Goblin = "Gnome",
    Worgen = "NightElf",
}
local DEFAULT_RACE_FILE_NAME = "Human"
local SUPPORTED_RACE_FILE_NAMES = {
    BloodElf = true,
    Draenei = true,
    Dwarf = true,
    Gnome = true,
    Human = true,
    NightElf = true,
    Orc = true,
    Scourge = true,
    Tauren = true,
    Troll = true,
}

function ns.ResolveAppearanceRace(raceFileName)
    if type(raceFileName) ~= "string" then
        return DEFAULT_RACE_FILE_NAME
    end

    local resolvedRaceFileName = RACE_FILE_NAME_FALLBACKS[raceFileName] or raceFileName
    if SUPPORTED_RACE_FILE_NAMES[resolvedRaceFileName] then
        return resolvedRaceFileName
    end
    return DEFAULT_RACE_FILE_NAME
end


local function startsWith(value, ...)
    assert(type(value) == "string", "startsWith(value, ...) - value must be a string")
    for i = 1, select("#", ...) do
        local prefix = select(i, ...)
        assert(type(prefix) == "string", "startsWith(value, ...) - prefix must be a string")
        if value:sub(1, prefix:len()) == prefix then
            return true
        end
    end
    return false
end


function ns.GetPreviewSetup(version, raceFileName, sex, slot, subclass)
	local versionSetup = previewSetup[version]
	assert(versionSetup ~= nil, "'version' is mandatory and must be either 'classic' or 'modern'.")
	assert(type(raceFileName) == "string", "'raceFileName' is mandatory and must be string.")
	assert(type(sex) == "number", "'sex' is mandatory and must be int.")
	assert(type(slot) == "string", "'slot' is mandatory and must be string.")
	local raceSetup = versionSetup[ns.ResolveAppearanceRace(raceFileName)]
	local sexSetup = raceSetup[sex] or raceSetup[2]
	if sexSetup[slot] == nil then
		return sexSetup["Armor"][slot]
	else
		assert(type(subclass) == "string", "'subclass' is mandatory and must be string.")
		if startsWith(subclass, "1H", "MH", "OH") then
			subclass = subclass:sub(4)
		end
		return sexSetup[slot][subclass]
	end
end
