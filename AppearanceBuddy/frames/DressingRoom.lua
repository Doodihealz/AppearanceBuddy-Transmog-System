
local addon, ns = ...

local defaultWidth = 350
local defaultHeight = 430

-- SetLight(enabled, omni, dirX, dirY, dirZ, ambIntensity, ambR, ambG, ambB, dirIntensity, dirR, dirG, dirB)
local defaultLight = {1, 0, 0, 1, 0, 1, 0.7, 0.7, 0.7, 1, 0.8, 0.8, 0.64}

local zStep = 0.003 -- per pixel
local facingStep = math.rad(0.75) -- per pixel

local sex = {male = 2, female = 3}
sex[sex.male] = "male"
sex[sex.female] = "female"
local male, female = 2, 3

local modelX = { -- male = 2, female = 3
    min = {
        -- The Alliance
        Dwarf =     {male = -0.75, female = -0.75},
        Draenei =   {male = -0.75, female = -0.75},
        Gnome =     {male = -0.75, female = -0.75},
        Human =     {male = -0.75, female = -0.75},
        NightElf =  {male = -0.75, female = -0.75},
        -- The Horde
        BloodElf =  {male = -0.75, female = -0.75},
        Orc =       {male = -0.75, female = -0.75},
        Scourge =   {male = -0.75, female = -0.75},
        Tauren =    {male = -0.75, female = -0.75},
        Troll =     {male = -0.75, female = -0.75},
    },
    max = {
        -- The Alliance
        Dwarf =     {male = 2.6, female = 1.55},
        Draenei =   {male = 3.2, female = 3.0},
        Gnome =     {male = 1.44, female = 1.1},
        Human =     {male = 2.10, female = 1.9},
        NightElf =  {male = 3.3, female = 3.2},
        -- The Horde
        BloodElf =  {male = 2.9, female = 2.2},
        Orc =       {male = 2.2, female = 2.35},
        Scourge =   {male = 2.0, female = 3.0},
        Tauren =    {male = 2.90, female = 2.4},
        Troll =     {male = 3.0, female = 3.0},
    },
}

local modelZ = {
    min = {
        -- The Alliance
        Dwarf =     {male = -0.80, female = -0.60},
        Draenei =   {male = -1.15, female = -0.97},
        Gnome =     {male = -0.30, female = -0.32},
        Human =     {male = -1.05, female = -1.76},
        NightElf =  {male = -1.05, female = -0.87},
        -- The Horde
        BloodElf =  {male = -1.00, female = -0.75},
        Orc =       {male = -0.75, female = -0.75},
        Scourge =   {male = -0.80, female = -0.67},
        Tauren =    {male = -0.80, female = -0.50},
        Troll =     {male = -0.75, female = -0.75},
    },
    max = {
        -- The Alliance
        Dwarf =     {male = 0.52, female = 0.75},
        Draenei =   {male = 1.15, female = 0.92},
        Gnome =     {male = 0.48, female = 0.47},
        Human =     {male = 0.78, female = 0.77},
        NightElf =  {male = 0.96, female = 0.96},
        -- The Horde
        BloodElf =  {male = 0.75, female = 0.80},
        Orc =       {male = 0.95, female = 0.9},
        Scourge =   {male = 0.75, female = 0.85},
        Tauren =    {male = 0.90, female = 1.35},
        Troll =     {male = 1.25, female = 1.25},
    },
}

local function getModelBounds(raceFileName, unitSex)
    local supportedRaceFileName = ns.ResolveAppearanceRace and ns.ResolveAppearanceRace(raceFileName)
        or raceFileName
    local sexKey = sex[unitSex] or "male"
    local minXBySex = modelX.min[supportedRaceFileName] or modelX.min.Human
    local maxXBySex = modelX.max[supportedRaceFileName] or modelX.max.Human
    local minZBySex = modelZ.min[supportedRaceFileName] or modelZ.min.Human
    local maxZBySex = modelZ.max[supportedRaceFileName] or modelZ.max.Human

    return minXBySex[sexKey] or minXBySex.male,
        maxXBySex[sexKey] or maxXBySex.male,
        minZBySex[sexKey] or minZBySex.male,
        maxZBySex[sexKey] or maxZBySex.male
