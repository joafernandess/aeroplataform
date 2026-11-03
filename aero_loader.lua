--[[
 ================================================================
  AERO — Unified Loader v2.0
  ----------------------------------------------------------------
  Single entry point for every Aero game. Users run:

      loadstring(game:HttpGet("<PUBLIC_API_URL>/loader/aero_loader.lua"))()

  What it does:
    1. Identifies the game by PlaceId (must be registered in the
       dashboard under that game — the backend matches it).
    2. Asks for the product key once (saved in getgenv().AERO_KEY
       for fast re-runs).
    3. Fetches the CURRENT script version straight from YOUR backend
       via /v1/execute (key + HWID validated SERVER-SIDE).
    4. Runs it, then re-validates against /v1/loader/heartbeat every
       N minutes. If the key gets revoked/banned/expired while
       playing, Aero is unloaded immediately.
 ----------------------------------------------------------------
  IMPORTANT — how enforcement works and its limits:
    - Every real check happens on YOUR backend. The loader itself
      carries no secrets and no decision logic.
    - The heartbeat's enforcement uses Player:Kick(), Roblox's own
      public API to disconnect the local client. This is the only
      legitimate mechanism a client-side script has; there is no
      server-side way to remove a player from a Roblox server.
    - HWID is best-effort across executors (see detect_hwid).
 ================================================================
]]

-- 🔧 CONFIG — the ONLY line you normally change -------------------
local API_URL = "http://127.0.0.1:8720"  -- must match PUBLIC_API_URL in your backend .env
-------------------------------------------------------------------

local LOADER_VERSION = "2.0"

local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer
local Core              = getgenv and getgenv() or _G

-- ----------------------------------------------------------------
-- Game identification
-- ----------------------------------------------------------------
local PlaceId = game.PlaceId
local GameId = game.GameId
local JobId   = game.JobId

local GAME_NAMES = {
    [1359573625] = "Deepwoken",
    [2753915549] = "Deepwoken",
    -- add more PlaceIds here as you launch new games (info only;
    -- the backend decides which script actually ships)
}

local function game_name()
    return GAME_NAMES[PlaceId] or ("PlaceId " .. tostring(PlaceId))
end

-- ----------------------------------------------------------------
-- HWID detection (best effort across executors)
-- ----------------------------------------------------------------
local function identify_executor()
    local execs = { identifyexecutor, getexecutorname }
    for _, fn in ipairs(execs) do
        local ok, name = pcall(fn)
        if ok and name and name ~= "" then return tostring(name) end
    end
    return "unknown"
end

local function detect_hwid()
    local attempts = {
        function() return gethwid() end,
        function() return syn.gethwid() end,
        function() return krnl_gethwid and krnl_gethwid() end,
        function() return fluxus_gethwid and fluxus_gethwid() end,
        function() return HttpService:GenerateGUID(false):sub(1, 0) end, -- never used; placeholder
    }
    for _, fn in ipairs(attempts) do
        local ok, hwid = pcall(fn)
        if ok and type(hwid) == "string" and hwid ~= "" and #hwid < 120 then
            return hwid
        end
    end
    -- Fallback: stable hash of the Roblox UserId (documented limitation: the
    -- backend requires a real HWID >= 16 chars with digits, so the raw
    -- UserId is expanded into a deterministic hex id; staff can always reset
    -- the HWID from the panel).
    local s = tostring(LocalPlayer.UserId) .. "|aero-hwid"
    local h = 0x811c9dc5
    for i = 1, #s do
        h = (h ~ string.byte(s, i)) * 16777619 % 4294967296
    end
    local hex = ""
    local v = h
    while #hex < 16 do
        hex = hex .. string.format("%08x", v)
        v = (v * 1103515245 + 12345) % 4294967296
    end
    return "uid-" .. hex:sub(1, 24) .. "-" .. tostring(LocalPlayer.UserId)
end

