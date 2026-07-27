local addon, ns = ...

local mainFrameTitle = "|cffd6aa16Transmogrify|r"

local _, raceFileName = UnitRace("player")
local _, classFileName = UnitClass("player")

local previewSetupVersion = "classic"

local armorSlots = {"Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet"}
local backSlot = "Back"
local miscellaneousSlots = {"Tabard", "Shirt"}
local mainHandSlot = "Main Hand"
local offHandSlot = "Off-hand"
local rangedSlot = "Ranged"

local addonMessagePrefix = "AppearanceBuddy"
-- Used in look saving/sending. Changing will break compatibility.
local slotOrder = { "Head", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet", "Main Hand", "Off-hand", "Ranged",}
local MAX_SHARED_APPEARANCE_PAYLOAD_LENGTH = 160
local MAX_SHARED_APPEARANCE_ITEM_ID = 4294967295

local slotTextures = {
    ["Head"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-head",
    ["Shoulder"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-shoulder",
    ["Back"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Chest"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-chest",
    ["Shirt"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-shirt",
    ["Tabard"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-tabard",
    ["Wrist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-wrists",
    ["Hands"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-hands",
    ["Waist"] =     "Interface\\Paperdoll\\ui-paperdoll-slot-waist",
    ["Legs"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-legs",
    ["Feet"] =      "Interface\\Paperdoll\\ui-paperdoll-slot-feet",
    ["Main Hand"] = "Interface\\Paperdoll\\ui-paperdoll-slot-mainhand",
    ["Off-hand"] =  "Interface\\Paperdoll\\ui-paperdoll-slot-secondaryhand",
    ["Ranged"] =    "Interface\\Paperdoll\\ui-paperdoll-slot-ranged",
}

local FALLBACK_SLOT_TEXTURE = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Transmog renders empty equipment through ItemButtonTemplate's icon region so
-- themed backdrops cannot cover the slot glyph.
ns.GetSlotPlaceholderTexture = function(slotName)
    return slotTextures[slotName] or FALLBACK_SLOT_TEXTURE
end

local slotSubclasses = {--[[
    ["slot1"] = {subclass1, subclass2, ...},
    ["slot2"] = {subclass1, subclass2, ...},
    ["slot2"] = {subclass1, subclass2, ...},
    ...]]
}

do
    for _, slot in ipairs(armorSlots) do slotSubclasses[slot] = {"Cloth", "Leather", "Mail", "Plate"} end
    for _, slot in ipairs(miscellaneousSlots) do slotSubclasses[slot] = {"Miscellaneous", } end
    slotSubclasses[backSlot] = {"Cloth", }
    slotSubclasses[mainHandSlot] = {
        "1H Axe", "1H Mace", "1H Sword", "1H Dagger", "1H Fist",
        "MH Axe", "MH Mace", "MH Sword", "MH Dagger", "MH Fist",
        "2H Axe", "2H Mace", "2H Sword", "Polearm", "Staff" }
    slotSubclasses[offHandSlot] = { "OH Axe", "OH Mace", "OH Sword", "OH Dagger", "OH Fist", "Shield", "Held in Off-hand"}
    slotSubclasses[rangedSlot] = {"Bow", "Crossbow", "Gun", "Wand", "Thrown"}
end

local defaultSlot = "Head"

local defaultSettings = {
    -- Retained only to keep existing SavedVariables loadable.  Race art is
    -- now selected automatically and no longer reads these manual choices.
    dressingRoomBackgroundColor = {0.6, 0.6, 0.6, 1},
    dressingRoomBackgroundTexture = {
        [GetRealmName()] = {
            [GetUnitName("player")] = raceFileName,
        },
    },
    previewSetup = "classic", -- possible values are "classic" and "modern",
    showAppearanceBuddyButton = true,
    showShortcutsInTooltip = true,
    prefetchItemData = false,
    ignoreUIScaling = false,
    windowLocked = false,
}

local function GetSettings()
    local function copyTable(tableFrom)
        local result = {}
        for k, v in pairs(tableFrom) do
            if type(v) == "table" then
                result[k] = copyTable(v)
            else
                result[k] = v
            end
        end
        return result
    end

    -- Migrate from old DressMe variable name
    if _G["AppearanceBuddySettings"] == nil and type(_G["DressMeSettings"]) == "table" then
        _G["AppearanceBuddySettings"] = copyTable(_G["DressMeSettings"])
        _G["DressMeSettings"] = nil
    end

    local settings = _G["AppearanceBuddySettings"]
    if type(settings) ~= "table" then
        settings = copyTable(defaultSettings)
        _G["AppearanceBuddySettings"] = settings
    end

    -- SavedVariables are user-editable and may also come from older versions.
    -- Normalize every top-level field before any nested indexing can occur.
    for key, defaultValue in pairs(defaultSettings) do
        if type(defaultValue) == "table" then
            if type(settings[key]) ~= "table" then
                settings[key] = copyTable(defaultValue)
            end
        elseif type(settings[key]) ~= type(defaultValue) then
            settings[key] = defaultValue
        end
    end

    if settings.previewSetup ~= "classic" and settings.previewSetup ~= "modern" then
        settings.previewSetup = defaultSettings.previewSetup
    end
    for index = 1, 4 do
        local component = tonumber(settings.dressingRoomBackgroundColor[index])
        if not component or component ~= component or component <= -math.huge or component >= math.huge then
            component = defaultSettings.dressingRoomBackgroundColor[index]
        end
        settings.dressingRoomBackgroundColor[index] = math.max(0, math.min(1, component))
    end

    local realmName = tostring(GetRealmName() or "")
    local playerName = tostring(GetUnitName("player") or "")
    local textures = settings.dressingRoomBackgroundTexture
    if type(textures[realmName]) ~= "table" then
        textures[realmName] = {}
    end
    if type(textures[realmName][playerName]) ~= "string" or textures[realmName][playerName] == "" then
        textures[realmName][playerName] = raceFileName
    end

    return settings
end


local function getManagedScrollFrameParts(scrollFrame)
    if not scrollFrame then
        return nil, nil, nil
    end

    local scrollBar = scrollFrame.ScrollBar
    if not scrollBar and scrollFrame.GetName then
        local frameName = scrollFrame:GetName()
        if frameName and frameName ~= "" then
            scrollBar = _G[frameName.."ScrollBar"]
        end
    end
    if not scrollBar then
        return nil, nil, nil
    end

    local scrollUpButton = scrollBar.ScrollUpButton or _G[scrollBar:GetName().."ScrollUpButton"]
    local scrollDownButton = scrollBar.ScrollDownButton or _G[scrollBar:GetName().."ScrollDownButton"]
    return scrollBar, scrollUpButton, scrollDownButton
end

local function RefreshManagedScrollFrame(scrollFrame, forcedVisibility)
    local scrollBar, scrollUpButton, scrollDownButton = getManagedScrollFrameParts(scrollFrame)
    if not scrollBar then
        return
    end

    local shouldShow
    if forcedVisibility ~= nil then
        shouldShow = forcedVisibility and true or false
    else
        shouldShow = false
        if scrollFrame:IsVisible() then
            local scrollChild = scrollFrame:GetScrollChild()
            local childHeight = scrollChild and tonumber(scrollChild:GetHeight()) or 0
            local frameHeight = tonumber(scrollFrame:GetHeight()) or 0
            shouldShow = childHeight > frameHeight + 1
        end
    end

    if shouldShow then scrollBar:Show() else scrollBar:Hide() end
    if scrollUpButton then
        if shouldShow then scrollUpButton:Show() else scrollUpButton:Hide() end
    end
    if scrollDownButton then
        if shouldShow then scrollDownButton:Show() else scrollDownButton:Hide() end
    end

    if not shouldShow and scrollFrame.SetVerticalScroll then
        scrollFrame:SetVerticalScroll(0)
    end
end

local function IsWindowLocked()
    return GetSettings().windowLocked and true or false
end


local mainFrame = CreateFrame("Frame", addon, UIParent)
local function UpdateReferenceScale()
    local parentWidth = tonumber(UIParent and UIParent:GetWidth()) or 0
    local parentHeight = tonumber(UIParent and UIParent:GetHeight()) or 0
    local widthScale = parentWidth > 0 and (parentWidth * 0.85 / 1090) or 1
    local heightScale = parentHeight > 0 and (parentHeight * 0.82 / 590) or 1
    -- The reference occupies roughly 84% x 82% of its viewport.  A detached
    -- frame (the legacy "Ignore UI scaling" option) otherwise expands to
    -- almost the entire screen on a 0.64 UI scale.
    local preferredScale = GetSettings().ignoreUIScaling and 0.85 or 1
    local scale = math.min(preferredScale, widthScale, heightScale)
    mainFrame:SetScale(math.max(0.62, scale))
end
mainFrame.UpdateReferenceScale = UpdateReferenceScale
-- Register Escape-key dismissal through the standard UI special-frame list.
table.insert(UISpecialFrames, mainFrame:GetName())
do 
    mainFrame:SetWidth(1090)
    mainFrame:SetHeight(590)
    mainFrame:SetPoint("CENTER")
    mainFrame:Hide()
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if not IsWindowLocked() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    local tempEnchantVisibility = {}
    mainFrame:SetScript("OnShow", function()
        UpdateReferenceScale()
        PlaySound("igCharacterInfoOpen")
        for _, frameName in ipairs({"TempEnchant1", "TempEnchant2"}) do
            local tempEnchant = _G[frameName]
            tempEnchantVisibility[frameName] = tempEnchant ~= nil and tempEnchant:IsShown() or false
            if tempEnchantVisibility[frameName] then
                tempEnchant:Hide()
            end
        end
    end)
    mainFrame:SetScript("OnHide", function()
        PlaySound("igCharacterInfoClose")
        for _, frameName in ipairs({"TempEnchant1", "TempEnchant2"}) do
            local tempEnchant = _G[frameName]
            if tempEnchantVisibility[frameName] and tempEnchant then
                tempEnchant:Show()
            end
            tempEnchantVisibility[frameName] = nil
        end
    end)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -9)
    title:SetText(mainFrameTitle)
    title:SetTextColor(0.84, 0.66, 0.086)

    local titleBg = mainFrame:CreateTexture(nil, "BACKGROUND")
	titleBg:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Title-Background")
	titleBg:SetPoint("TOPLEFT", 10, -7)
    titleBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPRIGHT", -28, -24)

	-- Keep the two sampled background regions over one continuous opaque fill.
	-- Without it, fractional UI scales can expose the world at their shared edge.
	local windowUnderlay = mainFrame:CreateTexture(nil, "BACKGROUND")
	windowUnderlay:SetTexture("Interface\\Buttons\\WHITE8X8")
	windowUnderlay:SetPoint("TOPLEFT", 6, -26)
	windowUnderlay:SetPoint("BOTTOMRIGHT", -6, 5)
	windowUnderlay:SetVertexColor(0.045, 0.030, 0.028, 1)

	local menuBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    menuBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    menuBg:SetTexCoord(0, 1, 0, 0.8125) 
	menuBg:SetPoint("TOPLEFT", 6, -26)
    menuBg:SetPoint("RIGHT", -6, 0)
    menuBg:SetHeight(48)
    menuBg:SetVertexColor(0.16, 0.10, 0.065)

    local frameBg = mainFrame:CreateTexture(nil, "BACKGROUND")
    frameBg:SetTexture("Interface\\WorldStateFrame\\WorldStateFinalScoreFrame-TopBackground")
    frameBg:SetTexCoord(0, 0.5, 0, 0.8125) 
    -- Overlap the two sampled regions by one UI unit. Their former shared
    -- edge landed between physical pixels at common UI scales and exposed a
    -- hairline exactly along the mode-button baseline.
    frameBg:SetPoint("TOPLEFT", menuBg, "BOTTOMLEFT", 0, 1)
    frameBg:SetPoint("TOPRIGHT", menuBg, "BOTTOMRIGHT", 0, 1)
    frameBg:SetPoint("BOTTOM", 0, 5)
    frameBg:SetVertexColor(0.045, 0.030, 0.028)
	
	local topLeft = mainFrame:CreateTexture(nil, "BORDER")
    topLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    -- Skip two atlas padding texels on every left-side slice. One still let
    -- bilinear filtering sample the neighboring black gutter at fractional
    -- UI scales, which appeared as a dark strip outside the window.
    topLeft:SetTexCoord(0.50390625, 0.625, 0, 1)
	topLeft:SetWidth(64)
	topLeft:SetHeight(64)
	topLeft:SetPoint("TOPLEFT")
	
	local topRight = mainFrame:CreateTexture(nil, "BORDER")
    topRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    topRight:SetTexCoord(0.625, 0.75, 0, 1)
	topRight:SetWidth(64)
	topRight:SetHeight(64)
    topRight:SetPoint("TOPRIGHT")
	
	local top = mainFrame:CreateTexture(nil, "BORDER")
    top:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    top:SetTexCoord(0.25, 0.37, 0, 1)
	top:SetPoint("TOPLEFT", topLeft, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", topRight, "TOPLEFT")

    local botLeft = mainFrame:CreateTexture(nil, "BORDER")
    botLeft:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botLeft:SetTexCoord(0.75390625, 0.875, 0, 1)
	botLeft:SetPoint("BOTTOMLEFT")
    botLeft:SetWidth(64)
    botLeft:SetHeight(64)

    local left = mainFrame:CreateTexture(nil, "BORDER")
    left:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    left:SetTexCoord(0.00390625, 0.125, 0, 1)
    left:SetPoint("TOPLEFT", topLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", botLeft, "TOPRIGHT")

    local botRight = mainFrame:CreateTexture(nil, "BORDER")
    botRight:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    botRight:SetTexCoord(0.875, 1, 0, 1)
	botRight:SetPoint("BOTTOMRIGHT")
    botRight:SetWidth(64)
    botRight:SetHeight(64)

    local right = mainFrame:CreateTexture(nil, "BORDER")
    right:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    -- Match the native Gear Manager border geometry.  The old +4 offset
    -- pushed this atlas slice outside the window, exposing its decorative
    -- pixels as two stray right-edge blobs.
    right:SetTexCoord(0.1171875, 0.2421875, 0, 1)
    right:SetWidth(64)
    right:SetPoint("TOPRIGHT", topRight, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMRIGHT", botRight, "TOPRIGHT")

    local bot = mainFrame:CreateTexture(nil, "BORDER")
    bot:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-Border")
    bot:SetTexCoord(0.38, 0.45, 0, 1)
    bot:SetPoint("BOTTOMLEFT", botLeft, "BOTTOMRIGHT")
    bot:SetPoint("TOPRIGHT", botRight, "TOPLEFT")

    mainFrame.stats = CreateFrame("Frame", nil, mainFrame)
    local stats = mainFrame.stats
    stats:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	    tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 5, bottom = 3 }
    })
    stats:SetBackdropColor(0.12, 0.12, 0.12)
    stats:SetBackdropBorderColor(0.25, 0.25, 0.25)
    stats:SetPoint("BOTTOMLEFT", 218, 10)
    stats:SetPoint("BOTTOMRIGHT", 640, 10)
    stats:SetHeight(24)
    stats:SetBackdropColor(0, 0, 0, 0)
    stats:SetBackdropBorderColor(0, 0, 0, 0)

    mainFrame.buttons = {}

    -- Reference workspace: a compact saved-look rail, central mannequin, and
    -- an independently framed appearance browser.  The underlying frames stay
    -- intact; these panels only establish their visual hierarchy.
    mainFrame.layout = {
        panelTop = -38,
        panelBottom = 10,
        sidebarLeft = 10,
        sidebarWidth = 200,
        modelLeft = 218,
        modelWidth = 422,
        modelContentInset = 7,
        browserLeft = 648,
    }
    if ns.Theme then
        mainFrame.sidebar = ns.Theme.CreatePanel(mainFrame, nil, "panel", "bronzeDim")
        mainFrame.sidebar:SetPoint("TOPLEFT", mainFrame.layout.sidebarLeft, mainFrame.layout.panelTop)
        mainFrame.sidebar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMLEFT", mainFrame.layout.sidebarLeft + mainFrame.layout.sidebarWidth, mainFrame.layout.panelBottom)

        mainFrame.modelPanel = ns.Theme.CreatePanel(mainFrame, nil, "model", "bronze")
        mainFrame.modelPanel:SetPoint("TOPLEFT", mainFrame.layout.modelLeft, mainFrame.layout.panelTop)
        mainFrame.modelPanel:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMLEFT", mainFrame.layout.modelLeft + mainFrame.layout.modelWidth, mainFrame.layout.panelBottom)

        mainFrame.browserPanel = ns.Theme.CreatePanel(mainFrame, nil, "panel", "bronze")
        mainFrame.browserPanel:SetPoint("TOPLEFT", mainFrame.layout.browserLeft, mainFrame.layout.panelTop)
        mainFrame.browserPanel:SetPoint("BOTTOMRIGHT", -10, mainFrame.layout.panelBottom)

        -- The browser intentionally stops ten units inside the outer rim.  Give
        -- only that exposed gutter an opaque panel fill; it stays beneath the
        -- native BORDER-layer chrome and does not resize the browser card.
        mainFrame.browserRightGutter = mainFrame:CreateTexture(nil, "BACKGROUND")
        local browserRightGutter = mainFrame.browserRightGutter
        browserRightGutter:SetTexture("Interface\\Buttons\\WHITE8X8")
        browserRightGutter:SetVertexColor(0.090, 0.059, 0.047, 1)
        browserRightGutter:SetPoint("TOPLEFT", mainFrame.browserPanel, "TOPRIGHT", -6, 0)
        browserRightGutter:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -6, mainFrame.layout.panelBottom)
    end

    local function UpdateWindowLockState()
        local locked = IsWindowLocked()
        mainFrame:SetMovable(not locked)
        if locked then
            mainFrame:StopMovingOrSizing()
        end
    end

	local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function(self)
        self:GetParent():Hide()
    end)

    mainFrame.buttons.close = close
    mainFrame.UpdateWindowLockState = UpdateWindowLockState
    UpdateWindowLockState()
end


mainFrame.dressingRoom = ns.CreateDressingRoom(nil, mainFrame)

do
    local dr = mainFrame.dressingRoom
    if mainFrame.modelPanel then
        local inset = mainFrame.layout.modelContentInset
        -- modelPanel owns the one continuous gold card border. Keep the model
        -- safely inside both that edge and its intentional 1px inset detail.
        dr:SetPoint("TOPLEFT", mainFrame.modelPanel, "TOPLEFT", inset, -inset)
        dr:SetPoint("BOTTOMRIGHT", mainFrame.modelPanel, "BOTTOMRIGHT", -inset, inset)
    else
        dr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 220, -52)
        dr:SetSize(418, 528)
    end

    -- The background is always automatic, so allocating all ten race textures
    -- retained nine hidden texture objects and prompted the client to resolve
    -- nine assets it could never display for this character.
    local supportedRaceFileName = ns.ResolveAppearanceRace and ns.ResolveAppearanceRace(raceFileName)
        or raceFileName
    local raceBackgroundKey = type(supportedRaceFileName) == "string" and supportedRaceFileName:lower() or "human"
    local raceBackground = dr:CreateTexture(nil, "BACKGROUND")
    raceBackground:SetTexture("Interface\\AddOns\\AppearanceBuddy\\images\\"..raceBackgroundKey)
    raceBackground:SetAllPoints()
    -- Slightly stronger than the previous 0.32 while keeping the model dominant.
    raceBackground:SetVertexColor(0.18, 0.11, 0.075, 0.38)
    raceBackground:Hide()
    dr.backgroundTextures = { [raceBackgroundKey] = raceBackground }
    dr.raceBackgroundKey = raceBackgroundKey

    -- SetLight(enabled, omni, dirX, dirY, dirZ, ambIntensity, ambR, ambG, ambB, dirIntensity, dirR, dirG, dirB)
    local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}
    local shadowformLight = {1, 0, 0, 1, 0, 1, 0.16, 0, 0.23, 0}
    local shadowformAlpha = 0.75

    dr.shadowformEnabled = false

    dr.EnableShadowform = function(self)
        self:SetLight(unpack(shadowformLight))
        self:SetModelAlpha(shadowformAlpha)
        self.shadowformEnabled = true
    end

    dr.DisableShadowform = function(self)
        self:SetLight(unpack(defaultLight))
        self:SetModelAlpha(1)
        self.shadowformEnabled = false
    end
end

-- The reference has a compact control strip above the mannequin.  These call
-- the existing DressingRoom methods, so they work in both normal and transmog
-- views without touching model state.
do
    local dr = mainFrame.dressingRoom
    -- Keep this chrome inside the model card.  The old +8 TOP anchor placed
    -- half of every button above the panel and directly through both gold top
    -- borders.  A dedicated child strip gives the row one stable anchor and
    -- frame level at every UI scale.
    local controlParent = mainFrame.modelPanel or mainFrame
    local controlStrip = CreateFrame("Frame", addon.."ModelControlStrip", controlParent)
    controlStrip:SetSize(102, 18) -- five 18px buttons plus four 3px gaps
    if mainFrame.modelPanel then
        -- Preserve the existing horizontal center (-6) while clearing the
        -- panel edge and its 4px inset detail.
        controlStrip:SetPoint("TOP", mainFrame.modelPanel, "TOP", -6, -14)
    else
        controlStrip:SetPoint("TOP", dr, "TOP", -6, -8)
    end
    controlStrip:SetFrameLevel(math.max(controlParent:GetFrameLevel(), dr:GetFrameLevel()) + 5)
    mainFrame.modelControlStrip = controlStrip

    local controls = {
        {icon = "Interface\\Common\\UI-Searchbox-Icon", badge = "+", action = function() dr:SmoothZoom(1) end, tip = "Zoom in"},
        {icon = "Interface\\Common\\UI-Searchbox-Icon", badge = "-", action = function() dr:SmoothZoom(-1) end, tip = "Zoom out"},
        {icon = "Interface\\Buttons\\UI-RotationLeft-Button-Up", action = function() dr:SetFacing((dr:GetFacing() or 0) + math.rad(15)) end, tip = "Rotate left"},
        {icon = "Interface\\Buttons\\UI-RotationRight-Button-Up", action = function() dr:SetFacing((dr:GetFacing() or 0) - math.rad(15)) end, tip = "Rotate right"},
        {icon = "Interface\\PaperDollInfoFrame\\UI-GearManager-Undo", action = function() dr:SmoothZoomReset() dr:SetFacing(0) end, tip = "Reset view"},
    }
    mainFrame.modelControls = {}
    for index, data in ipairs(controls) do
        -- UIPanelButtonTemplate2 has an OnShow handler that builds global
        -- texture names from GetName(); unnamed controls fault on WotLK.
        local button = CreateFrame("Button", addon.."ModelControl"..index, controlStrip, "UIPanelButtonTemplate2")
        button:SetSize(18, 18)
        if index == 1 then
            button:SetPoint("TOPLEFT", controlStrip, "TOPLEFT", 0, 0)
        else
            button:SetPoint("LEFT", mainFrame.modelControls[index - 1], "RIGHT", 3, 0)
        end
        button:SetFrameLevel(controlStrip:GetFrameLevel() + 1)
        button:SetText("")
        if ns.Theme then ns.Theme.SkinButton(button) end
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", 0, 0)
        icon:SetSize(12, 12)
        icon:SetTexture(data.icon)
        if data.badge then
            local badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
            badge:SetText(data.badge)
            badge:SetTextColor(0.94, 0.74, 0.17)
        end
        button:SetScript("OnClick", function()
            data.action()
            PlaySound("gsTitleOptionOK")
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(data.tip)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        mainFrame.modelControls[index] = button
    end
end

local function showAppearanceBuddyStatus(message)
    local chatFrame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
    if chatFrame then
        chatFrame:AddMessage("|ccff6ff98<Appearance Buddy>|r: " .. message)
    end
end

local function serializeAppearanceSlots(slots)
    local fields = {}
    local itemCount = 0

    for index, slotName in ipairs(slotOrder) do
        local slot = slots[slotName]
        local itemId = slot and tonumber(slot.itemId)
        if itemId and itemId > 0 and itemId <= MAX_SHARED_APPEARANCE_ITEM_ID and itemId == math.floor(itemId) then
            fields[index] = tostring(itemId)
            itemCount = itemCount + 1
        else
            fields[index] = ""
        end
    end

    return table.concat(fields, ":"), itemCount
end

mainFrame.buttons.send = CreateFrame("Button", "$parentButtonSend", mainFrame, "UIPanelButtonTemplate2")

do
    StaticPopupDialogs["APPEARANCE_BUDDY_SEND_DIALOG"] = {
        text = "|cffffd700Enter player name:",
        button1 = "Send",
        button2 = CLOSE,
        timeout = 0,
        whileDead = true,
        hasEditBox = true,
        preferredIndex = 3,
        OnAccept = function(self)
            local playerName = (self.editBox:GetText() or ""):match("^%s*(.-)%s*$")
            if playerName ~= "" then
                local payload, itemCount = serializeAppearanceSlots(mainFrame.slots)
                if itemCount > 0 and SendAddonMessage then
                    SendAddonMessage(addonMessagePrefix, payload, "WHISPER", playerName)
                elseif itemCount > 0 then
                    showAppearanceBuddyStatus("addon messages are unavailable on this client.")
                else
                    showAppearanceBuddyStatus("nothing to send.")
                end
            end
        end,
        OnShow = function(self)
            local data = self.data
            self.editBox:SetText("")
        end,}
    local btn = mainFrame.buttons.send
    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "BOTTOMRIGHT")
    btn:SetPoint("BOTTOM", mainFrame.stats, "BOTTOM", 0, 1)
    btn:SetWidth(mainFrame.dressingRoom:GetWidth()/4)
    btn:SetText("Send")
    if ns.Theme then ns.Theme.SkinButton(btn) end
    btn:SetScript("OnClick", function()
        StaticPopup_Show("APPEARANCE_BUDDY_SEND_DIALOG")
        PlaySound("gsTitleOptionOK")
    end)
end

mainFrame.buttons.reset = CreateFrame("Button", "$parentButtonReset", mainFrame, "UIPanelButtonTemplate2")

do
    local btn = mainFrame.buttons.reset
    btn:SetPoint("TOPRIGHT", mainFrame.buttons.send, "TOPLEFT")
    btn:SetWidth(mainFrame.buttons.send:GetWidth())
    btn:SetText("Reset")
    if ns.Theme then ns.Theme.SkinButton(btn) end
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Reset()
        PlaySound("gsTitleOptionOK")
    end)
end

mainFrame.buttons.undress = CreateFrame("Button", "$parentButtonUndress", mainFrame, "UIPanelButtonTemplate2")

do
    local btn = mainFrame.buttons.undress
    btn:SetPoint("TOPRIGHT", mainFrame.buttons.reset, "TOPLEFT")
    btn:SetPoint("BOTTOMRIGHT", mainFrame.buttons.reset, "BOTTOMLEFT")
    btn:SetWidth(mainFrame.buttons.reset:GetWidth())
    btn:SetText("Undress")
    if ns.Theme then ns.Theme.SkinButton(btn) end
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:Undress()
        PlaySound("gsTitleOptionOK")
    end)
end

mainFrame.buttons.useTarget = CreateFrame("Button", "$parentButtonUseTarget", mainFrame, "UIPanelButtonTemplate2")

do
    local btn = mainFrame.buttons.useTarget
    btn:SetPoint("TOPRIGHT", mainFrame.buttons.undress, "TOPLEFT")
    btn:SetWidth(mainFrame.buttons.undress:GetWidth())
    btn:SetText("Use Target")
    if ns.Theme then ns.Theme.SkinButton(btn) end
    btn:SetScript("OnClick", function()
        mainFrame.dressingRoom:SetUnit("target")
        PlaySound("gsTitleOptionOK")
    end)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Use target player's model.")
        GameTooltip:AddLine("The target must be in range of inspection.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

---------------- TABS ----------------

local TAB_NAMES = {"Transmog", "Settings"}

mainFrame.tabs = {}

do
    local tabs = {}

    local function tab_OnClick(self)
        local selectedTab = PanelTemplates_GetSelectedTab(self:GetParent())
        local targetTab = self:GetID()
        -- The compact options button doubles as the return control so the
        -- reference-style title bar stays free of a second visible tab.
        if targetTab == 2 and selectedTab == 2 then
            targetTab = 1
        end
        local tab = tabs[selectedTab]
        if tab ~= nil then
            tab:Hide()
        end
        PanelTemplates_SetTab(self:GetParent(), targetTab)
        tabs[targetTab]:Show()
        if mainFrame.sidebar then
            if targetTab == 1 then mainFrame.sidebar:Show() else mainFrame.sidebar:Hide() end
        end
        PlaySound("gsTitleOptionOK")
    end

    for i = 1, #TAB_NAMES do
        mainFrame.buttons["tab"..i] = CreateFrame("Button", "$parentTab"..i, mainFrame, "OptionsFrameTabButtonTemplate")
        local btn = mainFrame.buttons["tab"..i]
        btn:SetText(TAB_NAMES[i])
        btn:SetID(i)
        if i == 1 then
            btn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -72, -5)
        else
            btn:SetPoint("LEFT", _G[mainFrame:GetName().."Tab"..(i - 1)], "RIGHT", -2, 0)
        end
        if ns.Theme then ns.Theme.SkinButton(btn) end
        btn:SetScript("OnClick", tab_OnClick)

        local frame = CreateFrame("Frame", "$parentTab"..i.."Content", mainFrame)
        frame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 656, -58)
        frame:SetPoint("BOTTOMRIGHT", -16, 18)
        frame:Hide()
        table.insert(tabs, frame)
    end
    
    PanelTemplates_SetNumTabs(mainFrame, #TAB_NAMES)
    tab_OnClick(_G[mainFrame:GetName().."Tab1"])

    -- Hidden template tabs continue to own Blizzard's panel state, while the
    -- Settings page exposes its own deliberate return control.
    mainFrame.buttons.tab1:Hide()
    local settingsTabButton = mainFrame.buttons.tab2
    settingsTabButton:Hide()

    local settingsBackButton = CreateFrame("Button", addon.."SettingsBack", tabs[2], "UIPanelButtonTemplate2")
    settingsBackButton:SetPoint("TOPRIGHT", tabs[2], "TOPRIGHT", -10, -10)
    settingsBackButton:SetSize(142, 22)
    settingsBackButton:SetText("Back to Transmogrify")
    if ns.Theme then ns.Theme.SkinButton(settingsBackButton) end
    settingsBackButton:SetScript("OnClick", function()
        tab_OnClick(mainFrame.buttons.tab1)
    end)
    mainFrame.buttons.settingsBack = settingsBackButton

    mainFrame.ShowSettings = function(self)
        if not self:IsShown() then self:Show() end
        if PanelTemplates_GetSelectedTab(self) ~= 2 then
            tab_OnClick(settingsTabButton)
        end
    end

    mainFrame.ShowTransmog = function(self)
        if not self:IsShown() then self:Show() end
        if PanelTemplates_GetSelectedTab(self) ~= 1 then
            tab_OnClick(mainFrame.buttons.tab1)
        end
    end

    local settingsOpenButton = CreateFrame("Button", addon.."SettingsOpen", tabs[1], "UIPanelButtonTemplate2")
    -- Keep the Settings control inside the 17px title-bar lane (-7 through
    -- -24).  The old 20px button started above that lane and overlapped the
    -- upper chrome at every UI scale.
    settingsOpenButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -30, -7)
    settingsOpenButton:SetSize(76, 16)
    settingsOpenButton:SetText("Settings")
    if ns.Theme then ns.Theme.SkinButton(settingsOpenButton) end
    settingsOpenButton:SetScript("OnClick", function()
        mainFrame:ShowSettings()
    end)
    settingsOpenButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Settings", 0.84, 0.66, 0.086)
        GameTooltip:AddLine("Open Appearance Buddy settings.", 1, 1, 1)
        GameTooltip:Show()
    end)
    settingsOpenButton:HookScript("OnLeave", GameTooltip_Hide)
    mainFrame.buttons.settingsOpen = settingsOpenButton

    mainFrame.tabs.transmog = tabs[1]
    mainFrame.tabs.settings = tabs[2]
    if ns.Theme then ns.Theme.ApplyInset(mainFrame.tabs.settings, "panel", "bronze") end