end


function ns.CreateDressingRoom(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:EnableMouseWheel(true)
    frame:SetSize(defaultWidth, defaultHeight)
    frame:SetMinResize(defaultWidth, defaultHeight)
    frame:SetMaxResize(defaultWidth, defaultHeight)

    local unit = "player"
    local _, unitRaceFileName = UnitRace(unit)
    local unitSex = UnitSex(unit)

    local model = CreateFrame("DressUpModel", nil, frame)
    model:SetAllPoints()
    model:SetUnit("player")

    local dragDummy = CreateFrame("Frame", nil, frame)
    dragDummy:SetPoint("TOPLEFT", 24, -24)
    dragDummy:SetPoint("BOTTOMRIGHT", -24, 24)
    dragDummy:EnableMouse(true)
    dragDummy:SetMovable(true)

    local function resetDragDummyPosition()
        dragDummy:StopMovingOrSizing()
        dragDummy:ClearAllPoints()
        dragDummy:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -24)
        dragDummy:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 24)
    end

    local spinVelocity = 0  -- radians/second; used for momentum after a left-button drag
    local SPIN_FRICTION = 4.0  -- decay rate: higher = stops sooner
    local SPIN_STOP_THRESHOLD = 0.05  -- rad/s below which we kill the coast loop

    dragDummy:SetScript("OnMouseDown", function(self, button)
        self:StartMoving()
        spinVelocity = 0  -- cancel any existing momentum when a new drag begins
        local cursorX, cursorY = GetCursorPosition()
        if button == "LeftButton" then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                local deltaX = newX - cursorX
                model:SetFacing(model:GetFacing() + deltaX * facingStep)
                -- Track instantaneous velocity (rad/s) with smoothing so stutter
                -- frames don't pollute the release speed.
                local dt = math.max(elapsed, 0.001)
                local instant = (deltaX * facingStep) / dt
                spinVelocity = spinVelocity * 0.4 + instant * 0.6
                cursorX, cursorY = newX, newY
            end)
        elseif button == "RightButton" and IsAltKeyDown() then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                frame:GetScript("OnMouseWheel")(frame, (newY - cursorY) * 0.05)
                cursorX, cursorY = newX, newY
            end)
        elseif button == "RightButton" then
            self:SetScript("OnUpdate", function(self, elapsed)
                local newX, newY = GetCursorPosition()
                local deltaY = newY - cursorY
                local x, y, z = model:GetPosition()
                local zOffset = zStep * deltaY
                z = z + zOffset
                local _, _, min, max = getModelBounds(unitRaceFileName, unitSex)
                z = z > max and max or z
                z = z < min and min or z
                model:SetPosition(x, y, z)
                cursorX, cursorY = newX, newY
            end)
        end
    end)

    dragDummy:SetScript("OnMouseUp", function(self, button)
        resetDragDummyPosition()

        if math.abs(spinVelocity) > SPIN_STOP_THRESHOLD then
            -- Coast to a stop: apply velocity each frame and decay it
            -- exponentially so behaviour is framerate-independent.
            self:SetScript("OnUpdate", function(self, elapsed)
                if math.abs(spinVelocity) <= SPIN_STOP_THRESHOLD then
                    spinVelocity = 0
                    self:SetScript("OnUpdate", nil)
                    return
                end
                model:SetFacing(model:GetFacing() + spinVelocity * elapsed)
                spinVelocity = spinVelocity * math.exp(-SPIN_FRICTION * elapsed)
            end)
        else
            spinVelocity = 0
            self:SetScript("OnUpdate", nil)
        end

    end)

    -- Hiding a model is a lifecycle boundary, not a synthetic mouse release.
    -- A release may start momentum, which would leave a hidden model with a
    -- stale OnUpdate that resumes the next time its parent is shown.
    dragDummy:SetScript("OnHide", function(self)
        spinVelocity = 0
        self:SetScript("OnUpdate", nil)
        resetDragDummyPosition()
    end)

    -- ---- Smooth zoom (driven by the +/-/Reset overlay buttons) ----
    local zoomVelocity = 0      -- model-x units/second
    local zoomTarget   = nil    -- non-nil: spring x towards this value
    local ZOOM_KICK     = 1.5   -- velocity impulse per button click
    local ZOOM_FRICTION = 4.0   -- exponential decay (matches spin coast)
    local ZOOM_STOP     = 0.005 -- stop threshold

    -- Keep the animation driver owned by the dressing room. Preview models can
    -- be created and hidden independently; an unparented driver would outlive
    -- its view and continue ticking after the UI closes.
    local zoomFrame = CreateFrame("Frame", nil, frame)
    zoomFrame:Hide()
    local function stopZoomAnimation()
        zoomVelocity = 0
        zoomTarget = nil
        zoomFrame:SetScript("OnUpdate", nil)
        zoomFrame:Hide()
    end

    local function zoomFrame_OnUpdate(self, elapsed)
        local dt = math.max(elapsed, 0.001)
        local x, y, z = model:GetPosition()
        local xMin, xMax = getModelBounds(unitRaceFileName, unitSex)

        if zoomTarget ~= nil then
            local diff = zoomTarget - x
            if math.abs(diff) < 0.002 then
                model:SetPosition(zoomTarget, y, z)
                stopZoomAnimation()
                return
            end
            -- Exponential approach – same feel as spin coast.
            local newX = x + diff * (1 - math.exp(-8 * dt))
            newX = math.max(xMin, math.min(xMax, newX))
            model:SetPosition(newX, y, z)
            return
        end

        if math.abs(zoomVelocity) <= ZOOM_STOP then
            stopZoomAnimation()
            return
        end

        x = x + zoomVelocity * dt
        x = math.max(xMin, math.min(xMax, x))
        model:SetPosition(x, y, z)
        zoomVelocity = zoomVelocity * math.exp(-ZOOM_FRICTION * dt)
        if (zoomVelocity > 0 and x >= xMax) or (zoomVelocity < 0 and x <= xMin) then
            stopZoomAnimation()
        end
    end

    local function armZoomAnimation()
        if zoomFrame:GetScript("OnUpdate") == nil then
            zoomFrame:SetScript("OnUpdate", zoomFrame_OnUpdate)
        end
        zoomFrame:Show()
    end

    -- direction: +1 = zoom in, -1 = zoom out
    function frame:SmoothZoom(direction)
        zoomTarget = nil
        zoomVelocity = zoomVelocity + direction * ZOOM_KICK
        armZoomAnimation()
    end

    -- Animate back to the default (x = 0) position.
    function frame:SmoothZoomReset()
        zoomTarget = 0
        zoomVelocity = 0
        armZoomAnimation()
    end

    -- Cancel any in-flight camera animation before a consumer pins a static
    -- view.  This intentionally leaves the camera position/facing unchanged;
    -- callers decide what view to apply next.
    function frame:StopCameraMotion()
        spinVelocity = 0
        dragDummy:SetScript("OnUpdate", nil)
        resetDragDummyPosition()

        stopZoomAnimation()
    end

    local dbgFrame = CreateFrame("Frame", nil, model)
    dbgFrame:Hide()
    dbgFrame:EnableMouse(false)
    dbgFrame:EnableMouseWheel(false)
    dbgFrame:SetAllPoints()

    local dbgInfo = dbgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dbgInfo:SetAllPoints()
    dbgInfo:SetJustifyH("LEFT")
    dbgInfo:SetJustifyV("TOP")

    function frame:ShowDebugInfo()
        dbgFrame:Show()
        dbgFrame:SetScript("OnUpdate", function(self, elapsed)
            local facing = model:GetFacing()
            local x, y, z = model:GetPosition()
            dbgInfo:SetFormattedText("Facing = %f\nX = %f\nZ = %f", facing, x, z)
        end)
    end

    function frame:HideDebugInfo()
        dbgFrame:SetScript("OnUpdate", nil)
        dbgFrame:Hide()
    end
    function frame:IsDebugInfoShown() return dbgFrame:IsShown() end

    function frame:Reset()
        local x, y, z = model:GetPosition()
        local facing = model:GetFacing()
        model:SetPosition(0, 0, 0)
        model:SetFacing(0)
        model:ClearModel()
        model:SetUnit("player")

        unit = "player"
        _, unitRaceFileName = UnitRace(unit)
        unitSex = UnitSex(unit)

        local minX, maxX, minZ, maxZ = getModelBounds(unitRaceFileName, unitSex)

        x = x < minX and minX or x > maxX and maxX or x
        z = z < minZ and minZ or z > maxZ and maxZ or z

        model:SetPosition(x, y, z)
        model:SetFacing(facing)
        model:SetLight(unpack(defaultLight))
    end

    function frame:SetUnit(newUnit)
        if UnitIsPlayer(newUnit) and (newUnit == "player" or CheckInteractDistance(newUnit, 1)) then
            local x, y, z = model:GetPosition()    
            local facing = model:GetFacing()
            model:SetPosition(0, 0, 0)
            model:SetFacing(0)
            model:ClearModel()
            model:SetUnit(newUnit)
            unit = newUnit
            _, unitRaceFileName = UnitRace(unit)
            unitSex = UnitSex(unit)
            local minX, maxX, minZ, maxZ = getModelBounds(unitRaceFileName, unitSex)

            x = x < minX and minX or x > maxX and maxX or x
            z = z < minZ and minZ or z > maxZ and maxZ or z

            model:SetPosition(x, y, z)
            model:SetFacing(facing)
        end
    end

    function frame:GetUnitToken()
        return unit
    end

    function frame:ClearModel(...) model:ClearModel(...) end
    function frame:TryOn(...) model:TryOn(...) end
    function frame:Undress() model:Undress() end
    function frame:GetPosition(...) return model:GetPosition(...) end
    function frame:SetPosition(...) model:SetPosition(...) end
    function frame:GetFacing(...) return model:GetFacing(...) end
    function frame:SetFacing(...) model:SetFacing(...) end
    function frame:SetCamera(...) model:SetCamera(...) end
    function frame:SetAnimation(animId) model:SetSequence(animId) end
    function frame:SetSequence(...) model:SetSequence(...) end

    function frame:SetModelScale(...) model:SetModelScale(...) end
    function frame:GetModelScale(...) return model:GetModelScale(...) end
    function frame:SetLight(...) model:SetLight(...) end
    function frame:GetLight(...) return model:GetLight(...) end
    function frame:SetModelAlpha(...) model:SetAlpha(...) end
    function frame:GetModelAlpha(...) return model:GetAlpha(...) end
    function frame:OnUpdateModel(...) model:SetScript("OnUpdateModel", ...) end
    function frame:EnableDragRotation(enable) 
        if enable then dragDummy:Show() else dragDummy:Hide() end
    end

    local originSetBackdrop = frame.SetBackdrop
    function frame:SetBackdrop(backdrop)
        originSetBackdrop(frame, backdrop)
        model:SetPoint("TOPLEFT", backdrop.insets.left * 2, -backdrop.insets.top * 2)
        model:SetPoint("BOTTOMRIGHT", -backdrop.insets.right * 2, backdrop.insets.bottom * 2)
    end

    frame:SetScript("OnMouseWheel", function(self, delta)
        self:SmoothZoom(delta)
    end)

    frame:HookScript("OnHide", function(self)
        self:StopCameraMotion()
        self:HideDebugInfo()
    end)

    for _, child in pairs({frame:GetChildren()}) do
        child:SetFrameLevel(frame:GetFrameLevel())
    end

    return frame
end
