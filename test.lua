-- SaveServersList.lua
-- Fetch public server instances for current place and save to file (executor file write)

local HttpService = game:GetService("HttpService")
local placeId = tostring(game.PlaceId)
local maxPages = 50         -- safety limit to avoid infinite loops
local perPage = 100         -- API supports up to 100
local outFilename = ("servers_%s.json"):format(placeId)

-- HTTP request helper supporting common exploit APIs and fallback to HttpGet
local function httpGet(url)
    -- try syn.request
    if syn and syn.request then
        local ok, res = pcall(syn.request, {Url = url, Method = "GET"})
        if ok and res and (res.StatusCode == 200 or res.status == 200) then
            return res.Body or res.body
        end
    end

    -- try http.request (some executors)
    if http and http.request then
        local ok, res = pcall(http.request, {Url = url, Method = "GET"})
        if ok and res and (res.StatusCode == 200 or res.status == 200) then
            return res.Body or res.body
        end
    end

    -- try request (other executors)
    if request then
        local ok, res = pcall(request, {Url = url, Method = "GET"})
        if ok and res and (res.StatusCode == 200 or res.status == 200) then
            return res.Body or res.body
        end
    end

    -- fallback to in-game HttpGet (requires HttpEnabled if used outside exploit)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok then return body end

    return nil, "no http method available"
end

-- file write helper: try common executor write functions
local function writeFile(path, content)
    local ok, err

    if writefile then
        ok, err = pcall(writefile, path, content)
        if ok then return true end
    end

    if syn and syn.write_file then
        ok, err = pcall(syn.write_file, path, content)
        if ok then return true end
    end

    if write_file then
        ok, err = pcall(write_file, path, content)
        if ok then return true end
    end

    return false, err or "no writefile available"
end

-- fetch & aggregate pages
local servers = {}
local cursor = nil
local page = 0

repeat
    page = page + 1
    if page > maxPages then
        warn("Reached maxPages, stopping pagination.")
        break
    end

    local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=%d"):format(placeId, perPage)
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end

    local body, err = httpGet(url)
    if not body then
        warn("HTTP request failed:", err)
        break
    end

    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" then
        warn("Failed to decode JSON (page "..tostring(page)..")")
        break
    end

    -- data.data is the array of servers; nextPageCursor may be present
    if type(data.data) == "table" then
        for _, serv in ipairs(data.data) do
            table.insert(servers, serv)
        end
    end

    cursor = data.nextPageCursor or nil
until not cursor or cursor == ""


-- Save collected servers to file as pretty JSON
local success, encodeErr = pcall(function()
    local encoded = HttpService:JSONEncode({ placeId = placeId, fetchedAt = os.time(), servers = servers })
    local ok, writeErr = writeFile(outFilename, encoded)
    if ok then
        print(("Saved %d server entries to %s"):format(#servers, outFilename))
    else
        error("Failed to write file: "..tostring(writeErr))
    end
end)

if not success then
    warn("Error encoding/saving servers:", encodeErr)
end