end

---------------- SLOTS ----------------

mainFrame.slots = {}
mainFrame.selectedSlot = nil
mainFrame.legacyPreviewActive = false

local function slot_OnShiftLeftClick(self)
    if self.itemId ~= nil then
        local _, link = GetItemInfo(self.itemId)
        if link ~= nil then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: "..link.." ("..self.itemId..")")
        else
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: It seems this item cannot be used for transmogrification.")
        end
    end
end

local function getIndex(array, value)
    for i = 1, #array do
        if array[i] == value then
            return i    
        end
    end
    return nil
end

local function slot_OnControlLeftClick(self)
    if self.itemId ~= nil then
        ns.ShowWowheadURLDialog(self.itemId)
    end
end


local function slot_OnLeftClick(self)
    local selectedSlot = mainFrame.selectedSlot
    if selectedSlot ~= nil then
        selectedSlot:UnlockHighlight()
    end
    mainFrame.selectedSlot = self
    --[[ ReTryOn weapon so the model displays
    the weapon of the clicked (selected) slot. ]]
    if mainFrame.legacyPreviewActive
        and self.itemId ~= nil
        and getIndex({mainHandSlot, offHandSlot, rangedSlot}, self.slotName) then
        mainFrame.dressingRoom:TryOn(self.itemId)
    end
    self:LockHighlight()
