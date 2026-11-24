--[[
	CoinController
	Coin burst when an enemy you defeated dies (EnemyDefeated remote): spinning Yen coins pop out of the
	enemy, land around it, then fly into your character, and "+X ¥" pops over your head.
	Purely cosmetic — the server already credited the Yen (EnemyService -> EconomyService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.Modules.NumberFormat)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local CoinController = {
	Name = "CoinController",
	Priority = 44,
}

local BURST_TIME = 0.35
local REST_TIME = 0.4
local FLY_TIME = 0.3
local MAX_ACTIVE = 120

local active: { any } = {}

local function coinCount(yen: number, boss: boolean): number
	if boss then
		return 18
	end
	return math.clamp(math.ceil(math.log10(math.max(yen, 1) + 1) * 3), 3, 10)
end

function CoinController:Burst(payload)
	if type(payload) ~= "table" or type(payload.Position) ~= "table" then
		return
	end
	local origin = Vector3.new(payload.Position[1], payload.Position[2], payload.Position[3])
	local groundY = origin.Y - 1
	local count = coinCount(payload.Yen or 0, payload.Boss == true)
	local batch = { Yen = payload.Yen or 0, Shown = false }
	local now = os.clock()
	for i = 1, count do
		if #active >= MAX_ACTIVE then
			break
		end
		local angle = math.random() * math.pi * 2
		local distance = 3 + math.random() * (if payload.Boss then 9 else 5)
		local coin = C.Create("Part", {
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, 1.3, 1.3),
			Color = Theme.Colors.Yen,
			Material = Enum.Material.Neon,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			CFrame = CFrame.new(origin),
			Parent = self.Folder,
		})
		table.insert(active, {
			Part = coin,
			Born = now + i * 0.015,
			From = origin + Vector3.new(0, 2, 0),
			Landing = Vector3.new(origin.X + math.cos(angle) * distance, groundY + 0.7, origin.Z + math.sin(angle) * distance),
			Spin = math.random() * math.pi,
			Batch = batch,
		})
	end
end

function CoinController:Popup(text: string)
	local character = Players.LocalPlayer.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head then
		return
	end
	local gui = C.Create("BillboardGui", {
		Size = UDim2.fromOffset(140, 36),
		StudsOffsetWorldSpace = Vector3.new(math.random(-10, 10) / 10, 2.5, 0),
		AlwaysOnTop = true,
		Adornee = head,
		Parent = self.Folder,
	})
	local label = C.Title(gui, text, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Colors.Yen }, 2)
	TweenService:Create(gui, TweenInfo.new(0.9), { StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	task.delay(0.95, function()
		gui:Destroy()
	end)
end

function CoinController:Step()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local now = os.clock()
	for i = #active, 1, -1 do
		local coin = active[i]
		local age = now - coin.Born
		local position: Vector3
		if age < 0 then
			position = coin.From
		elseif age < BURST_TIME then
			local a = age / BURST_TIME
			position = coin.From:Lerp(coin.Landing, a) + Vector3.new(0, math.sin(a * math.pi) * 4, 0)
		elseif age < BURST_TIME + REST_TIME or not root then
			position = coin.Landing
		elseif age < BURST_TIME + REST_TIME + FLY_TIME then
			local a = (age - BURST_TIME - REST_TIME) / FLY_TIME
			position = coin.Landing:Lerp(root.Position, a * a)
		else
			coin.Part:Destroy()
			table.remove(active, i)
			if not coin.Batch.Shown and coin.Batch.Yen > 0 then
				coin.Batch.Shown = true
				self:Popup("+" .. NumberFormat.Abbreviate(coin.Batch.Yen) .. " " .. Theme.Icons.Yen)
			end
			continue
		end
		coin.Part.CFrame = CFrame.new(position) * CFrame.Angles(0, coin.Spin + now * 6, 0)
	end
end

function CoinController:Init(controllers)
	self.Controllers = controllers
	self.Folder = C.Create("Folder", { Name = "LocalCoins", Parent = Workspace })
end

function CoinController:Start()
	Net.Connect("EnemyDefeated", function(payload)
		self:Burst(payload)
	end)
	RunService.RenderStepped:Connect(function()
		self:Step()
	end)
end

return CoinController
