--[[
    Central loader delivered by the bot ("Get Script" / /loader).
    {script_key}, {api_url} and {game} are filled automatically.

    Flow:
      1. Sends the key + HWID + game to the API
         (game = the one picked in Discord; when empty, the API uses
         this server's PlaceId to find the game)
      2. The API validates the key, its access to that game, and records
         the execution
      3. Returns that game's script, which is executed
]]

-- Key in GLOBAL scope (same format as the original Project Rain loader,
-- in case the script wants to read `script_key` at some point)
script_key = "{script_key}"
local api_url = "{api_url}/v1/execute"
local game_slug = "{game}"

-- Detects the user's HWID. It must be a unique ID of the PC. The executor's
-- NAME is not one (everyone on the same executor would look like the same PC),
-- so it is never used. Order: executor HWID -> Roblox client id.
local hwid = ""

local function attempt(fn)
    local ok, value = pcall(fn)
    if ok and value ~= nil and tostring(value) ~= "" then
        return tostring(value)
    end
    return ""
end

if gethwid then
    hwid = attempt(gethwid)
end
if hwid == "" and getgenv then
    hwid = attempt(function() return getgenv().HWID end)
end
if hwid == "" then
    hwid = attempt(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
end

local place_id = ""
pcall(function()
    place_id = tostring(game.PlaceId)
end)

-- URL encoding (HWIDs may contain +, /, =, spaces... without encoding the
-- API would receive the wrong HWID and the key would lock onto it)
local function url_encode(value)
    return (tostring(value):gsub("[^%w%.%-_]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local url = api_url
    .. "?key=" .. url_encode(script_key)
    .. "&hwid=" .. url_encode(hwid)
    .. "&game=" .. url_encode(game_slug)
    .. "&place=" .. url_encode(place_id)

local ok, source = pcall(function()
    return game:HttpGet(url, true)
end)

if not ok then
    error("[KeyBot] Could not connect to the script API. " ..
        "Check your connection. (" .. tostring(source) .. ")", 0)
end

local func, err = loadstring(source)
if not func then
    error("[KeyBot] Invalid response from the API: " .. tostring(err), 0)
end

func()
