--[[
	CodesController
	"Codes" window: a text box and a REDEEM button. The server (CodesService, RedeemCode) validates the code,
	grants its rewards once per player and answers with the rewards it gave; the window only reports the result.
	Codes are listed in Shared/Config/Codes (empty until real codes are announced).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rewards = require(Shared.Modules.Rewards)
local Errors = require(Shared.Modules.Errors)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local CodesController = {
	Name = "CodesController",
	Priority = 31,
}

local MAX_LENGTH = 32

local P = Theme.Colors

function CodesController:SetStatus(text: string, good: boolean?)
	self.Status.Text = text
	self.Status.TextColor3 = if good == true then P.Cyan elseif good == false then P.Ice else P.TextDim
end

function CodesController:Redeem()
	if self.Busy then
		return
	end
	local text = string.gsub(self.Input.Text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		self:SetStatus("Type a code first.", false)
		return
	end
	self.Busy = true
	C.SetDisabled(self.RedeemButton, true)
	self:SetStatus("Checking...")
	local response = State.Request("RedeemCode", string.sub(text, 1, MAX_LENGTH))
	self.Busy = false
	C.SetDisabled(self.RedeemButton, false)
	if response.ok then
		local reward = Rewards.Describe(response.data)
		self:SetStatus("Code redeemed! " .. reward, true)
		self.Input.Text = ""
		if State.Notify then
			State.Notify("Code redeemed: " .. reward, "Success")
		end
	else
		self:SetStatus(Errors.Message(response.error), false)
	end
end

function CodesController:Init(controllers)
	self.Controllers = controllers
	local window = controllers.UIController:CreateWindow("Codes", "Codes", UDim2.fromOffset(560, 320), function()
		self:SetStatus("Codes are not case-sensitive.")
	end)
	self.Window = window
	local content = window.Content

	-- Short explanation
	local intro = C.Frame(content, { Name = "Intro", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84) })
	C.Title(intro, "Redeem a code", { Position = UDim2.fromOffset(4, 10), Size = UDim2.new(1, -8, 0, 30), TextSize = 26 }, 2.5)
	C.Label(intro, "Enter a code from the game's announcements to get free rewards. Each code works once.", {
		Position = UDim2.fromOffset(4, 42),
		Size = UDim2.new(1, -8, 0, 40),
		TextSize = 15,
		TextColor3 = P.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	-- Input row
	local row = C.Frame(content, { Name = "InputRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 56) })
	self.Input = C.TextInput(row, "Enter code here", { Name = "CodeInput", Position = UDim2.fromOffset(4, 2), Size = UDim2.new(1, -170, 0, 52) })
	self.Input:GetPropertyChangedSignal("Text"):Connect(function()
		if #self.Input.Text > MAX_LENGTH then
			self.Input.Text = string.sub(self.Input.Text, 1, MAX_LENGTH)
		end
	end)
	self.Input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self:Redeem()
		end
	end)
	self.RedeemButton = C.Button(row, "REDEEM", function()
		task.spawn(self.Redeem, self)
	end, {
		Name = "Redeem",
		Kind = "Primary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 0),
		Size = UDim2.fromOffset(150, 56),
		TextSize = 22,
		Confirm = false,
	})

	self.Status = C.Title(content, "", {
		Name = "Status",
		Position = UDim2.fromOffset(4, 176),
		Size = UDim2.new(1, -8, 0, 48),
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 2)
	self:SetStatus("Codes are not case-sensitive.")
end

return CodesController