end

local function slot_OnRightClick(self)
    self:RemoveItem()
end

local function slot_OnClick(self, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            slot_OnShiftLeftClick(self)
        elseif IsControlKeyDown() then
            slot_OnControlLeftClick(self)
        else
            slot_OnLeftClick(self)
        end
        PlaySound("gsTitleOptionOK")
    elseif button == "RightButton" then
        slot_OnRightClick(self)
    end
end

local function slot_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if self.itemId == nil then
        GameTooltip:AddLine(self.slotName)
    else
        local _, link = GetItemInfo(self.itemId)
        if link ~= nil then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:AddLine(self.slotName)
            GameTooltip:AddLine(self.itemLoadFailed and "Item data is unavailable." or "Loading item data...", 0.7, 0.7, 0.7)
        end
        if GetSettings().showShortcutsInTooltip then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Shift + Left Click:|r create a hyperlink for the item.")
            GameTooltip:AddLine("|cff00ff00Right Click:|r undress the slot.")
            GameTooltip:AddLine("|cff00ff00Ctrl + Left Click:|r create a Wowhead URL for the item.")
        end
    end
    GameTooltip:Show()
end

local function slot_OnLeave(self)
    GameTooltip:Hide()
end

local function slot_Reset(self)
    if not mainFrame.legacyPreviewActive then
        return
    end

    local characterSlotName = self.slotName
    if characterSlotName == mainHandSlot then characterSlotName = "MainHand" end
    if characterSlotName == offHandSlot then characterSlotName = "SecondaryHand" end
    if characterSlotName == rangedSlot then characterSlotName = "Ranged" end
    if characterSlotName == backSlot then characterSlotName = "Back" end
    local slotId = GetInventorySlotInfo(characterSlotName.."Slot")
    local itemId = GetInventoryItemID("player", slotId)
    if itemId ~= nil then
        self:SetItem(itemId)
    else
        self:RemoveItem()
    end
end

local function slot_CancelItemQuery(self)
    if self.itemQuery ~= nil then
        self.itemQuery:Cancel()
        self.itemQuery = nil
    end
end

local function slot_ClearItem(self)
    slot_CancelItemQuery(self)
    self.itemId = nil
    self.itemLoadFailed = nil
    self.textures.empty:Show()
    self.textures.item:Hide()
end

local function slot_RemoveItem(self)
    if self.itemId ~= nil then
        slot_ClearItem(self)
        self:GetScript("OnEnter")(self)
        --[[ We cannot undress a specific slot
        of a DressUpModel in WotLK. Instead,
        we're undressing the whole model and
        dressing it up again without the slot. ]]
        if mainFrame.legacyPreviewActive then
            mainFrame.dressingRoom:Undress()
            for _, slot in pairs(mainFrame.slots) do
                if slot.itemId ~= nil then
                    mainFrame.dressingRoom:TryOn(slot.itemId)
                end
            end
        end
    end
end

local function slot_SetItem(self, itemId)
    if type(itemId) ~= "number" or itemId <= 0 then
        self:RemoveItem()
        return
    end

    slot_CancelItemQuery(self)
    self.itemId = itemId
    self.itemLoadFailed = nil
    self.textures.empty:Show()
    self.textures.item:Hide()

    local queryHandle
    queryHandle = ns.QueryItem(itemId, function(queriedItemId, success)
        if self.itemQuery == queryHandle then
            self.itemQuery = nil
        end
        if queriedItemId == self.itemId then
            if success then
                local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(queriedItemId)
                self.textures.empty:Hide()
                self.textures.item:SetTexture(texture)
                self.textures.item:Show()
                if mainFrame.legacyPreviewActive then
                    mainFrame.dressingRoom:TryOn(queriedItemId)
                end
            else
                self.itemLoadFailed = true
            end
        end
    end)
    self.itemQuery = queryHandle
end

--------- Slot building

do
    for slotName, texturePath in pairs(slotTextures) do
        local slot = CreateFrame("Button", "$parentSlot"..slotName, mainFrame, "ItemButtonTemplate")
        slot:SetSize(36, 36)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
        slot:SetScript("OnClick", slot_OnClick)
        slot:SetScript("OnEnter", slot_OnEnter)
        slot:SetScript("OnLeave", slot_OnLeave)
        slot.slotName = slotName
        mainFrame.slots[slotName] = slot
        slot.textures = {}
        slot.textures.empty = slot:CreateTexture(nil, "ARTWORK")
        slot.textures.empty:SetTexture(texturePath)
        slot.textures.empty:SetAllPoints()
        slot.textures.item = slot:CreateTexture(nil, "ARTWORK")
        slot.textures.item:SetAllPoints()
        slot.textures.item:Hide()
        if ns.Theme then ns.Theme.SkinItemButton(slot) end
        slot.Reset = slot_Reset
        slot.SetItem = slot_SetItem
        slot.RemoveItem = slot_RemoveItem
    end

    local slots = mainFrame.slots
    slots["Head"]:SetPoint("TOPLEFT", mainFrame.dressingRoom, "TOPLEFT", 16, -103)
    slots["Shoulder"]:SetPoint("TOP", slots["Head"], "BOTTOM", 0, -4)
    slots["Back"]:SetPoint("TOP", slots["Shoulder"], "BOTTOM", 0, -4)
    slots["Chest"]:SetPoint("TOP", slots["Back"], "BOTTOM", 0, -4)
    slots["Shirt"]:SetPoint("TOP", slots["Chest"], "BOTTOM", 0, -4)
    slots["Tabard"]:SetPoint("TOP", slots["Shirt"], "BOTTOM", 0, -4)
    slots["Wrist"]:SetPoint("TOP", slots["Tabard"], "BOTTOM", 0, -4)
    slots["Hands"]:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "TOPRIGHT", -8, -170)
    slots["Waist"]:SetPoint("TOP", slots["Hands"], "BOTTOM", 0, -4)
    slots["Legs"]:SetPoint("TOP", slots["Waist"], "BOTTOM", 0, -4)
    slots["Feet"]:SetPoint("TOP", slots["Legs"], "BOTTOM", 0, -4)
    slots["Main Hand"]:SetPoint("BOTTOM", mainFrame.dressingRoom, "BOTTOM", -23, -4)
    slots["Off-hand"]:SetPoint("BOTTOM", mainFrame.dressingRoom, "BOTTOM", 23, -4)
    slots["Ranged"]:SetPoint("BOTTOM", mainFrame.dressingRoom, "BOTTOM", -23, -46)
