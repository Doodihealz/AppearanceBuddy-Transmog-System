local addon, ns = ...

-- A small WotLK-safe visual system.  Keep this separate from the transmog
-- protocol/state code so the UI can change without disturbing live behavior.
local Theme = {}
ns.Theme = Theme

Theme.colors = {
    window = {0.035, 0.027, 0.024, 0.985},
    panel = {0.090, 0.059, 0.047, 0.985},
    panelRaised = {0.125, 0.082, 0.055, 0.985},
    model = {0.063, 0.047, 0.043, 0.985},
    card = {0.008, 0.008, 0.008, 0.985},
    row = {0.032, 0.032, 0.032, 0.96},
    rowHover = {0.125, 0.094, 0.035, 0.98},
    rowSelected = {0.225, 0.179, 0.042, 0.98},
    bronze = {0.55, 0.396, 0.075, 1},
    bronzeDim = {0.31, 0.205, 0.030, 1},
    gold = {0.84, 0.66, 0.086, 1},
    goldBright = {0.94, 0.74, 0.17, 1},
    text = {0.92, 0.89, 0.80, 1},
    muted = {0.52, 0.49, 0.43, 1},
    magenta = {0.85, 0.18, 0.96, 1},
    magentaDark = {0.35, 0.04, 0.45, 1},
    green = {0.18, 0.82, 0.25, 1},
    red = {0.89, 0.08, 0.10, 1},
}

Theme.backdrops = {
    window = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 5, right = 5, top = 5, bottom = 5},
    },
    panel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    },
    inset = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    },
}

local function color(frame, key, borderKey)
    local fill = Theme.colors[key or "panel"]
    local border = Theme.colors[borderKey or "bronzeDim"]
    frame:SetBackdropColor(unpack(fill))
    frame:SetBackdropBorderColor(unpack(border))
end

local function createInsetBorder(frame, inset, colorKey)
    if not frame or frame._appearanceBuddyInsetBorder then
        return frame and frame._appearanceBuddyInsetBorder
    end

    local amount = tonumber(inset) or 3
    local colorValue = Theme.colors[colorKey or "bronzeDim"]
    local border = {}
    local function edge()
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetVertexColor(unpack(colorValue))
        texture:SetAlpha(0.72)
        table.insert(border, texture)
        return texture
    end

    local top = edge()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", amount, -amount)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -amount, -amount)
    top:SetHeight(1)

    local bottom = edge()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", amount, amount)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -amount, amount)
    bottom:SetHeight(1)

    local left = edge()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", amount, -amount)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", amount, amount)
    left:SetWidth(1)

    local right = edge()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -amount, -amount)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -amount, amount)
    right:SetWidth(1)

    frame._appearanceBuddyInsetBorder = border
    return border
end

local function setInsetBorderColor(frame, colorKey, alpha)
    local colorValue = Theme.colors[colorKey or "bronzeDim"]
    for _, texture in ipairs(frame and frame._appearanceBuddyInsetBorder or {}) do
        texture:SetVertexColor(unpack(colorValue))
        texture:SetAlpha(alpha or 0.72)
    end
end

function Theme.SetInsetBorderColor(frame, colorKey, alpha)
    setInsetBorderColor(frame, colorKey, alpha)
end

function Theme.ApplyPanel(frame, kind, borderKind)
    if not frame then return end
    frame:SetBackdrop(Theme.backdrops.panel)
    color(frame, kind or "panel", borderKind or "bronzeDim")
    createInsetBorder(frame, 4, borderKind or "bronzeDim")
end

function Theme.ApplyInset(frame, kind, borderKind, innerBorderInset)
    if not frame then return end
    frame:SetBackdrop(Theme.backdrops.inset)
    color(frame, kind or "card", borderKind or "bronzeDim")
    createInsetBorder(frame, tonumber(innerBorderInset) or 3, borderKind or "bronzeDim")
end

function Theme.CreatePanel(parent, name, kind, borderKind)
    local frame = CreateFrame("Frame", name, parent)
    Theme.ApplyPanel(frame, kind, borderKind)
    return frame
end

local function hideTexture(texture)
    if texture then
        texture:SetAlpha(0)
    end
end

-- UIPanelButtonTemplate2 owns Left/Middle/Right artwork that its OnShow and
-- OnEnable scripts can redraw after a custom backdrop has been applied.  Save
-- only the template's original regions before skinning, then hide that fixed
-- set later.  Do not inspect all current regions after SetBackdrop: those
-- include AppearanceBuddy's own backdrop textures.
local function captureButtonTemplateTextures(button)
    local textures = {}
    local regions = {button:GetRegions()}
    for index = 1, #regions do
        local region = regions[index]
        if region and region:GetObjectType() == "Texture" then
            table.insert(textures, region)
        end
    end
    return textures
end

local function hideButtonTemplateTextures(button)
    for _, texture in ipairs(button._appearanceBuddyTemplateTextures or {}) do
        texture:SetAlpha(0)
        texture:Hide()
    end
end

-- InputBoxTemplate contributes its own left/middle/right chrome. Capture it
-- before adding AppearanceBuddy's backdrop, then only hide that fixed set on
-- later shows. Enumerating all current regions here would also erase the
-- custom search background and border.
local function captureEditBoxTemplateTextures(editBox)
    local textures = {}
    local regions = {editBox:GetRegions()}
    for index = 1, #regions do
        local region = regions[index]
        if region and region:GetObjectType() == "Texture" then
            table.insert(textures, region)
        end
    end
    return textures
