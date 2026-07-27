local addon, ns = ...

local Paging = {}

local function normalizePage(value)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then
        return 1
    end
    return math.max(1, math.floor(value))
end

local function normalizeTime(value)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then
        return 0
    end
    return math.max(0, value)
end

function Paging.New(debounceSeconds, minimumIntervalSeconds, maximumRateLimitRetries, retryMarginSeconds)
    return {
        debounceSeconds = math.max(0, tonumber(debounceSeconds) or 0),
        minimumIntervalSeconds = math.max(0, tonumber(minimumIntervalSeconds) or 0),
        maximumRateLimitRetries = math.max(0, math.floor(tonumber(maximumRateLimitRetries) or 0)),
        retryMarginSeconds = math.max(0, tonumber(retryMarginSeconds) or 0),
        generation = 0,
        targetPage = nil,
        activePage = nil,
        dueAt = 0,
        lastSentAt = 0,
        rateLimitRetries = 0,
    }
end

function Paging.PageCount(totalItemCount, pageSize)
    totalItemCount = math.max(0, math.floor(tonumber(totalItemCount) or 0))
    pageSize = math.max(1, math.floor(tonumber(pageSize) or 1))
    return math.max(1, math.ceil(totalItemCount / pageSize))
end

local function clampPage(page, totalItemCount, pageSize)
    return math.min(normalizePage(page), Paging.PageCount(totalItemCount, pageSize))
end

function Paging.DisplayPage(pager, confirmedPage)
    return normalizePage(pager.targetPage or pager.activePage or confirmedPage)
end

function Paging.CanMove(pager, confirmedPage, totalItemCount, pageSize, direction)
    direction = tonumber(direction)
    if not direction or direction == 0 then
        return false
    end
    local current = Paging.DisplayPage(pager, confirmedPage)
    local nextPage = clampPage(current + (direction < 0 and -1 or 1), totalItemCount, pageSize)
    return nextPage ~= current
end

function Paging.Cancel(pager, generation)
    pager.generation = math.max(0, math.floor(tonumber(generation) or pager.generation or 0))
    pager.targetPage = nil
    pager.activePage = nil
    pager.dueAt = 0
    pager.lastSentAt = 0
    pager.rateLimitRetries = 0
end

function Paging.Queue(pager, generation, confirmedPage, totalItemCount, pageSize, direction, now)
    generation = math.max(0, math.floor(tonumber(generation) or 0))
    direction = tonumber(direction)
    if not direction or direction == 0 then
        return false
    end

    if pager.generation ~= generation then
        Paging.Cancel(pager, generation)
    end

    local basePage = Paging.DisplayPage(pager, confirmedPage)
    local targetPage = clampPage(basePage + (direction < 0 and -1 or 1), totalItemCount, pageSize)
    if targetPage == basePage then
        return false
    end

    pager.targetPage = targetPage
    if pager.activePage == nil
        and pager.rateLimitRetries == 0
        and targetPage == normalizePage(confirmedPage) then
        pager.targetPage = nil
        return true
    end

    now = normalizeTime(now)
    pager.dueAt = math.max(
        tonumber(pager.dueAt) or 0,
        now + pager.debounceSeconds,
        (tonumber(pager.lastSentAt) or 0) + pager.minimumIntervalSeconds
    )
    return true
end

function Paging.HasScheduledRequest(pager)
    return pager.targetPage ~= nil
end

function Paging.IsReady(pager, generation, now, requestPending)
    return not requestPending
        and pager.targetPage ~= nil
        and pager.generation == math.max(0, math.floor(tonumber(generation) or 0))
        and normalizeTime(now) >= (tonumber(pager.dueAt) or 0)
end

function Paging.BeginQueued(pager, generation, now)
    if pager.generation ~= math.max(0, math.floor(tonumber(generation) or 0))
        or pager.targetPage == nil then
        return nil
    end

    pager.activePage = normalizePage(pager.targetPage)
    pager.targetPage = nil
    pager.dueAt = 0
    pager.lastSentAt = normalizeTime(now)
    return pager.activePage
end

function Paging.BeginDirect(pager, generation, page, now)
    Paging.Cancel(pager, generation)
    pager.activePage = normalizePage(page)
    pager.lastSentAt = normalizeTime(now)
    return pager.activePage
end

function Paging.RepeatActive(pager, generation, now)
    if pager.generation ~= math.max(0, math.floor(tonumber(generation) or 0))
        or pager.activePage == nil then
        return nil
    end
    pager.lastSentAt = normalizeTime(now)
    return pager.activePage
end

function Paging.Complete(pager, generation, confirmedPage, totalItemCount, pageSize, now)
    if pager.generation ~= math.max(0, math.floor(tonumber(generation) or 0)) then
        return false
    end

    pager.activePage = nil
    pager.rateLimitRetries = 0
    if pager.targetPage ~= nil then
        pager.targetPage = clampPage(pager.targetPage, totalItemCount, pageSize)
        if pager.targetPage == normalizePage(confirmedPage) then
            pager.targetPage = nil
            pager.dueAt = 0
        else
            pager.dueAt = math.max(
                tonumber(pager.dueAt) or 0,
                normalizeTime(now),
                (tonumber(pager.lastSentAt) or 0) + pager.minimumIntervalSeconds
            )
        end
    end
    return pager.targetPage ~= nil
end

function Paging.RateLimited(pager, generation, now, retryAfter)
    if pager.generation ~= math.max(0, math.floor(tonumber(generation) or 0))
        or pager.activePage == nil then
        return false
    end

    local rejectedPage = pager.activePage
    pager.activePage = nil
    pager.rateLimitRetries = pager.rateLimitRetries + 1
    if pager.rateLimitRetries > pager.maximumRateLimitRetries then
        pager.targetPage = nil
        pager.dueAt = 0
        pager.rateLimitRetries = 0
        return false
    end

    if pager.targetPage == nil then
        pager.targetPage = rejectedPage
    end

    now = normalizeTime(now)
    retryAfter = normalizeTime(retryAfter)
    local retryDelay = math.max(
        pager.minimumIntervalSeconds,
        retryAfter + pager.retryMarginSeconds
    )
    pager.dueAt = math.max(
        tonumber(pager.dueAt) or 0,
        now + retryDelay,
        (tonumber(pager.lastSentAt) or 0) + pager.minimumIntervalSeconds
    )
    return true
end

function Paging.Fail(pager, generation)
    if pager.generation ~= math.max(0, math.floor(tonumber(generation) or 0)) then
        return false
    end
    pager.targetPage = nil
    pager.activePage = nil
    pager.dueAt = 0
    pager.rateLimitRetries = 0
    return true
end

ns.TransmogPaging = Paging
