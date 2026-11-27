--[[
	ClickerController
	The CLICK button (bottom-centre of the HUD). Every press sends Click to the server, which keeps the player's
	fighters at full attack speed for GameConfig.Combat.ClickActiveWindow seconds; without clicks they still fight
	on their own, at IdleAttackSpeed (slower). The Auto Clicker game pass (perk AutoClicker) clicks for the player:
	the server keeps them at full speed and the button pulses on its own.

	Under the button a status pill says which speed is active (never colour alone): FULL SPEED · SLOW · AUTO CLICKER.
	Next to it, a small AUTO button offers the Auto Clicker pass once the pass exists on Roblox (PassId set) and
	the player doesn't own it yet; it is hidden otherwise (no dead buttons).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Shop = require(Shared.Config.Shop)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local ClickerController = {
	Name = "ClickerController",
	Priority = 13,
}

local SIZE = 104
local COMBAT = GameConfig.Combat
local AUTO_PULSE = 0.35 -- seconds between the button's self-presses while Auto Clicker is on
local P = Theme.Colors

ClickerController.Clock = os.clock -- overridable in tests
ClickerController.LastClick = -math.huge
ClickerController.Clicks = 0
ClickerController.AutoClicker = false

local function autoClickerPass()
	for _, pass in Shop.GamePasses do
		if pass.Perks and pass.Perks.AutoClicker then
			return pass
		end
	end
	return nil
end

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

-- Full speed right now? (recent click or Auto Clicker; mirrors CombatService:IsClicking)
function ClickerController:IsActive(): boolean
	return self.AutoClicker or self.Clock() - self.LastClick <= COMBAT.ClickActiveWindow
end

-- Press feedback: squash and an expanding ring (+ a floating "+1" for the player's own clicks).
function ClickerController:_feedback(manual: boolean?)
	self.Scale.Scale = 0.86
	tween(self.Scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	local ring = C.Frame(self.Holder, {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, SIZE / 2),
		Size = UDim2.fromOffset(SIZE, SIZE),
		ZIndex = 2,
	})
	C.Corner(ring, UDim.new(0.5, 0))
	local stroke = C.Stroke(ring, P.Gold, 4)
	tween(ring, 0.35, { Size = UDim2.fromOffset(SIZE + 46, SIZE + 46) })
	tween(stroke, 0.35, { Transparency = 1 }).Completed:Connect(function()
		ring:Destroy()
	end)
	if manual then
		local plus = C.Number(self.Holder, "+1", {
			Name = "PlusOne",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, math.random(-22, 22), 0, 4),
			Size = UDim2.fromOffset(60, 26),
			TextSize = 22,
			TextColor3 = P.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		})
		tween(plus, 0.5, { Position = plus.Position - UDim2.fromOffset(0, 34), TextTransparency = 1 }).Completed:Connect(function()
			plus:Destroy()
		end)
	end
end

-- One click: tell the server, animate, refresh the status.
function ClickerController:Click()
	self.LastClick = self.Clock()
	self.Clicks += 1
	Net.Send("Click")
	self:_feedback(true)
	self:RefreshStatus()
end

function ClickerController:RefreshStatus()
	local state = if self.AutoClicker then "Auto" elseif self:IsActive() then "Full" else "Slow"
	if state == self.State then
		return
	end
	self.State = state
	local text = { Auto = "AUTO CLICKER", Full = "FULL SPEED", Slow = ("SLOW · x%g"):format(COMBAT.IdleAttackSpeed) }
	self.StatusLabel.Text = text[state]
	self.Status.BackgroundColor3 = if state == "Slow" then P.Ink else P.Gold
	self.StatusLabel.TextColor3 = if state == "Slow" then P.TextDim else P.Ink
	self.StatusStroke.Color = if state == "Slow" then P.Line else P.Ink
end

-- Ownership of the Auto Clicker pass (asks Roblox; a failed check just means "not owned" for the visuals).
function ClickerController:RefreshPass()
	local pass = autoClickerPass()
	local owned = false
	if pass and pass.PassId ~= 0 then
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Players.LocalPlayer.UserId, pass.PassId)
		owned = ok and result == true
	end
	self.AutoClicker = owned
	self.BuyAuto.Visible = pass ~= nil and pass.PassId ~= 0 and not owned
	self:RefreshStatus()
end

function ClickerController:Init(controllers)
	self.Controllers = controllers
	local ui = controllers.UIController
	local holder = C.Frame(ui:GetRoot(), {
		Name = "Clicker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(SIZE + 120, SIZE + 34),
	})
	self.Holder = holder
	-- Big round button: gold face, dark rim, the fighters' fist in the middle, "CLICK" under the fist.
	local button = C.Create("TextButton", {
		Name = "ClickButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = P.White,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(SIZE, SIZE),
		ZIndex = 3,
		Parent = holder,
	})
	C.Corner(button, UDim.new(0.5, 0))
	C.Gradient(button, Theme.Gradients.Gold.Top, Theme.Gradients.Gold.Bottom)
	C.Stroke(button, P.Ink, 4)
	local rim = C.Frame(button, { Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 4 })
	C.Corner(rim, UDim.new(0.5, 0))
	local rimStroke = C.Stroke(rim, P.White, 2)
	rimStroke.Transparency = 0.4
	C.Icon(button, "fighters", { Size = 54, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Color = Theme.IconColors.fighters, ZIndex = 5 })
	C.Title(button, "CLICK", { Name = "Caption", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, 0, 0, 20), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, 2.5)
	self.Button = button
	self.Scale = C.Create("UIScale", { Name = "Press", Parent = button })
	button.Activated:Connect(function()
		self:Click()
	end)
	-- Status pill
	local status = C.Frame(holder, { Name = "Status", BackgroundColor3 = P.Ink, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(136, 26), ZIndex = 4 })
	C.Corner(status, UDim.new(0.5, 0))
	self.StatusStroke = C.Stroke(status, P.Line, 2)
	self.Status = status
	self.StatusLabel = C.Title(status, "", { Size = UDim2.fromScale(1, 1), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, 1.5)
	-- Small "buy Auto Clicker" button (only when the pass exists and isn't owned)
	self.BuyAuto = C.Button(holder, "AUTO", function()
		local pass = autoClickerPass()
		if pass and pass.PassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.PassId)
		end
	end, {
		Name = "BuyAutoClicker",
		Kind = "Gold",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, SIZE / 2 + 10, 0, SIZE / 2),
		Size = UDim2.fromOffset(62, 40),
		TextSize = 15,
		Visible = false,
		Confirm = false,
	})
	ui:AddScaled(holder, "Hud")
	self:RefreshStatus()
end

function ClickerController:Start()
	task.spawn(self.RefreshPass, self)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local pass = autoClickerPass()
		if purchased and player == Players.LocalPlayer and pass and pass.PassId == passId then
			self.AutoClicker = true
			self.BuyAuto.Visible = false
			self:RefreshStatus()
		end
	end)
	local sinceAuto = 0
	RunService.RenderStepped:Connect(function(dt)
		self:RefreshStatus()
		-- Auto Clicker: the button presses itself (visual only; the server already keeps full speed).
		if self.AutoClicker then
			sinceAuto += dt
			if sinceAuto >= AUTO_PULSE then
				sinceAuto = 0
				self:_feedback()
			end
		end
	end)
end

return ClickerController
