--[[
	UpdateLog
	What players see in the "UPDATE LOG" card (top-right of the HUD) and its window.

	How to publish a new update:
	  1. Add a new table at the TOP of `Entries` (newest first) with a unique Id.
	  2. Fill Title, Date (optional, "YYYY-MM-DD") and Items (one short line per change).
	  3. Publish the game. Players who haven't opened the log since get a "NEW" dot on the card.
	Only list changes that are really in the game — the card shows the first entry as "the current update".
]]

export type Entry = {
	Id: string,
	Title: string,
	Date: string?,
	Items: { string },
}

local UpdateLog = {}

UpdateLog.Entries = {
	{
		Id = "alpha",
		Title = "Update Alpha",
		Date = "2026-11-26",
		Items = {
			"World 1 base game: click enemies, fighters attack, Yen coins fly to you",
			"Summon orb next to the spawn (open x1 / x3 with Yen)",
			"UI rework: side menus, fighter slots, zone and target panels",
			"New menus: Codes, Teleport, Index, Stats and Update Log",
			"New icon set",
		},
	},
} :: { Entry }

local seen = {}
for i, entry in UpdateLog.Entries do
	assert(type(entry.Id) == "string" and entry.Id ~= "", ("UpdateLog entry %d needs an Id"):format(i))
	assert(not seen[entry.Id], "Duplicate UpdateLog id " .. entry.Id)
	assert(type(entry.Title) == "string" and #entry.Items > 0, "UpdateLog entry needs a Title and Items: " .. entry.Id)
	seen[entry.Id] = true
end

-- The newest update (first entry), or nil when the log is empty.
function UpdateLog.GetLatest(): Entry?
	return UpdateLog.Entries[1]
end

return UpdateLog
