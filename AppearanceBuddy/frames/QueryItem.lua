local addon, ns = ...

-- Cold-cache requests can be dropped when many hyperlinks are sent through
-- the same tooltip in one frame.  Pace every emission, retry unresolved
-- requests, and keep a hard deadline so callers always receive a callback.
local QUERY_TIME = 10
local MAX_CONCURRENT_PROBES = 12
local INFO_POLL_INTERVAL = 0.05
local PROBE_INTERVAL = 0.05
local RETRY_INTERVAL = 0.75

local function invokeQueryHandler(handler, itemId, success)
    local ok, err = pcall(handler, itemId, success)
    if not ok then
        local errorHandler = geterrorhandler and geterrorhandler() or nil
        if type(errorHandler) == "function" then
            pcall(errorHandler, err)
        end
    end
end


local tooltip = CreateFrame(
    "GameTooltip",
    addon.."QueryItemTooltip",
    UIParent,
    "GameTooltipTemplate")
tooltip:SetOwner(UIParent, "ANCHOR_NONE")
tooltip:Hide()

local dummy = CreateFrame("Frame", nil, UIParent)
dummy.queries = {} -- [itemId] = query
dummy.activeProbes = {} -- [itemId] = query
dummy.activeProbeCount = 0
dummy.probeCooldown = 0
dummy.pollElapsed = 0
dummy.clock = 0
dummy.visibleQueue = {entries = {}, head = 1, tail = 0}
dummy.prefetchQueue = {entries = {}, head = 1, tail = 0}


local function resetQueue(queue)
    queue.entries = {}
    queue.head = 1
    queue.tail = 0
end

local function stopPollingIfIdle()
    if next(dummy.queries) == nil then
        -- Queue entries are lazily invalidated while scheduling.  Once all
        -- work is gone, drop them outright so stale references cannot linger.
        resetQueue(dummy.visibleQueue)
        resetQueue(dummy.prefetchQueue)
        dummy.probeCooldown = 0
        dummy.pollElapsed = 0
        dummy:SetScript("OnUpdate", nil)
    end
end

local function enqueueQuery(query)
    if query.state ~= "queued" or dummy.queries[query.itemId] ~= query then
        return
    end

    local priority = #query.handlers > 0 and "visible" or "prefetch"
    if query.queuePriority == priority then
        return
    end

    query.queuePriority = priority
    local queue = priority == "visible" and dummy.visibleQueue or dummy.prefetchQueue
    queue.tail = queue.tail + 1
    queue.entries[queue.tail] = query
end

local function popQueuedQuery(queue, priority)
    while queue.head <= queue.tail do
        local query = queue.entries[queue.head]
        queue.entries[queue.head] = nil
        queue.head = queue.head + 1

        if query ~= nil
            and query.state == "queued"
            and query.queuePriority == priority
            and dummy.queries[query.itemId] == query then
            return query
        end
    end

    resetQueue(queue)
    return nil
end

local function discardQuery(query)
    if dummy.queries[query.itemId] ~= query then
        return
    end

    dummy.queries[query.itemId] = nil
    if query.state == "active" then
        dummy.activeProbes[query.itemId] = nil
        dummy.activeProbeCount = dummy.activeProbeCount - 1
    end
    query.state = "discarded"
    query.queuePriority = nil
    for _, handle in ipairs(query.handlers) do
        handle.query = nil
        handle.handler = nil
        handle.active = false
    end
    for _, handle in ipairs(query.prefetchHandles) do
        handle.query = nil
        handle.active = false
    end
    query.handlers = {}
    query.prefetchHandles = {}
end

local function preemptOnePrefetchProbe()
    for _, query in pairs(dummy.activeProbes) do
        if #query.handlers == 0 then
            discardQuery(query)
            return true
        end
    end
    return false
end

local function startProbe(query)
    query.state = "active"
    query.queuePriority = nil
    query.retryDelay = 0
    dummy.activeProbes[query.itemId] = query
    dummy.activeProbeCount = dummy.activeProbeCount + 1
end

local function rotateProbe(query)
    if query.state ~= "active" or dummy.activeProbes[query.itemId] ~= query then
        return
    end

    dummy.activeProbes[query.itemId] = nil
    dummy.activeProbeCount = dummy.activeProbeCount - 1
    query.state = "queued"
    query.queuePriority = nil
    enqueueQuery(query)