end

local function hideEditBoxTemplateTextures(editBox)
    for _, texture in ipairs(editBox._appearanceBuddyTemplateTextures or {}) do
        texture:SetTexture(nil)
        texture:SetAlpha(0)
        texture:Hide()
    end
end

function Theme.SkinButton(button, variant)
    if not button or button._appearanceBuddyThemeButton then return end
    button._appearanceBuddyThemeButton = true
    button._appearanceBuddyTemplateTextures = captureButtonTemplateTextures(button)
    button:SetBackdrop(Theme.backdrops.inset)
    button:SetBackdropColor(unpack(Theme.colors[variant == "danger" and "card" or "row"]))
    button:SetBackdropBorderColor(unpack(Theme.colors[variant == "danger" and "red" or "bronzeDim"]))
    hideTexture(button:GetNormalTexture())
    hideTexture(button:GetPushedTexture())
    hideTexture(button:GetDisabledTexture())
    hideButtonTemplateTextures(button)
    button:HookScript("OnShow", hideButtonTemplateTextures)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(unpack(Theme.colors.goldBright))
        highlight:SetAlpha(0.22)
    end
    if button.GetFontString and button:GetFontString() then
        button:GetFontString():SetTextColor(unpack(Theme.colors.gold))
    end
    button:HookScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropBorderColor(unpack(Theme.colors.gold))
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self:IsEnabled() then
            self:SetBackdropBorderColor(unpack(Theme.colors[variant == "danger" and "red" or "bronzeDim"]))
        end
    end)
    button:HookScript("OnDisable", function(self)
        hideButtonTemplateTextures(self)
        self:SetBackdropColor(0.02, 0.02, 0.02, 0.65)
        self:SetBackdropBorderColor(0.18, 0.15, 0.12, 0.55)
    end)
    button:HookScript("OnEnable", function(self)
        hideButtonTemplateTextures(self)
        self:SetBackdropColor(unpack(Theme.colors[variant == "danger" and "card" or "row"]))
        self:SetBackdropBorderColor(unpack(Theme.colors[variant == "danger" and "red" or "bronzeDim"]))
    end)
end

function Theme.SkinItemButton(button)
    if not button or button._appearanceBuddyThemeItem then return end
    button._appearanceBuddyThemeItem = true
    button:SetBackdrop(Theme.backdrops.inset)
    button:SetBackdropColor(unpack(Theme.colors.card))
    button:SetBackdropBorderColor(unpack(Theme.colors.bronze))
    createInsetBorder(button, 3, "bronzeDim")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(unpack(Theme.colors.magenta))
        highlight:SetAlpha(0.35)
    end
end

function Theme.SkinEditBox(editBox)
    if not editBox or editBox._appearanceBuddyThemeEditBox then return end
    editBox._appearanceBuddyThemeEditBox = true
    editBox._appearanceBuddyTemplateTextures = captureEditBoxTemplateTextures(editBox)
    hideEditBoxTemplateTextures(editBox)
    editBox:SetBackdrop(Theme.backdrops.inset)
    editBox:SetBackdropColor(unpack(Theme.colors.card))
    editBox:SetBackdropBorderColor(unpack(Theme.colors.bronzeDim))
    editBox:HookScript("OnShow", hideEditBoxTemplateTextures)
    editBox:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(Theme.colors.gold))
    end)
    editBox:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(Theme.colors.bronzeDim))
    end)
end

function Theme.SkinListButton(button)
    if not button or button._appearanceBuddyThemeListButton then return end
    button._appearanceBuddyThemeListButton = true
    button:SetBackdrop(Theme.backdrops.inset)
    button:SetBackdropColor(unpack(Theme.colors.row))
    button:SetBackdropBorderColor(0.10, 0.08, 0.06, 0.9)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(unpack(Theme.colors.goldBright))
        highlight:SetAlpha(0.2)
    end
    if button.GetFontString and button:GetFontString() then
        button:GetFontString():SetTextColor(unpack(Theme.colors.gold))
    end
end

function Theme.SetSelected(button, selected, accent)
    if not button or not button.SetBackdropBorderColor then return end
    if selected then
        button:SetBackdropColor(unpack(Theme.colors.rowSelected))
        button:SetBackdropBorderColor(unpack(Theme.colors[accent or "gold"]))
        setInsetBorderColor(button, accent or "gold", 0.92)
    else
        button:SetBackdropColor(unpack(Theme.colors.row))
        button:SetBackdropBorderColor(0.10, 0.08, 0.06, 0.9)
        setInsetBorderColor(button, "bronzeDim", 0.72)
    end
end

function Theme.AddLabel(parent, point, relativeTo, relativePoint, x, y, text, font, textColor)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    label:SetPoint(point, relativeTo or parent, relativePoint or point, x or 0, y or 0)
    label:SetText(text or "")
    label:SetTextColor(unpack(Theme.colors[textColor or "gold"]))
    return label
end

function Theme.CreateDivider(parent, point, relativeTo, relativePoint, x, y, width, height)
    local divider = parent:CreateTexture(nil, "BORDER")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetPoint(point, relativeTo or parent, relativePoint or point, x or 0, y or 0)
    divider:SetSize(width or 1, height or 1)
    divider:SetVertexColor(unpack(Theme.colors.bronzeDim))
    return divider
end
