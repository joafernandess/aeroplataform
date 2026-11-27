--[[
	NotificationController
	Toast notifications (server "Notify" remote, level ups, request errors through State.Notify, zone changes)
	plus boss alerts:
	  a boss-tier enemy (MiniBoss / WorldBoss / RaidBoss) appears in Workspace.Enemies -> "⚠ Bandit King has appeared!"
	  EnemyDefeated with Boss = true                                                  -> "Boss defeated! +600 ¥"

	Layout: top-centre column under the zone pill and the target panel (toasts start at y = 112; at y = 10 while a
	window is open, since both are hidden then). The container shares the y = 10 anchor with ZoneController and
	TargetPanelController so the whole stack scales as one block.
	Identical messages merge into one toast ("… x3") and refresh its timer.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Enemies = require(Shared.Config.Enemies)
local NumberFormat = require(Shared.Modules.NumberFormat)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local NotificationController = {
	Name = "NotificationController",
	Priority = 2,
}

local P = Theme.Colors

-- Side bar colour, icon glyph and icon colours per kind (all within the black/white/blue palette).
local KINDS = {
	Info = { Bar = P.Blue500, Glyph = "i" },
	Success = { Bar = P.Cyan, Glyph = "✓" },
	Warning = { Bar = P.White, Glyph = "!" },
	Error = { Bar = P.Ink, Glyph = "!", Inverted = true },
	Quest = { Bar = P.Blue500, Glyph = "☰" },
	Level = { Bar = P.Cyan, Glyph = "▲" },
	Zone = { Bar = P.Blue500, Glyph = Theme.Icons.Worlds },
	-- Boss alerts: cyan rim + cyan icon with an ink "!" (no red in the palette).
	Boss = { Bar = P.Cyan, Glyph = "!", IconFill = P.Cyan, GlyphColor = P.Ink, Stroke = P.Cyan },
}

local MAX_TOASTS = 3
local TOAST_HEIGHT = 52
local STACK_TOP = 102 -- toasts start 102px below the shared anchor (y 10 -> 112), under the target panel
local BOSS_TIERS = { MiniBoss = true, WorldBoss = true, RaidBoss = true }
local RAID_ALERT_RANGE = 300 -- raid zones are per party: only alert for raid bosses near the local player
-- U+26A0 followed by U+FE0E (text presentation) so it renders as a monochrome glyph, not a yellow emoji.
local WARNING = utf8.char(0x26A0, 0xFE0E)

local counter = 0

function NotificationController:Show(text: string, kind: string?, duration: number?)
	local container = self.Container
	local style = KINDS[kind or "Info"] or KINDS.Info
	local lifetime = duration or 3

	-- Merge identical messages into the existing toast.
	local key = (kind or "Info") .. "\0" .. text
	local existing = self.Live[key]
	if existing and existing.Frame.Parent then
		existing.Count += 1
		existing.Label.Text = ("%s  x%d"):format(text, existing.Count)
		self:_schedule(existing, lifetime)
		return
	end

	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	counter += 1
	local toast = C.Frame(container, { Size = UDim2.new(1, 0, 0, TOAST_HEIGHT), BackgroundColor3 = P.Panel, LayoutOrder = counter })
	C.Corner(toast, Theme.Radius.Toast)
	C.Stroke(toast, if style.Inverted then P.White else style.Stroke or P.Ink, if style.Inverted then 2.5 else 3)
	local bar = C.Frame(toast, { BackgroundColor3 = style.Bar, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0, 6, 1, -16), ZIndex = 2 })
	C.Corner(bar, UDim.new(0.5, 0))
	if style.Inverted then
		C.Stroke(bar, P.White, 1.5)
	end
	local icon = C.Frame(toast, {
		BackgroundColor3 = style.IconFill or P.White,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 22, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		ZIndex = 2,
	})
	C.Corner(icon, UDim.new(0.5, 0))
	C.Stroke(icon, P.Ink, 2.5)
	C.Label(icon, style.Glyph, {
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
		TextColor3 = style.GlyphColor or P.Blue500,
		ZIndex = 3,
	})
	local label = C.Title(toast, text, {
		Name = "Message",
		Font = Theme.Fonts.Body,
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.new(1, -74, 1, 0),
		TextWrapped = true,
		TextSize = 17,
		ZIndex = 2,
	}, 1.5)
	local entry = { Frame = toast, Label = label, Count = 1, Key = key, Token = 0 }
	self.Live[key] = entry
	self:_schedule(entry, lifetime)
end

-- (Re)starts the toast's lifetime; when it runs out the whole toast fades and is removed.
function NotificationController:_schedule(entry, lifetime: number)
	entry.Token += 1
	local token = entry.Token
	task.delay(lifetime, function()
		local toast = entry.Frame
		if entry.Token ~= token or not toast.Parent then
			return
		end
		if self.Live[entry.Key] == entry then
			self.Live[entry.Key] = nil
		end
		local info = TweenInfo.new(0.3)
		local last
		for _, instance in { toast, table.unpack(toast:GetDescendants()) } do
			if instance:IsA("GuiObject") then
				last = TweenService:Create(instance, info, { BackgroundTransparency = 1 })
				last:Play()
				if instance:IsA("TextLabel") then
					TweenService:Create(instance, info, { TextTransparency = 1 }):Play()
				end
			elseif instance:IsA("UIStroke") then
				TweenService:Create(instance, info, { Transparency = 1 }):Play()
			end
		end
		if last then
			last.Completed:Connect(function()
				toast:Destroy()
			end)
		else
			toast:Destroy()
		end
	end)
end

-- Is this boss worth alerting the local player about? (same world, or a raid boss next to them)
function NotificationController:_isRelevant(model: Instance): boolean
	local zone = model:GetAttribute("Zone")
	if type(zone) ~= "string" then
		return true
	end
	if string.sub(zone, 1, 6) == "World:" then
		local data = State.Data
		return data == nil or zone == "World:" .. tostring(data.CurrentWorld)
	end
	local raids = self.Controllers.RaidController
	if not (raids and raids.Active) then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local part = model:IsA("Model") and ((model :: Model).PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
	if root and part then
		return ((root :: BasePart).Position - (part :: BasePart).Position).Magnitude <= RAID_ALERT_RANGE
	end
	return true
end

function NotificationController:OnEnemyAdded(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local tier = model:GetAttribute("Tier")
	if not (tier and BOSS_TIERS[tier] and Enemies.Tiers[tier]) then
		return
	end
	local runtimeId = model:GetAttribute("RuntimeId")
	if runtimeId ~= nil then
		if self.Announced[runtimeId] then
			return
		end
		self.Announced[runtimeId] = true
	end
	if not self:_isRelevant(model) then
		return
	end
	local name = model:GetAttribute("DisplayName") or model.Name
	self:Show(("%s %s has appeared!"):format(WARNING, name), "Boss", 5)
end

function NotificationController:OnEnemyDefeated(payload: any)
	if type(payload) ~= "table" or payload.Boss ~= true then
		return
	end
	local yen = tonumber(payload.Yen) or 0
	local text = if yen > 0 then ("Boss defeated! +%s %s"):format(NumberFormat.Abbreviate(yen), Theme.Icons.Yen) else "Boss defeated!"
	self:Show(text, "Boss", 4)
end

function NotificationController:Init(controllers)
	self.Controllers = controllers
	self.Live = {}
	self.Announced = {}
	self.Container = C.Frame(controllers.UIController:GetRoot(), {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(360, STACK_TOP + MAX_TOASTS * (TOAST_HEIGHT + 8)),
		ZIndex = 60,
	})
	self.Padding = C.Create("UIPadding", { PaddingTop = UDim.new(0, STACK_TOP), Parent = self.Container })
	C.List(self.Container, Enum.FillDirection.Vertical, 8)
	controllers.UIController:AddScaled(self.Container, "Hud")
	State.Notify = function(text, kind)
		self:Show(text, kind)
	end
end

function NotificationController:Start()
	-- While a window is open the zone pill and target panel are hidden: toasts move up to the top edge so they
	-- only cross the window's header strip instead of its content.
	self.Controllers.UIController.WindowChanged:Connect(function(name)
		self.Padding.PaddingTop = UDim.new(0, if name then 0 else STACK_TOP)
	end)
	Net.Connect("Notify", function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			self:Show(payload.Text, payload.Kind, payload.Duration)
		end
	end)
	Net.Connect("LevelUp", function(payload)
		self:Show(("Level up! You are now level %d"):format(payload.Level), "Level", 4)
	end)
	Net.Connect("EnemyDefeated", function(payload)
		self:OnEnemyDefeated(payload)
	end)
	task.spawn(function()
		local folder = Workspace:WaitForChild("Enemies", 60)
		if not folder then
			return
		end
		folder.ChildAdded:Connect(function(child)
			if child:GetAttribute("Tier") == nil then
				-- attributes not replicated yet: try once more on the next frame
				task.defer(function()
					self:OnEnemyAdded(child)
				end)
			else
				self:OnEnemyAdded(child)
			end
		end)
		folder.ChildRemoved:Connect(function(child)
			local runtimeId = child:GetAttribute("RuntimeId")
			if runtimeId ~= nil then
				self.Announced[runtimeId] = nil
			end
		end)
	end)
end

return NotificationController
