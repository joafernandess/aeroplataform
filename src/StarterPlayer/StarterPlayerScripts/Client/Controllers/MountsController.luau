--[[
	MountsController
	"Mounts" window. The game has no mount system yet, so the window is prepared (button, window, icon, layout)
	and honestly says so: no fake mounts, no buttons that do nothing. When a mount system exists, render its list
	in Render() and remove the empty state.
]]

local Client = script.Parent.Parent
local C = require(Client.UI.Components)

local MountsController = {
	Name = "MountsController",
	Priority = 37,
}

function MountsController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	C.EmptyState(self.List, "mounts", "Mounts are not available yet", "Mounts aren't part of the game yet. When they are added, you'll find, equip and ride them from this menu.")
end

function MountsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Mounts", "Mounts", UDim2.fromOffset(600, 420), function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 30), Parent = self.List })
end

return MountsController
