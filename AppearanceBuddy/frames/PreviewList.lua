local addon, ns = ...


local itemBackdrop = { -- small "DressingRoom"s
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 8, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}
local itemBackdropColor = {0.008, 0.008, 0.008, 0.985}
local itemBackdropBorderColor = {0.31, 0.205, 0.030, 1}
local selectedItemBackdropBorderColor = {0.85, 0.18, 0.96, 1}
local previewHighlightTexture = "Interface\\Buttons\\ButtonHilight-Square"
local previewGapX = 8
local previewGapY = 10

local function setDressingRoomSelected(dressingRoom, selected)
    if not dressingRoom then return end

    dressingRoom.isAppearanceSelected = selected and true or false
    dressingRoom:SetBackdropColor(unpack(itemBackdropColor))
    dressingRoom:SetBackdropBorderColor(unpack(selected and selectedItemBackdropBorderColor or itemBackdropBorderColor))

    local insetColor = selected and selectedItemBackdropBorderColor or itemBackdropBorderColor
    for _, texture in ipairs(dressingRoom._appearanceBuddyInsetBorder or {}) do
        texture:SetVertexColor(unpack(insetColor))
        texture:SetAlpha(selected and 0.95 or 0.72)
    end

end


local function getIndexOf(array, value)
    for i, v in ipairs(array) do
        if v == value then return i end
    end
    return nil
end

--[[
    Methods:
        GetPage
        SetPage
        GetPageCount
        SetItems(itemIds) // takes a list of integers
        SetupModel(self, width, height, x, y, z, facing, sequence)
        Update
        TryOn(item)

        Call `Update` method manually after all Set- methods. TryOn 
        items several times in the same frame can give sometimes 
        unexpected result.
]]

local function getResolvedSetup(frame, itemId)
    if frame and type(frame.getItemSetup) == "function" and tonumber(itemId) then
        local width, height, x, y, z, facing, sequence = frame.getItemSetup(tonumber(itemId))
        if tonumber(x) then
            return {
                width = width,
                height = height,
                x = x,
                y = y,
                z = z,
                facing = facing,
                sequence = sequence,
            }
        end
    end
    return frame and frame.dressingRoomSetup
end

local function getDressingRoomSetup(frame)
    local list = frame and frame:GetParent()
    return frame and (frame.itemSetup or (list and list.dressingRoomSetup))
end

local function DressingRoom_OnUpdateModel(self)
    local setup = getDressingRoomSetup(self:GetParent())
    if setup then
        self:SetSequence(tonumber(setup.sequence) or 3)
    end
end


local function button_OnClick(self, button)
    local mainFrame = self:GetParent():GetParent()
    local onItemClick = mainFrame.onItemClick
    if button == "LeftButton" then
        mainFrame.selectedItemId = self:GetParent().itemId
        if mainFrame.selectedItemId ~= nil then
            for _, dr in ipairs(mainFrame.dressingRooms) do
                setDressingRoomSelected(dr, dr.itemId == mainFrame.selectedItemId)
            end
        end
    end
    if onItemClick ~= nil then
        onItemClick(self, button)
    end
    if button == "LeftButton" then
        PlaySound("gsTitleOptionOK")
    end
end


local function button_OnEnter(self, ...)
    local onEnter = self:GetParent():GetParent().onEnter
    if onEnter ~= nil then
        onEnter(self, ...)
    end
end


local function button_OnLeave(self, ...)
    local onLeave = self:GetParent():GetParent().onLeave
    if onLeave ~= nil then
        onLeave(self, ...)
    end
end