-- ----------------------------------------------------------------
-- HTTP with retry
-- ----------------------------------------------------------------
local function http_get(url)
    for attempt = 1, 3 do
        local ok, body = pcall(function()
            return game:HttpGet(url, true)
        end)
        if ok and body and body ~= "" then
            return true, body
        end
        warn(("[Aero] request failed (attempt %d/3): %s"):format(attempt, tostring(body)))
        task.wait(1 + attempt)
    end
    return false, "request failed after retries"
end

local function http_post_json(path, payload)
    -- Preferred: POST with a JSON body via `request` (when available).
    if request then
        for attempt = 1, 3 do
            local ok, response = pcall(function()
                return request({
                    Url = API_URL .. path,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(payload),
                })
            end)
            if ok and response and response.Success then
                local decoded
                pcall(function() decoded = HttpService:JSONDecode(response.Body) end)
                return true, decoded
            end
            task.wait(1 + attempt)
        end
    end
    -- Fallback: the same endpoints accept GET query params.
    local qs = ("?key=%s&hwid=%s&place=%s&game_id=%s&lv=%s"):format(
        url_encode(payload.key or ""), url_encode(payload.hwid or ""),
        tostring(payload.place_id or ""),
        tostring(payload.game_id or payload.universe_id or GameId or ""),
        url_encode(payload.lv or ""))
    for attempt = 1, 2 do
        local ok, body = pcall(function()
            return game:HttpGet(API_URL .. path .. qs, true)
        end)
        if ok and body and body ~= "" then
            local decoded
            pcall(function() decoded = HttpService:JSONDecode(body) end)
            return true, decoded
        end
        task.wait(1 + attempt)
    end
    return false, "request failed after retries"
end

local function url_encode(s)
    return s:gsub("[^%w%-_%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

-- ----------------------------------------------------------------
-- Stops execution with a clean message (used by every denied path)
-- ----------------------------------------------------------------
local function fail(message)
    local text = tostring(message)
    if text:sub(1, 6) ~= "[Aero]" then
        text = "[Aero] " .. text
    end
    warn(text)
    if setclipboard then pcall(function() setclipboard(text) end) end
    error(text, 0)
end

-- ----------------------------------------------------------------
-- Key UI (skipped when getgenv().AERO_KEY is already set)
-- ----------------------------------------------------------------
local function ask_for_key()
    if type(Core.AERO_KEY) == "string" and #Core.AERO_KEY >= 8 then
        return Core.AERO_KEY
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AeroLoaderUI"
    gui.ResetOnSpawn = false
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(360, 176)
    frame.Position = UDim2.new(0.5, -180, 0.5, -88)
    frame.BackgroundColor3 = Color3.fromHex("171a2a")
    frame.BorderColor3 = Color3.fromHex("303b5e")
    frame.BorderSizePixel = 2
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 34)
    title.Position = UDim2.new(0, 10, 0, 6)
    title.BackgroundTransparency = 1
    title.Text = "AERO — " .. game_name()
    title.TextColor3 = Color3.fromHex("7896d4")
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -20, 0, 16)
    subtitle.Position = UDim2.new(0, 10, 0, 40)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Paste your license key below"
    subtitle.TextColor3 = Color3.fromHex("8a97b8")
    subtitle.TextSize = 12
    subtitle.Font = Enum.Font.Gotham
    subtitle.Parent = frame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -20, 0, 30)
    box.Position = UDim2.new(0, 10, 0, 58)
    box.BackgroundColor3 = Color3.fromHex("0c0e18")
    box.BorderColor3 = Color3.fromHex("303b5e")
    box.TextColor3 = Color3.fromHex("d7dff2")
    box.PlaceholderText = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    box.TextSize = 13
    box.Font = Enum.Font.Code
    box.TextWrapped = true
    box.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Position = UDim2.new(0, 10, 0, 96)
    btn.BackgroundColor3 = Color3.fromHex("7896d4")
    btn.TextColor3 = Color3.fromHex("0c0e18")
    btn.Text = "LOAD AERO"
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.Parent = frame

    local note = Instance.new("TextLabel")
    note.Size = UDim2.new(1, -20, 0, 30)
    note.Position = UDim2.new(0, 10, 0, 130)
    note.BackgroundTransparency = 1
    note.Text = "loader v" .. LOADER_VERSION .. " · exec: " .. identify_executor()
    note.TextColor3 = Color3.fromHex("59657f")
    note.TextSize = 11
    note.Font = Enum.Font.Gotham
    note.Parent = frame

    local result = nil
    btn.MouseButton1Click:Connect(function()
        result = box.Text
    end)
    box.FocusLost:Connect(function(enter)
        if enter then result = box.Text end
    end)
    box:CaptureFocus()

    while result == nil do task.wait(0.05) end
    result = (result or ""):gsub("%s+", "")
    gui:Destroy()
    if #result < 8 then
        fail("No valid key provided. Get one from our Discord store.")
    end
    return result