end

------- Tricks and hooks with slots and provided appearances. -------


local function btnReset_Hook()
    if not mainFrame.legacyPreviewActive then
        return
    end

    mainFrame.dressingRoom:Undress()
    for _, slot in pairs(mainFrame.slots) do
        if slot.slotName == rangedSlot and ("DRUIDSHAMANPALADINDEATHKNIGHT"):find(classFileName) then
            slot:RemoveItem()
        else
            slot:Reset()
        end
    end
    if mainFrame.dressingRoom.shadowformEnabled then
        mainFrame.dressingRoom:EnableShadowform()
    end
end

local function btnUndress_Hook()
    for _, slot in pairs(mainFrame.slots) do
        slot_CancelItemQuery(slot)
        slot.itemId = nil
        slot.itemLoadFailed = nil
        slot.textures.empty:Show()
        slot.textures.item:Hide()
    end
end

local function parseSharedAppearancePayload(payload)
    if type(payload) ~= "string" or #payload == 0 or #payload > MAX_SHARED_APPEARANCE_PAYLOAD_LENGTH then
        return nil
    end

    local items = {}
    local itemCount = 0
    local position = 1

    -- The sender always emits exactly one field per slot.  Preserve empty
    -- fields so a received look can intentionally leave a slot undressed.
    for index, slotName in ipairs(slotOrder) do
        local field
        if index < #slotOrder then
            local separator = payload:find(":", position, true)
            if separator == nil then
                return nil
            end
            field = payload:sub(position, separator - 1)
            position = separator + 1
        else
            field = payload:sub(position)
            if field:find(":", 1, true) ~= nil then
                return nil
            end
        end

        if field ~= "" then
            if #field > 10 or field:match("^%d+$") == nil then
                return nil
            end
            local itemId = tonumber(field)
            if itemId == nil or itemId < 1 or itemId > MAX_SHARED_APPEARANCE_ITEM_ID or itemId ~= math.floor(itemId) then
                return nil
            end
            items[slotName] = itemId
            itemCount = itemCount + 1
        end
    end

    if itemCount == 0 then
        return nil
    end
    return items