local recycler = {
    ["recycled"] = {},
    ["counter"] = 0,

    ["get"] = function(self, parent, number)
        local result = {}
        while #result < number do
            if self.recycled[parent] == nil then self.recycled[parent] = {} end
            local recycled = self.recycled[parent]
            if #recycled > 0 then
                table.insert(result, table.remove(recycled))
            else
                self.counter = self.counter + 1
                local dr = ns.CreateDressingRoom("$parentDressingRoom"..self.counter, parent)
                if ns.Theme then
                    -- Keep the colored inner line snug to the icon without
                    -- touching the card's own tooltip-style frame border.
                    ns.Theme.ApplyInset(dr, "card", "bronze", 2)
                else
                    dr:SetBackdrop(itemBackdrop)
                    dr:SetBackdropColor(unpack(itemBackdropColor))
                    dr:SetBackdropBorderColor(unpack(itemBackdropBorderColor))
                end
                dr:EnableDragRotation(false)
                dr:EnableMouseWheel(false)
                dr.SetAppearanceSelected = setDressingRoomSelected
                dr.queriedLabel = dr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dr.queriedLabel:SetJustifyH("LEFT")
                dr.queriedLabel:SetHeight(18)
                dr.queriedLabel:SetPoint("CENTER", dr, "CENTER", 0, 0)
                dr.queriedLabel:SetText("Loading...")
                dr.queriedLabel:SetTextColor(0.84, 0.66, 0.086)
                dr.queriedLabel:Hide()
                dr.queryFailedLabel = dr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dr.queryFailedLabel:SetJustifyH("LEFT")
                dr.queryFailedLabel:SetHeight(18)
                dr.queryFailedLabel:SetPoint("CENTER", dr, "CENTER", 0, 0)
                dr.queryFailedLabel:SetText("Query failed")
                dr.queryFailedLabel:SetTextColor(0.89, 0.08, 0.10)
                dr.queryFailedLabel:Hide()
                local btn = CreateFrame("Button", "$parent".."Button", dr)
                btn:SetAllPoints()
                btn:SetHighlightTexture(previewHighlightTexture)
                btn:EnableMouse(true)
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                btn:SetScript("OnEnter", button_OnEnter)
                btn:SetScript("OnLeave", button_OnLeave)
                btn:SetScript("OnClick", button_OnClick)
                dr.button = btn
                table.insert(result, 1, dr)
            end
        end
        return result
    end,

    ["recycle"] = function(self, parent, dr)
        if self.recycled[parent] == nil then self.recycled[parent] = {} end
        local recycled = self.recycled[parent]
        for i, v in pairs(recycled) do
            assert(dr ~= v, "Double recycling.")
        end
        if dr.queryHandle and dr.queryHandle.Cancel then
            dr.queryHandle:Cancel()
        end
        dr.queryHandle = nil
        dr:OnUpdateModel(nil)
        dr:ClearModel()
        dr.itemSetup = nil
        setDressingRoomSelected(dr, false)
        dr:Hide()
        table.insert(recycled, dr)
    end,
}


local function cancelHandles(handles)
    for index = #handles, 1, -1 do
        local handle = handles[index]
        if handle and handle.Cancel then
            handle:Cancel()
        end
        handles[index] = nil
    end
end


local function PreviewList_CancelQueries(self, clearModels)
    cancelHandles(self.prefetchHandles or {})
    for _, dr in ipairs(self.dressingRooms or {}) do
        if dr.queryHandle and dr.queryHandle.Cancel then
            dr.queryHandle:Cancel()
        end
        dr.queryHandle = nil
        dr.isQuerying = false
        dr:OnUpdateModel(nil)
        if clearModels then
            dr:ClearModel()
        end
    end
end


local function PreviewList_SetItems(self, itemIds)
    PreviewList_CancelQueries(self, false)
    for _, dr in ipairs(self.dressingRooms or {}) do
        dr.queriedLabel:Hide()
        dr.queryFailedLabel:Hide()
    end
    table.wipe(self.itemIds)
    for i=1, #itemIds do
        table.insert(self.itemIds, itemIds[i])
    end
    self.selectedItemId = nil
    --if self.dressingRoomSetup ~= nil then
    --    self:Update()
    --end
end