end

-- ----------------------------------------------------------------
-- AutoKick heartbeat — revalidate the license while playing
-- ----------------------------------------------------------------
local autokick_running = false
local function start_heartbeat(key, hwid)
    local autokick_on, recheck = true, 5
    local ok, data = http_post_json("/v1/loader/auth", {
        key = key, hwid = hwid, place_id = PlaceId, game_id = GameId, lv = LOADER_VERSION,
    })
    if ok and type(data) == "table" then
        if data.status == "ok" and type(data.script) == "table" then
            local s = data.script
            autokick_on = (s.autokick == nil) or (s.autokick == 1)
            recheck = tonumber(s.recheck_minutes) or 5
        end
    end
    if not autokick_on then return end

    autokick_running = true
    task.spawn(function()
        local interval = math.max(60, recheck * 60)
        while autokick_running do
            task.wait(interval)
            local ok2, resp = http_post_json("/v1/loader/heartbeat", {
                key = key, hwid = hwid, place_id = PlaceId, game_id = GameId, lv = LOADER_VERSION,
            })
            if ok2 and type(resp) == "table" and resp.status == "denied" then
                autokick_running = false
                -- Legitimate client-side enforcement: disconnect THIS client.
                LocalPlayer:Kick("[Aero] Your license is no longer valid — "
                    .. tostring(resp.reason or "access denied")
                    .. ". Contact support if you believe this is an error.")
                return
            end
            -- On transport errors keep trying silently; the backend is the
            -- one that decides revocation. Never kick on network failure.
        end
    end)
end

-- ----------------------------------------------------------------
-- Boot sequence
-- ----------------------------------------------------------------
local hwid = detect_hwid()

local key = ask_for_key()
Core.AERO_KEY = key

-- heartbeat runs concurrently with delivery
start_heartbeat(key, hwid)

local url = ("%s/v1/execute?key=%s&hwid=%s&place=%s&game_id=%s&lv=%s"):format(
    API_URL, url_encode(key), url_encode(hwid), tostring(PlaceId),
    tostring(GameId), LOADER_VERSION)

local ok, body = http_get(url)
if not ok then
    fail("Could not reach the Aero license server. Check your connection.")
end

-- Denied deliveries arrive as `error("...", 0)` — executing them stops us.
if body:sub(1, 6) == "error(" then
    local message = body:match('"(.*)"') or "Access denied."
    fail(message)
end

pcall(function()
    local StarterGui = game:GetService("StarterGui")
    StarterGui:SetCore("SendNotification", {
        Title = "Aero";
        Text = game_name() .. " loaded ✓";
        Duration = 5;
    })
end)

local chunk, err = loadstring(body, "AeroScript")
if not chunk then
    fail("Malformed script received from server (" .. tostring(err) .. ").")
end

local run_ok, run_err = pcall(chunk)
if not run_ok then
    -- The script itself failed; report without masking the original error.
    warn("[Aero] Script runtime error: " .. tostring(run_err))
end