end

local function previewSharedAppearance(payload, sender)
    local items = parseSharedAppearancePayload(payload)
    if items == nil then
        return false
    end

    -- Show first: the one-time slot OnShow initialization restores the
    -- equipped outfit, so applying the shared look must happen afterwards.
    if not mainFrame:IsShown() then
        mainFrame:Show()
    end

    mainFrame.dressingRoom:Undress()
    for _, slotName in ipairs(slotOrder) do
        local slot = mainFrame.slots[slotName]
        local itemId = items[slotName]
        if itemId ~= nil then
            slot:SetItem(itemId)
        else
            slot_ClearItem(slot)
        end
    end
    if mainFrame.dressingRoom.shadowformEnabled then
        mainFrame.dressingRoom:EnableShadowform()
    end

    showAppearanceBuddyStatus("previewing appearance shared by " .. sender .. ".")
    return true
end

do
    -- 3.3.5 receives CHAT_MSG_ADDON without prefix registration.  Register
    -- only on newer clients where the registration API is required.
    local _, _, _, tocVersion = GetBuildInfo()
    tocVersion = tonumber(tocVersion)
    if tocVersion and tocVersion >= 40100 and RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(addonMessagePrefix)
    end

    local lastSharedPreviewAtBySender = {}
    local receiver = CreateFrame("Frame", nil, UIParent)
    receiver:RegisterEvent("CHAT_MSG_ADDON")
    receiver:SetScript("OnEvent", function(_, event, prefix, payload, distribution, sender)
        -- Sharing belongs to the retired legacy preview. The active Transmog
        -- mannequin must never be opened or undressed by an unsolicited addon
        -- message. Preserve the old path only if a future caller explicitly
        -- re-enables that preview, and accept its original WHISPER transport.
        if event ~= "CHAT_MSG_ADDON"
            or prefix ~= addonMessagePrefix
            or distribution ~= "WHISPER"
            or not mainFrame.legacyPreviewActive
            or type(sender) ~= "string"
            or sender == "" then
            return
        end
        local now = GetTime and GetTime() or 0
        local lastAt = tonumber(lastSharedPreviewAtBySender[sender]) or 0
        if now > 0 and now - lastAt < 2 then return end
        if now > 0 then lastSharedPreviewAtBySender[sender] = now end
        previewSharedAppearance(payload, sender)
    end)
    mainFrame.shareReceiver = receiver