local function PreviewList_SetupModel(self, width, height, x, y, z, facing, sequence)
    assert(#self.itemIds > 0, "`SetItems` first.")
    self.dressingRoomSetup = {
        ["width"] = width,
        ["height"] = height,
        ["x"] = x,
        ["y"] = y,
        ["z"] = z,
        ["facing"] = facing,
        ["sequence"] = sequence,
    }
    -- width/height are the card pitch.  The last card has no trailing gap,
    -- which lets the narrow browser fit the intended 5 x 4 presentation.
    local countW = math.floor((self:GetWidth() + previewGapX) / width)
    local countH = math.floor((self:GetHeight() + previewGapY) / height)
    local cardWidth = math.max(1, width - previewGapX)
    local cardHeight = math.max(1, height - previewGapY)
    local perPage = countW * countH
    if perPage > 0 then
        if #self.dressingRooms < perPage then
            local list = recycler:get(self, perPage - #self.dressingRooms)
            while #list > 0 do
                local dr = table.remove(list)
                dr:SetWidth(cardWidth)
                dr:SetHeight(cardHeight)
                table.insert(self.dressingRooms, dr)
            end
        elseif #self.dressingRooms > perPage then
            while #self.dressingRooms > perPage do
                local dr = table.remove(self.dressingRooms)
                dr:OnUpdateModel(nil)
                recycler:recycle(self, dr)
            end
        end
        local gapW = (self:GetWidth() - (countW * width - previewGapX)) / 2
        local gapH = (self:GetHeight() - (countH * height - previewGapY)) / 2
        for h = 1, countH do
            for w = 1, countW do
                local dr = self.dressingRooms[(h - 1) * countW + w]
                dr:ClearAllPoints()
                dr:SetPoint("TOPLEFT", self, "TOPLEFT", width * (w - 1) + gapW , -height * (h - 1) - gapH)
                dr.itemId = nil
                dr.itemIndex = nil
                dr.itemSetup = nil
                dr.isQuerying = false
                dr:SetSize(cardWidth, cardHeight)
                setDressingRoomSelected(dr, false)
            end
        end
    end
end


local function PreviewList_SetPage(self, page)
    assert(type(page) == "number", "`page` must be a positive number.")
    self.currentPage = page
end


local function PreviewList_GetPage(self)
    return self.currentPage
end


local function PreviewList_GetPageCount(self)
    if #self.itemIds == 0 or #self.dressingRooms == 0 then
        return 0
    end
    return math.ceil(#self.itemIds/#self.dressingRooms)
end


local function queryItemHandler(functable, itemId, success)
    local dr = functable.dressingRoom
    if dr.itemId == itemId then
        dr.queryHandle = nil
        dr.isQuerying = false
        if success then
            dr:Show()
            dr.queriedLabel:Hide()
            local setup = getResolvedSetup(dr:GetParent(), itemId)
            dr.itemSetup = setup
            dr:OnUpdateModel(nil)
            dr:Reset()
            -- For hand-weapon slots (Main Hand / Off-hand) we intentionally skip
            -- Undress().  On a fully-undressed DressUpModel WoW auto-fills both
            -- hand attachment points for dual-wield-capable classes, making a 1H
            -- weapon appear in both hands.  Keeping the player's real equipped
            -- gear on the model prevents this: the companion hand slot is already
            -- occupied so TryOn only claims the correct single slot.
            if not dr:GetParent().skipUndress then
                dr:Undress()
            end
            dr:SetPosition(tonumber(setup.x) or 0, tonumber(setup.y) or 0, tonumber(setup.z) or 0)
            dr:SetFacing(tonumber(setup.facing) or 0)
            dr:TryOn(itemId)
            if dr:GetParent().tryOnItem ~= nil then
                dr:TryOn(dr:GetParent().tryOnItem)
            end
            dr.button:Show()
            dr:OnUpdateModel(DressingRoom_OnUpdateModel)
        else
            dr:Show()
            dr:OnUpdateModel(nil)
            dr.queriedLabel:Hide()
            dr.button:Hide()
            dr.queryFailedLabel:Show()
        end
    end
end

local function PreviewList_Update(self)
    assert(self.dressingRoomSetup ~= nil, "`SetupModel` first.")
    assert(#self.itemIds > 0, "`SetItems` first.")
    local perPage = #self.dressingRooms
    for i = 1, perPage do
        local dr = self.dressingRooms[i]
        local itemIndex = (self.currentPage - 1) * perPage + i
        local itemId = self.itemIds[itemIndex]
        local samePendingQuery = itemId ~= nil
            and dr.itemId == itemId
            and dr.itemIndex == itemIndex
            and dr.isQuerying
            and dr.queryHandle ~= nil
            and dr.queryHandle.active

        if not samePendingQuery then
            if dr.queryHandle and dr.queryHandle.Cancel then
                dr.queryHandle:Cancel()
            end
            dr.queryHandle = nil
        end

        if itemId == nil then
            dr.itemId = nil
            dr.itemIndex = nil
            dr.itemSetup = nil
            dr.isQuerying = false
            dr.button:Hide()
            dr.queriedLabel:Hide()
            dr.queryFailedLabel:Hide()
            setDressingRoomSelected(dr, false)
            dr:OnUpdateModel(nil)
            dr:ClearModel()
            dr:Hide()
        elseif samePendingQuery then
            -- OnShow and parent refreshes may both update the list during the
            -- initial load.  Keep the original bounded query alive instead of
            -- cancelling and restarting the exact same work.
            dr:Show()
            dr.button:Hide()
            dr.queriedLabel:Show()
            dr.queryFailedLabel:Hide()
            setDressingRoomSelected(dr, dr.itemId == self.selectedItemId)
        else
            dr.itemId = itemId
            dr.itemIndex = itemIndex
            dr.itemSetup = nil
            dr.isQuerying = true
            dr:Show()
            dr:ClearModel()
            dr.button:Hide()
            dr.queriedLabel:Show()
            dr.queryFailedLabel:Hide()
            local handler = {
                ["dressingRoom"] = dr,
                ["__call"] = queryItemHandler,}
            setmetatable(handler, handler)
            dr.queryHandle = ns.QueryItem(itemId, handler)
            setDressingRoomSelected(dr, dr.itemId == self.selectedItemId)
        end
    end
    -- A page change or repeated show replaces ownership of adjacent-page
    -- prefetches. Releasing the old handles lets the shared query scheduler
    -- drop work that no visible consumer still needs.
    cancelHandles(self.prefetchHandles)

    -- Prefetch is optional: it competes with the client's normal item-data
    -- traffic, including loot, on a cold cache.
    local settings = ns.GetSettings and ns.GetSettings()
    if not settings or not settings.prefetchItemData then
        return
    end

    -- Pre-fetch the next page's items into WoW's item cache so they are ready
    -- when the user navigates forward, minimizing the cold-cache wait.
    local nextStart = self.currentPage * perPage + 1
    for j = nextStart, math.min(nextStart + perPage - 1, #self.itemIds) do
        local handle = ns.QueryItem(self.itemIds[j])
        if handle then
            table.insert(self.prefetchHandles, handle)
        end
    end
    -- Pre-fetch the previous page too for backward navigation.
    if self.currentPage > 1 then
        local prevStart = (self.currentPage - 2) * perPage + 1
        for j = prevStart, math.min(prevStart + perPage - 1, #self.itemIds) do
            local handle = ns.QueryItem(self.itemIds[j])
            if handle then
                table.insert(self.prefetchHandles, handle)
            end
        end
    end
end


local function PreviewList_SelectByItemId(self, itemId)
    local index = getIndexOf(self.itemIds, itemId)
    if index ~= nil then
        self.selectedItemId = itemId
        for _, dr in ipairs(self.dressingRooms) do
            setDressingRoomSelected(dr, dr.itemId == itemId)
        end
    end
end


local function PreviewList_TryOn(self, item)
    self.tryOnItem = item
    if item ~= nil then
        for i, dr in ipairs(self.dressingRooms) do
            if dr:IsVisible() and not dr.isQuerying then
                dr:TryOn(item)
            end
        end
    end
end


function ns.CreatePreviewList(parent)
    local frameName = nil
    if parent and parent.GetName then
        local parentName = parent:GetName()
        if parentName and parentName ~= "" then
            frameName = parentName.."PreviewList"
        end
    end

    local frame = CreateFrame("Frame", frameName, parent)

    frame.itemIds = {}
    frame.dressingRooms = {}
    frame.prefetchHandles = {}
    frame.currentPage = 1
    frame.dressingRoomSetup = nil
    frame.getItemSetup = nil
    --[[
    frame.dressingRoomSetup = {
        ["width"] = 0,
        ["height"] = 0,
        ["x"] = 0.0,
        ["y"] = 0.0,
        ["z"] = 0.0,
        ["facing"] = 0.0,
        ["sequence"] = 0,
    }]]
    frame.onEnter = nil
    frame.onLeave = nil
    frame.onItemClick = nil

    frame.selectedItemId = nil

    frame.SetItems = PreviewList_SetItems
    frame.Update = PreviewList_Update
    frame.SetupModel = PreviewList_SetupModel
    frame.GetPage = PreviewList_GetPage
    frame.SetPage = PreviewList_SetPage
    frame.GetPageCount = PreviewList_GetPageCount
    frame.SelectByItemId = PreviewList_SelectByItemId
    frame.TryOn = PreviewList_TryOn
    frame.CancelQueries = PreviewList_CancelQueries

    frame:SetScript("OnShow", function(self)
        if self.dressingRoomSetup ~= nil then
            self:Update()
        end
    end)
    frame:SetScript("OnHide", function(self)
        self:CancelQueries(true)
    end)

    return frame
end