end

local function requestProbe(query)
    if query.state ~= "active" or dummy.activeProbes[query.itemId] ~= query then
        return
    end

    -- A malformed/private-server link must not be able to abort OnUpdate and
    -- strand every card in the loading state.  The deadline remains active
    -- even when the tooltip rejects this individual request.
    pcall(function()
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:ClearLines()
        tooltip:SetHyperlink("item:".. tostring(query.itemId) ..":0:0:0:0:0:0:0")
        tooltip:Hide()
    end)
    query.lastProbeAt = dummy.clock
    query.retryDelay = RETRY_INTERVAL
end

local function shouldPreferProbe(query, candidate)
    if candidate == nil then
        return true
    end
    if query.lastProbeAt == nil then
        return candidate.lastProbeAt ~= nil or query.itemId < candidate.itemId
    end
    if candidate.lastProbeAt == nil then
        return false
    end
    if query.lastProbeAt ~= candidate.lastProbeAt then
        return query.lastProbeAt < candidate.lastProbeAt
    end
    return query.itemId < candidate.itemId
end

local function scheduleProbes()
    while dummy.activeProbeCount < MAX_CONCURRENT_PROBES do
        local query = popQueuedQuery(dummy.visibleQueue, "visible")
        if query == nil then
            query = popQueuedQuery(dummy.prefetchQueue, "prefetch")
        end
        if query == nil then
            break
        end
        startProbe(query)
    end
end