end

local function tryOnFromSlots(dressUpModel)
    for _, slot in pairs(mainFrame.slots) do
        if slot.itemId ~= nil then
            dressUpModel:TryOn(slot.itemId)
        end
    end
end

local function refreshDressingRoomFromSlots(unitToken)
    if not mainFrame.legacyPreviewActive then
        return
    end

    if unitToken ~= nil then
        mainFrame.dressingRoom:SetUnit(unitToken)
    end

    mainFrame.dressingRoom:Undress()
    tryOnFromSlots(mainFrame.dressingRoom)

    if mainFrame.dressingRoom.shadowformEnabled then
        mainFrame.dressingRoom:EnableShadowform()
    end
end

--[[
    Have to reTryOn selected appearances since
    the model's reset each time it's shown.
]]
--[[
    After half a year I don't remeber anymore
    why I do it, but showing/hiding a DressUpModel
    breaks the model's positioning.
]]
local function dressingRoom_OnShow(self)
    if not mainFrame.legacyPreviewActive then
        return
    end

    self:Reset()
    self:Undress()
    tryOnFromSlots(self)
    if self.shadowformEnabled then
        self:EnableShadowform()
    end
end

--[[
    Need to TryOn items in the slots if we changed
    displayed model.
]]
mainFrame.buttons.useTarget:HookScript("OnClick", function(slef)
    if not mainFrame.legacyPreviewActive then
        return
    end

    if mainFrame.dressingRoom.shadowformEnabled then
        mainFrame.dressingRoom:EnableShadowform()
    end
    mainFrame.dressingRoom:Undress()
    tryOnFromSlots(mainFrame.dressingRoom)
end)

-- At first time it's shown.
mainFrame.slots[defaultSlot]:SetScript("OnShow", function(self)
    self:SetScript("OnShow", nil)
    mainFrame.buttons.reset:HookScript("OnClick", btnReset_Hook)
    mainFrame.dressingRoom:HookScript("OnShow", dressingRoom_OnShow)
    dressingRoom_OnShow(mainFrame.dressingRoom)
    btnReset_Hook()
    mainFrame.buttons.undress:HookScript("OnClick", btnUndress_Hook)
    self:Click("LeftButton")
end)

---------------- SHADOWFORM ----------------

mainFrame.buttons.shadowform = CreateFrame("Button", "$parentShadowformButton", mainFrame, "ItemButtonTemplate")

do
    local enableTexture = "Interface\\Icons\\spell_shadow_shadowform"
    local disableTexture = "Interface\\Icons\\spell_nature_wispsplode"
    
    local btn = mainFrame.buttons.shadowform
    btn:SetSize(28, 28)
    _G[btn:GetName().."NormalTexture"]:SetAllPoints()
    _G[btn:GetName().."NormalTexture"]:SetTexCoord(0.1875, 0.796875, 0.1875, 0.796875)

    btn:SetPoint("TOPRIGHT", mainFrame.dressingRoom, "TOPRIGHT", -12, -12)
    btn:SetFrameLevel(mainFrame.dressingRoom:GetFrameLevel() + 1)
    if ns.Theme then ns.Theme.SkinItemButton(btn) end

    local texture = btn:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture(enableTexture)

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        PlaySound("gsTitleOptionOK")
        if not mainFrame.dressingRoom.shadowformEnabled then
            mainFrame.dressingRoom:EnableShadowform()
            texture:SetTexture(disableTexture)
            self:LockHighlight()
        else
            mainFrame.dressingRoom:DisableShadowform()
            texture:SetTexture(enableTexture)
            self:UnlockHighlight()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:ClearLines()
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Shadowform")
        GameTooltip:AddLine("A poor simulation that relies on the model's light setup. Equipment with its own light source (like  \"Excavator's Brand\" tourch) gives wrong result. Emission textures that ignore light (like Draenei eyes) also ignore the simulation and are not shaded as they would be in the true shadowform.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:ClearLines()
        GameTooltip:Hide()
    end)
end

---------------- CHARACTER MENU BUTTON ----------------

local btnAppearanceBuddy = CreateFrame("Button", "$parent"..addon.."AppearanceBuddyButton", CharacterModelFrame, "UIPanelButtonTemplate2")
btnAppearanceBuddy:SetSize(90, 20)
btnAppearanceBuddy:SetPoint("BOTTOMRIGHT", -2, 25)
btnAppearanceBuddy:SetText("Transmog")
if ns.Theme then ns.Theme.SkinButton(btnAppearanceBuddy) end
btnAppearanceBuddy:SetScript("OnClick", function(self)
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show() 
    end
end)

---------------- SETTINGS TAB ----------------


