--[[
	TargetPanelController
	Top-centre panel (360x56, y = 46) shown while you fight:
	  target = CombatController.TargetModel (clicked enemy) if alive, otherwise the enemy that took the most
	  damage in the latest DamageNumbers batch (kept while hits keep coming, forgotten FORGET_AFTER s later).
	Shows the display name (Display font, outlined), a tier tag (ELITE / MINI BOSS / BOSS), a WHITE health bar
	(enemy = white, player = blue) with "current / max" and a cyan damage trail that catches up after a beat.
	Fades out when the target dies or disappears; hidden while a window is open.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.Modules.NumberFormat)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local TargetPanelController = {
	Name = "TargetPanelController",
	Priority = 43, -- after CombatController (40) and EnemyHealthController (41)
}

TargetPanelController.FORGET_AFTER = 2.5 -- seconds without damage before a damage-picked target is dropped
TargetPanelController.INTERVAL = 0.1
TargetPanelController.TRAIL_DELAY = 0.3

TargetPanelController.Model = nil :: Model? -- enemy currently shown
TargetPanelController.Recent = nil :: Model? -- enemy picked from damage numbers
TargetPanelController.RecentAt = 0

local P = Theme.Colors
local PANEL_SIZE = Vector2.new(360, 56)
local STACK_OFFSET = 36 -- panel top relative to the shared top-centre anchor (y 10 -> 46)

-- Tier tag pills (Normal enemies have none).
local TAGS = {
	Elite = { Text = "ELITE", Fill = P.PanelLight, TextColor = P.White, Width = 58 },
	MiniBoss = { Text = "MINI BOSS", Fill = P.Blue500, TextColor = P.White, Width = 86 },
	WorldBoss = { Text = "BOSS", Fill = P.Cyan, TextColor = P.Ink, Width = 56 },
	RaidBoss = { Text = "BOSS", Fill = P.Cyan, TextColor = P.Ink, Width = 56 },
}

local function alive(model: Model?): boolean
	return model ~= nil and model.Parent ~= nil and (tonumber(model:GetAttribute("Health")) or 0) > 0
end

local function healthOf(model: Model): (number, number)
	local health = math.max(tonumber(model:GetAttribute("Health")) or 0, 0)
	local maxHealth = math.max(tonumber(model:GetAttribute("MaxHealth")) or 1, 1)
	return health, maxHealth
end

-- Finds the enemy model with this RuntimeId (registry first, then a folder scan).
function TargetPanelController:FindModel(runtimeId: any): Model?
	local registry = self.Controllers and self.Controllers.EnemyHealthController
	local model = registry and registry:GetModel(runtimeId)
	if model then
		return model
	end
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:GetAttribute("RuntimeId") == runtimeId then
			return child :: Model
		end
	end
	return nil
end

-- DamageNumbers batch: keep the current enemy if it was hit again, otherwise the one that took the most damage.
function TargetPanelController:OnDamage(list: any)
	if type(list) ~= "table" then
		return
	end
	local totals = {}
	for _, entry in list do
		if type(entry) == "table" and entry.Enemy ~= nil then
			totals[entry.Enemy] = (totals[entry.Enemy] or 0) + (tonumber(entry.Amount) or 0)
		end
	end
	local current = self.Recent and self.Recent:GetAttribute("RuntimeId")
	local chosen = if current ~= nil and totals[current] then current else nil
	if chosen == nil then
		local best = -1
		for runtimeId, amount in totals do
			if amount > best and self:FindModel(runtimeId) then
				chosen, best = runtimeId, amount
			end
		end
	end
	local model = chosen ~= nil and self:FindModel(chosen)
	if model then
		self.Recent = model
		self.RecentAt = os.clock()
		self:Update()
	end
end

-- Which enemy should the panel show right now?
function TargetPanelController:Pick(): Model?
	local combat = self.Controllers and self.Controllers.CombatController
	local clicked = combat and combat.TargetModel
	if alive(clicked) then
		return clicked
	end
	if self.Recent and alive(self.Recent) and os.clock() - self.RecentAt <= TargetPanelController.FORGET_AFTER then
		return self.Recent
	end
	self.Recent = nil
	return nil
end

-- Fill snaps (quick tween) to the new value; the cyan trail waits TRAIL_DELAY then catches up.
function TargetPanelController:Refresh()
	local model = self.Model
	if not model then
		return
	end
	local health, maxHealth = healthOf(model)
	local fraction = math.clamp(health / maxHealth, 0, 1)
	self.HealthLabel.Text = NumberFormat.Abbreviate(health) .. " / " .. NumberFormat.Abbreviate(maxHealth)
	if fraction == self.Fraction then
		return
	end
	local previous = self.Fraction or fraction
	self.Fraction = fraction
	self.Fill.Visible = fraction > 0.001
	if fraction >= previous then
		-- healed / new target: no trail
		self.TrailToken += 1
		self.Fill.Size = UDim2.fromScale(fraction, 1)
		self.Trail.Size = UDim2.fromScale(fraction, 1)
		return
	end
	TweenService:Create(self.Fill, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(fraction, 1) }):Play()
	self.TrailToken += 1
	local token = self.TrailToken
	task.delay(TargetPanelController.TRAIL_DELAY, function()
		if self.TrailToken == token then
			TweenService:Create(self.Trail, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
	end)
end

function TargetPanelController:SetTarget(model: Model?)
	if model == self.Model then
		return
	end
	if self.HealthConnection then
		self.HealthConnection:Disconnect()
		self.HealthConnection = nil
	end
	self.Model = model
	if not model then
		self:Fade(false)
		return
	end
	self.NameLabel.Text = model:GetAttribute("DisplayName") or model.Name
	local tag = TAGS[model:GetAttribute("Tier") or "Normal"]
	self.Tag.Visible = tag ~= nil
	if tag then
		self.Tag.BackgroundColor3 = tag.Fill
		self.Tag.Size = UDim2.fromOffset(tag.Width, 20)
		self.TagLabel.Text = tag.Text
		self.TagLabel.TextColor3 = tag.TextColor
		self.TagOutline.Enabled = tag.TextColor == P.White
	end
	self.NameLabel.Size = UDim2.new(1, -(24 + (if tag then tag.Width + 8 else 0)), 0, 24)
	self.Fraction = nil
	self:Refresh()
	self.HealthConnection = model:GetAttributeChangedSignal("Health"):Connect(function()
		if self.Model == model then
			self:Refresh()
			if not alive(model) then
				self:Update()
			end
		end
	end)
	self:Fade(true)
end

-- Fade every element of the panel in/out (transparency tweens), with a small pop on the way in.
function TargetPanelController:Fade(visible: boolean)
	self.FadeToken += 1
	local token = self.FadeToken
	local seconds = if visible then 0.12 else 0.3
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, if visible then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	if visible then
		if not self.Panel.Visible then
			self.PopScale.Scale = 0.92
			for _, entry in self.Faders do
				entry[1][entry[2]] = 1
			end
		end
		self.Panel.Visible = true
		TweenService:Create(self.PopScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	if not self.Panel.Visible then
		return
	end
	local last
	for _, entry in self.Faders do
		last = TweenService:Create(entry[1], info, { [entry[2]] = if visible then entry[3] else 1 })
		last:Play()
	end
	if not visible and last then
		last.Completed:Connect(function()
			if self.FadeToken == token then
				self.Panel.Visible = false
			end
		end)
	end
end

function TargetPanelController:Update()
	local target = self:Pick()
	if target ~= self.Model then
		self:SetTarget(target)
	elseif target then
		self:Refresh()
	end
end

-- Records every transparency of the panel so Fade can restore it.
local function collectFaders(root: Instance)
	local entries = {}
	local function add(instance: Instance)
		if instance:IsA("GuiObject") then
			table.insert(entries, { instance, "BackgroundTransparency", (instance :: any).BackgroundTransparency })
			if instance:IsA("TextLabel") then
				table.insert(entries, { instance, "TextTransparency", (instance :: any).TextTransparency })
			end
		elseif instance:IsA("UIStroke") then
			table.insert(entries, { instance, "Transparency", (instance :: any).Transparency })
		end
	end
	add(root)
	for _, descendant in root:GetDescendants() do
		add(descendant)
	end
	return entries
end

function TargetPanelController:Init(controllers)
	self.Controllers = controllers
	self.TrailToken = 0
	self.FadeToken = 0
	self.WindowOpen = false
	local ui = controllers.UIController

	-- Shares the top-centre anchor (y 10) with the zone pill and the toasts, so the stack scales as one.
	self.Container = C.Frame(ui:GetRoot(), {
		Name = "TargetPanel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(PANEL_SIZE.X, STACK_OFFSET + PANEL_SIZE.Y),
	})
	ui:AddScaled(self.Container, "Hud")

	local panel = C.Frame(self.Container, {
		Name = "Panel",
		BackgroundColor3 = P.Panel,
		BackgroundTransparency = 0.06,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STACK_OFFSET),
		Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		Visible = false,
	})
	self.Panel = panel
	C.Corner(panel, Theme.Radius.Card)
	C.Stroke(panel, P.Ink, Theme.Stroke.Card)
	self.PopScale = C.Create("UIScale", { Parent = panel })
	-- Inner rim (signature: near-black panel with a 1.5px Line rim inset 3px).
	local rim = C.Frame(panel, { Name = "Rim", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6) })
	C.Corner(rim, Theme.Radius.Card - 3)
	C.Stroke(rim, P.Line, Theme.Stroke.Rim)

	self.NameLabel = C.Title(panel, "", {
		Name = "EnemyName",
		Font = Theme.Fonts.Display,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -24, 0, 24),
		TextSize = 20,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	}, 2.5)

	self.Tag = C.Frame(panel, {
		Name = "Tag",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 7),
		Size = UDim2.fromOffset(56, 20),
		BackgroundColor3 = P.Cyan,
		Visible = false,
		ZIndex = 2,
	})
	C.Corner(self.Tag, UDim.new(0.5, 0))
	C.Stroke(self.Tag, P.Ink, Theme.Stroke.Badge)
	self.TagLabel = C.Label(self.Tag, "", {
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})
	self.TagOutline = C.Outline(self.TagLabel, 1.5)

	-- Health bar: ink track, cyan damage trail, WHITE fill (enemy), outlined numbers.
	local track = C.Frame(panel, {
		Name = "Health",
		BackgroundColor3 = P.Ink,
		BackgroundTransparency = 0.1,
		Position = UDim2.fromOffset(12, 31),
		Size = UDim2.new(1, -24, 0, 18),
		ZIndex = 2,
	})
	C.Corner(track, UDim.new(0.5, 0))
	C.Stroke(track, P.Ink, 2)
	self.Trail = C.Frame(track, { Name = "Trail", BackgroundColor3 = P.Cyan, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	C.Corner(self.Trail, UDim.new(0.5, 0))
	self.Fill = C.Frame(track, { Name = "Fill", BackgroundColor3 = P.White, Size = UDim2.fromScale(1, 1), ZIndex = 4 })
	C.Corner(self.Fill, UDim.new(0.5, 0))
	C.Gradient(self.Fill, Theme.Gradients.EnemyHealth.Top, Theme.Gradients.EnemyHealth.Bottom)
	self.HealthLabel = C.Label(track, "", {
		Name = "Numbers",
		Font = Theme.Fonts.Number,
		Size = UDim2.fromScale(1, 1),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
	})
	C.Outline(self.HealthLabel, 2)

	self.Faders = collectFaders(panel)
end

function TargetPanelController:Start()
	self.Controllers.UIController.WindowChanged:Connect(function(name)
		self.WindowOpen = name ~= nil
		self.Container.Visible = not self.WindowOpen
	end)
	Net.Connect("DamageNumbers", function(list)
		self:OnDamage(list)
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(self.Update, self)
			if not ok then
				warn("[TargetPanelController] " .. tostring(err))
				task.wait(5)
			end
			task.wait(TargetPanelController.INTERVAL)
		end
	end)
end

return TargetPanelController