local function removeHandle(handle)
    local query = handle.query
    if query == nil then
        return
    end

    local handles = handle.prefetch and query.prefetchHandles or query.handlers
    for i = #handles, 1, -1 do
        if handles[i] == handle then
            table.remove(handles, i)
            break
        end
    end

    handle.query = nil
    handle.handler = nil
    handle.active = false

    if not handle.prefetch and #query.handlers == 0 and #query.prefetchHandles > 0 then
        -- A visible subscriber can grant an old prefetch a fresh visible wait.
        -- Once the last visible owner leaves, restore the prefetch's original
        -- deadline so hidden work cannot inherit that extension.
        query.deadline = query.prefetchDeadline
        query.visibleDeadline = nil
    end

    if #query.handlers == 0
        and (#query.prefetchHandles == 0 or query.deadline <= dummy.clock) then
        discardQuery(query)
    elseif query.state == "queued" then
        enqueueQuery(query)
    end
    scheduleProbes()
    stopPollingIfIdle()
end

local function finishQuery(query, success)
    if dummy.queries[query.itemId] ~= query then
        return
    end

    dummy.queries[query.itemId] = nil
    if query.state == "active" then
        dummy.activeProbes[query.itemId] = nil
        dummy.activeProbeCount = dummy.activeProbeCount - 1
    end
    query.state = "finished"
    query.queuePriority = nil

    local handlers = query.handlers
    query.handlers = {}
    for _, handle in ipairs(query.prefetchHandles) do
        handle.query = nil
        handle.active = false
    end
    query.prefetchHandles = {}
    for i = 1, #handlers do
        local handle = handlers[i]
        local handler = handle.handler
        handle.query = nil
        handle.handler = nil
        handle.active = false
        if not handle.cancelled and handler ~= nil then
            invokeQueryHandler(handler, query.itemId, success)
        end
    end
end

local function dummy_OnUpdate(self, elapsed)
    self.clock = self.clock + elapsed
    self.pollElapsed = self.pollElapsed + elapsed
    if self.pollElapsed < INFO_POLL_INTERVAL then
        return
    end

    elapsed = self.pollElapsed
    self.pollElapsed = 0
    self.probeCooldown = math.max(0, self.probeCooldown - elapsed)

    -- Deadlines belong to requests, not probe slots. Expire queued work too,
    -- otherwise a burst larger than MAX_CONCURRENT_PROBES fails in 10-second
    -- waves as each new group finally becomes active.
    local expiredQueries = {}
    for _, query in pairs(self.queries) do
        if query.deadline <= self.clock then
            expiredQueries[#expiredQueries + 1] = query
        end
    end
    for i = 1, #expiredQueries do
        finishQuery(expiredQueries[i], false)
    end

    scheduleProbes()

    local visibleCandidate = nil
    local prefetchCandidate = nil
    for itemId, query in pairs(self.activeProbes) do
        query.retryDelay = math.max(0, (query.retryDelay or 0) - elapsed)
        local itemInfoOK, _, itemLink = pcall(GetItemInfo, itemId)
        if not itemInfoOK then itemLink = nil end

        if itemLink ~= nil then
            -- Remove the entry before invoking callbacks so a callback can
            -- safely begin a fresh probe for the same item.
            finishQuery(query, itemLink ~= nil)
        elseif #query.handlers == 0 and #query.prefetchHandles == 0 then
            discardQuery(query)
        elseif query.retryDelay <= 0 then
            if #query.handlers > 0 then
                if shouldPreferProbe(query, visibleCandidate) then
                    visibleCandidate = query
                end
            else
                if shouldPreferProbe(query, prefetchCandidate) then
                    prefetchCandidate = query
                end
            end
        end
    end

    scheduleProbes()
    if self.probeCooldown <= 0 then
        local candidate = visibleCandidate or prefetchCandidate
        if candidate ~= nil
            and candidate.state == "active"
            and self.activeProbes[candidate.itemId] == candidate then
            requestProbe(candidate)
            -- An unresolved probe must not monopolize one of the bounded
            -- active slots. Put it behind its peers after each emission so a
            -- cold page larger than the cap gives every item a fair attempt.
            rotateProbe(candidate)
            scheduleProbes()
            self.probeCooldown = PROBE_INTERVAL
        end
    end
    stopPollingIfIdle()
end


function ns.QueryItem(itemId, handler)
    assert(type(itemId) == "number"
        and itemId == itemId
        and itemId > 0
        and itemId < math.huge
        and itemId == math.floor(itemId)
        and itemId <= 4294967295,
        "`itemId` must be a finite positive integer.")
    assert( type(handler) == "nil" or
            type(handler) == "function" or
            (type(handler) == "table" and getmetatable(handler) ~= nil and getmetatable(handler)["__call"] ~= nil),
            "'handler' must be a callable object (a function or a functable).")
    local itemInfoOK, _, itemLink = pcall(GetItemInfo, itemId)
    if not itemInfoOK then itemLink = nil end
    if itemLink ~= nil then
        if handler ~= nil then
            invokeQueryHandler(handler, itemId, true)
        end
        return nil
    end

    local queries = dummy.queries
    local query = queries[itemId]
    if query == nil then
        query = {
            itemId = itemId,
            deadline = dummy.clock + QUERY_TIME,
            prefetchDeadline = dummy.clock + QUERY_TIME,
            handlers = {},
            prefetchHandles = {},
            state = "queued",
        }
        queries[itemId] = query
    end

    if handler ~= nil then
        -- A visible consumer joining an optional prefetch receives its own
        -- bounded wait. Additional visible subscribers share that deadline so
        -- they cannot keep an unresolved query alive indefinitely.
        if #query.handlers == 0 and #query.prefetchHandles > 0 then
            query.visibleDeadline = dummy.clock + QUERY_TIME
            query.deadline = query.visibleDeadline
            query.retryDelay = 0
        end
        local handle = {
            itemId = itemId,
            query = query,
            handler = handler,
            active = true,
        }
        function handle:Cancel()
            if self.active then
                self.cancelled = true
                removeHandle(self)
            end
        end
        table.insert(query.handlers, handle)

        if query.state == "queued" then
            enqueueQuery(query)
            if dummy.activeProbeCount >= MAX_CONCURRENT_PROBES then
                preemptOnePrefetchProbe()
            end
        end
        if dummy:GetScript("OnUpdate") == nil then
            dummy:SetScript("OnUpdate", dummy_OnUpdate)
        end
        scheduleProbes()
        return handle
    end

    local prefetchHandle = {
        itemId = itemId,
        query = query,
        prefetch = true,
        active = true,
    }
    function prefetchHandle:Cancel()
        if self.active then
            self.cancelled = true
            removeHandle(self)
        end
    end
    table.insert(query.prefetchHandles, prefetchHandle)
    enqueueQuery(query)
    if dummy:GetScript("OnUpdate") == nil then
        dummy:SetScript("OnUpdate", dummy_OnUpdate)
    end
    scheduleProbes()
    return prefetchHandle
end