do  --------- Preview Setup
    local settingsTab = mainFrame.tabs.settings

    settingsTab.previewSetupMenu = CreateFrame("Frame", "$parentPreviewSetupDropDownMenu", settingsTab, "UIDropDownMenuTemplate")
    
    local menu = settingsTab.previewSetupMenu

    local function menu_OnClick(self, mode)
        GetSettings().previewSetup = mode
        UIDropDownMenu_SetText(menu, mode)
        previewSetupVersion = mode
        if mainFrame.selectedSlot ~= nil then
            mainFrame.selectedSlot:Click("LeftButton")
        end
    end

    UIDropDownMenu_Initialize(menu, function(frame)
        local previewSetup = GetSettings().previewSetup
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.checked, info.arg1, info.func = "classic", previewSetup == "classic", "classic", menu_OnClick
        UIDropDownMenu_AddButton(info)
        info.text, info.checked, info.arg1, info.func = "modern", previewSetup == "modern", "modern", menu_OnClick
        UIDropDownMenu_AddButton(info)
    end)

    local label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 16, -24)
    label:SetText("Used models:")

    local tipFrame = CreateFrame("Frame", addon.."PreviewSetupDropDownMenuTip", settingsTab)
    tipFrame:SetPoint("LEFT", label, "LEFT")
    tipFrame:SetPoint("RIGHT", menu:GetChildren(), "LEFT")
    tipFrame:SetHeight(menu:GetChildren():GetHeight())
    tipFrame:EnableMouse(true)
    tipFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Used models")
        GameTooltip:AddLine("There's a funmade modification for WotLK client that brings modern high quality character models from \"Warlords of Draenor\" expansion. Unfortunately, preview for the modern models has different setup. If your game client's using the modern models, choose \"modern\" in this popup menu and \"classic\" otherwise.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tipFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    menu:SetPoint("TOPLEFT", label:GetWidth() + 10, -16)

    settingsTab.SetPreviewSetup = function(self, mode)
        menu_OnClick(nil, mode)
    end
end


do  --------- Character background
    local settingsTab = mainFrame.tabs.settings
    local textures = mainFrame.dressingRoom.backgroundTextures

    local label = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 16, -80)
    label:SetText("Race background:")

    local value = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", label, "RIGHT", 8, 0)
    value:SetTextColor(0.85, 0.85, 0.85)

    local function getText(background)
        return  (background == "nightelf" and "Night elf")
                or (background == "bloodelf" and "Blood elf")
                or (background == "scourge" and "Forsaken")
                or background:gsub("^%l", string.upper)
    end

    local function showRaceBackground(background)
        background = type(background) == "string" and background:lower() or nil
        if background == nil or background == "color" or textures[background] == nil then
            background = mainFrame.dressingRoom.raceBackgroundKey or "human"
        end
        for _, tex in pairs(textures) do
            tex:Hide()
        end
        textures[background]:Show()
        return background
    end

    settingsTab.SetCharacterBackground = function(self, background)
        local activeBackground = showRaceBackground(background)
        value:SetText(getText(activeBackground) .. " (automatic)")
    end
end


do  --------- Show/hide "Appearance Buddy" button
    local settingsTab = mainFrame.tabs.settings
    settingsTab.showAppearanceBuddyButtonCheckBox = CreateFrame("CheckButton", "$parentShowAppearanceBuddyButtonCheckBox", settingsTab, "ChatConfigCheckButtonTemplate")

    local checkbox = settingsTab.showAppearanceBuddyButtonCheckBox
    checkbox:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 15, -150)
    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            btnAppearanceBuddy:Show()
            GetSettings().showAppearanceBuddyButton = true
        else
            btnAppearanceBuddy:Hide()
            GetSettings().showAppearanceBuddyButton = false
        end
    end)
    checkbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Show \"Appearance\" button")
        GameTooltip:AddLine("Show or hide \"Appearance\" button in the character window.", 1, 1, 1, 1, true)
        GameTooltip:AddLine("The addon can be still accessed via \"/appearancebuddy\" chat command.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Show \"Appearance\" button")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 2)
end


do  --------- Show shortcuts in tooltips
    local settingsTab = mainFrame.tabs.settings
    settingsTab.showShortcutsInTooltipCheckBox = CreateFrame("CheckButton", "$parentShowShortcutsInTooltipCheckBox", settingsTab, "ChatConfigCheckButtonTemplate")
    
    local checkbox = settingsTab.showShortcutsInTooltipCheckBox
    checkbox:SetPoint("TOP", settingsTab.showAppearanceBuddyButtonCheckBox, "BOTTOM", 0, -10)
    checkbox:SetScript("OnClick", function(self)
        GetSettings().showShortcutsInTooltip = self:GetChecked() ~= nil
    end)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Show shortcuts in tooltip")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 2)
end


do  --------- Ignore UI scaling
    local settingsTab = mainFrame.tabs.settings
    settingsTab.ignoreUIScalingCheckBox = CreateFrame("CheckButton", "$parentIgnoreUIScalingCheckBox", settingsTab, "ChatConfigCheckButtonTemplate")
    
    local checkbox = settingsTab.ignoreUIScalingCheckBox
    checkbox:SetPoint("TOP", settingsTab.showShortcutsInTooltipCheckBox, "BOTTOM", 0, -30)
    checkbox:SetScript("OnClick", function(self)
        GetSettings().ignoreUIScaling = self:GetChecked() ~= nil
        if self:GetChecked() then
            mainFrame:SetParent(nil)
        else
            mainFrame:SetParent(UIParent)
        end
        UpdateReferenceScale()
        if mainFrame:IsVisible() then
            -- only to update the main dressing room
            mainFrame:Hide()
            mainFrame:Show()
        end
    end)
    local origingSetChecked = checkbox.SetChecked
    checkbox.SetChecked = function(self, enable)
        origingSetChecked(self, enable)
        checkbox:GetScript("OnClick")(self)
    end
    checkbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Ignore UI scaling")
        GameTooltip:AddLine("The game's 3D rendering can break correct display of previews with low UI scaling values. Enable this to bypass UI scaling.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Ignore UI scaling")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 2)
end


do  --------- Item data prefetch and manual inventory scan
    local settingsTab = mainFrame.tabs.settings
    settingsTab.prefetchItemDataCheckBox = CreateFrame("CheckButton", "$parentPrefetchItemDataCheckBox", settingsTab, "ChatConfigCheckButtonTemplate")

    local checkbox = settingsTab.prefetchItemDataCheckBox
    checkbox:SetPoint("TOP", settingsTab.showShortcutsInTooltipCheckBox, "BOTTOM", 0, -10)
    checkbox:SetScript("OnClick", function(self)
        GetSettings().prefetchItemData = self:GetChecked() ~= nil
    end)
    checkbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Prefetch nearby item data")
        GameTooltip:AddLine("Requests item data for adjacent appearance pages. Disabled by default to avoid competing with normal item and loot data.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Prefetch nearby item data")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 2)

    local button = CreateFrame("Button", addon.."ScanInventoryButton", settingsTab, "UIPanelButtonTemplate2")
    settingsTab.scanInventoryButton = button
    button:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 20, -4)
    button:SetSize(142, 22)
    button:SetText("Scan inventory now")
    if ns.Theme then ns.Theme.SkinButton(button) end
    button:SetScript("OnClick", function()
        if ns.ScanInventoryForAppearances then
            ns.ScanInventoryForAppearances()
        elseif SELECTED_CHAT_FRAME then
            SELECTED_CHAT_FRAME:AddMessage("|ccff6ff98<Appearance Buddy>|r: Transmog scanning is unavailable.")
        end
    end)
    settingsTab.ignoreUIScalingCheckBox:ClearAllPoints()
    settingsTab.ignoreUIScalingCheckBox:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -20, -15)
    button:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Scan inventory now")
        GameTooltip:AddLine("Explicitly unlock eligible equipped and bag items. This can take time on accounts with many appearances.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end


do  --------- Lock window
    local settingsTab = mainFrame.tabs.settings
    settingsTab.windowLockedCheckBox = CreateFrame("CheckButton", "$parentWindowLockedCheckBox", settingsTab, "ChatConfigCheckButtonTemplate")

    local checkbox = settingsTab.windowLockedCheckBox
    checkbox:SetPoint("TOP", settingsTab.ignoreUIScalingCheckBox, "BOTTOM", 0, -10)
    checkbox:SetScript("OnClick", function(self)
        GetSettings().windowLocked = self:GetChecked() ~= nil
        if mainFrame.UpdateWindowLockState then
            mainFrame.UpdateWindowLockState()
        end
    end)
    checkbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Lock window")
        GameTooltip:AddLine("Prevent Appearance Buddy from being moved.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Lock window")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 2)
