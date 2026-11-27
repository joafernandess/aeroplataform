--[[
	Mounts
	Mount definitions for the Mounts window. EMPTY on purpose: the game has no mount system yet, so the window shows
	"not available yet" instead of fake mounts.

	To add mounts later:
	  1. Add definitions here: { Id = "M_Cloud", Name = "Swift Cloud", Rarity = "Epic", Speed = 1.25 }.
	  2. Server: store owned mounts in the profile as data.Mounts = { [mountId] = true } and the equipped one as
	     data.EquippedMount, and handle the "EquipMount" / "UnequipMount" remotes (validate ownership).
	  3. The Mounts window (Client/Controllers/MountsController) already renders the grid, rarity, equipped state
	     and the Equip / Unequip buttons from that data.
]]

export type MountDef = { Id: string, Name: string, Rarity: string, Speed: number? }

local Mounts = {}

Mounts.List = {} :: { MountDef }
Mounts.ById = {} :: { [string]: MountDef }
for _, def in Mounts.List do
	assert(not Mounts.ById[def.Id], "Duplicate mount id " .. def.Id)
	Mounts.ById[def.Id] = def
end

function Mounts.Get(id: string): MountDef?
	return Mounts.ById[id]
end

return Mounts