end



do  --------- Apply settings on addon loaded
    local settingsTab = mainFrame.tabs.settings

    local function applySettings(settings)
        -- Dressing room background: always auto-match to the player's race.
        -- Do not replace a Death Knight's race art with class art: each race
        -- keeps its own low-opacity background as shown in the UI.
        local autoBackground = mainFrame.dressingRoom.raceBackgroundKey or "human"
        settingsTab:SetCharacterBackground(autoBackground)
        -- Preview setup popup menu
        settingsTab:SetPreviewSetup(settings.previewSetup)
        -- Show/hide "Appearance Buddy" button
        settingsTab.showAppearanceBuddyButtonCheckBox:SetChecked(settings.showAppearanceBuddyButton)
        if settings.showAppearanceBuddyButton then
            btnAppearanceBuddy:Show()
        else
            btnAppearanceBuddy:Hide()
        end
        -- Show shortcuts in tooltip
        settingsTab.showShortcutsInTooltipCheckBox:SetChecked(settings.showShortcutsInTooltip)
        -- Item data prefetch
        settingsTab.prefetchItemDataCheckBox:SetChecked(settings.prefetchItemData)
        -- Ignore UI scaling
        settingsTab.ignoreUIScalingCheckBox:SetChecked(settings.ignoreUIScaling)
        if settings.ignoreUIScaling then
            mainFrame:SetParent(nil)
        else
            mainFrame:SetParent(UIParent)
        end
        UpdateReferenceScale()
        -- Lock window
        settingsTab.windowLockedCheckBox:SetChecked(settings.windowLocked)
        if mainFrame.UpdateWindowLockState then
            mainFrame.UpdateWindowLockState()
        end
    end

    settingsTab:RegisterEvent("ADDON_LOADED")
    settingsTab:SetScript("OnEvent", function(self, event, addonName)
        if addonName == addon then
            if event == "ADDON_LOADED" then
                applySettings(GetSettings())
            end
        end
    end)
end

---------------- CHAT COMMANDS ----------------

ns.mainFrame = mainFrame
ns.GetSettings = GetSettings
ns.RefreshManagedScrollFrame = RefreshManagedScrollFrame
ns.GetPreviewSetupVersion = function()
    return previewSetupVersion
end
ns.RefreshDressingRoomFromSlots = refreshDressingRoomFromSlots
ns.SetAppearanceBuddyPreviewControlsVisible = function(visible)
    mainFrame.legacyPreviewActive = visible and true or false
    for _, slot in pairs(mainFrame.slots) do
        if not visible then
            slot_CancelItemQuery(slot)
        end
        if visible then
            slot:Show()
        else
            slot:Hide()
        end
    end

    for _, name in ipairs({"send", "reset", "undress", "useTarget", "shadowform"}) do
        local button = mainFrame.buttons[name]
        if button then
            if visible then
                button:Show()
            else
                button:Hide()
            end
        end
    end
end

-- The custom Transmogrify and Settings pages own the preview now. Hide the
-- retired direct-child controls before the first frame show can expose them.
ns.SetAppearanceBuddyPreviewControlsVisible(false)

-- Settings shares the mannequin with Transmogrify, but not the retired
-- slot/action controls. Hide them before the page can expose or initialize
-- the legacy preview and overwrite the active transmog mannequin.
if mainFrame.tabs and mainFrame.tabs.settings then
    mainFrame.tabs.settings:HookScript("OnShow", function()
        ns.SetAppearanceBuddyPreviewControlsVisible(false)
    end)
end

SLASH_APPEARANCEBUDDY1 = "/appearancebuddy"
SLASH_APPEARANCEBUDDY2 = "/ab"

-- Scan results popup (created once, reused)
local function getScanPopup()
    if _G["AppearanceBuddyScanPopup"] then
        return _G["AppearanceBuddyScanPopup"]
    end
    local p = CreateFrame("Frame", "AppearanceBuddyScanPopup", UIParent)
    p:SetSize(540, 360)
    p:SetPoint("CENTER")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    p:SetBackdropColor(0.08, 0.08, 0.08, 0.97)
    p:SetBackdropBorderColor(0.55, 0.55, 0.55)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -9)
    title:SetText("|cff00ff00AppearanceBuddy Frame Scan|r  (Ctrl+A then Ctrl+C to copy)")

    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() p:Hide() end)

    local sf = CreateFrame("ScrollFrame", "AppearanceBuddyScanScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -26)
    sf:SetPoint("BOTTOMRIGHT", -26, 8)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(0)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetWidth(490)
    eb:SetScript("OnEscapePressed", function() p:Hide() end)
    sf:SetScrollChild(eb)
    p.editBox = eb

    return p
end

SlashCmdList["APPEARANCEBUDDY"] = function(msg)
    msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    elseif msg == "settings" then
        if mainFrame.ShowSettings then mainFrame:ShowSettings() end
    elseif msg == "transmog" or msg == "items" then
        if mainFrame.ShowTransmog then mainFrame:ShowTransmog() end
    elseif msg == "inventory" or msg == "unlocks" then
        if ns.ScanInventoryForAppearances then
            ns.ScanInventoryForAppearances()
        else
            print("|cffff4444AppearanceBuddy:|r Transmog scanning is unavailable.")
        end
    elseif msg == "debug" then
        if mainFrame.dressingRoom:IsDebugInfoShown() then mainFrame.dressingRoom:HideDebugInfo() else mainFrame.dressingRoom:ShowDebugInfo() end
    elseif msg == "scan" then
        local mfLeft, mfBottom, mfWidth, mfHeight = mainFrame:GetLeft(), mainFrame:GetBottom(), mainFrame:GetWidth(), mainFrame:GetHeight()
        if not mfLeft then
            print("|cffff4444AppearanceBuddy scan:|r Open the window first.")
            return
        end
        local mfRight  = mfLeft   + mfWidth
        local mfTop    = mfBottom + mfHeight
        -- Search zone: mainFrame area expanded by 600px on all sides
        local expand = 600
        local zL, zR = mfLeft - expand, mfRight  + expand
        local zB, zT = mfBottom - expand, mfTop + expand

        local lines = {}
        lines[#lines+1] = string.format("mainFrame: (%.0f,%.0f)-(%.0f,%.0f)  size %.0fx%.0f",
            mfLeft, mfBottom, mfRight, mfTop, mfWidth, mfHeight)
        lines[#lines+1] = "Visible frames within 300px of window:"
        lines[#lines+1] = ""

        local count = 0
        local frame = EnumerateFrames()
        while frame do
            if frame:IsVisible() and frame ~= mainFrame then
                local fl, fb, fw, fh = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
                if fl and fb and fw and fh and fw > 0 and fh > 0 then
                    local fr = fl + fw
                    local ft = fb + fh
                    -- Include only frames that overlap the search zone
                    if fr > zL and fl < zR and ft > zB and fb < zT then
                        local name = frame:GetName() or "(no name)"
                        local otype = frame:GetObjectType()
                        local outsideTag = ""
                        if fr <= mfLeft or fl >= mfRight or ft <= mfBottom or fb >= mfTop then
                            outsideTag = " *** OUTSIDE ***"
                        end
                        lines[#lines+1] = string.format("[%s] %s  (%.0f,%.0f)-(%.0f,%.0f)%s",
                            otype, name, fl, fb, fr, ft, outsideTag)
                        count = count + 1
                    end
                end
            end
            frame = EnumerateFrames(frame)
        end

        if count == 0 then
            lines[#lines+1] = "(none found)"
        end

        local popup = getScanPopup()
        local text = table.concat(lines, "\n")
        popup.editBox:SetText(text)
        popup.editBox:SetCursorPosition(0)
        popup:Show()
        popup:Raise()
        print("|cff00ff00AppearanceBuddy:|r Scan complete — " .. count .. " frame(s). See popup window.")
    end
end
