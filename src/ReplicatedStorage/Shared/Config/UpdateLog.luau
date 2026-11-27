--[[
	UpdateLog
	What players see in the "UPDATE LOG" card (top-right of the HUD) and its window. This is the only place the
	update notes live: the card shows the first entry's Title, the window lists every entry.

	How to publish a new update:
	  1. Add a new table at the TOP of `Entries` (newest first) with a unique Id.
	  2. Fill Title (the version name), Date (optional, "YYYY-MM-DD") and its Sections. Use the standard section
	     names below; leave out a section that has nothing in it.
	  3. Publish the game. Players who haven't opened the log since get a "NEW" tag on the card.
	Only list changes that are really in the game.
]]

export type Section = { Title: string, Items: { string } }
export type Entry = {
	Id: string,
	Title: string,
	Date: string?,
	Sections: { Section },
}

local UpdateLog = {}

-- Standard section names (any other name is allowed too).
UpdateLog.NEW = "New features"
UpdateLog.IMPROVED = "Improvements"
UpdateLog.FIXED = "Bug fixes"

UpdateLog.Entries = {
	{
		Id = "alpha",
		Title = "Update Alpha",
		Date = "2026-11-26",
		Sections = {
			{
				Title = UpdateLog.NEW,
				Items = {
					"World 1 base game: click enemies, fighters attack, Yen coins fly to you",
					"Summon orb next to the spawn (open x1 / x3 with Yen)",
					"New menus: Codes, Teleport, Index, Stats and Update Log",
				},
			},
			{
				Title = UpdateLog.IMPROVED,
				Items = {
					"UI rework: side menus with hotkeys, zone and target panels",
					"New icon set",
				},
			},
		},
	},
} :: { Entry }

local seen = {}
for i, entry in UpdateLog.Entries do
	assert(type(entry.Id) == "string" and entry.Id ~= "", ("UpdateLog entry %d needs an Id"):format(i))
	assert(not seen[entry.Id], "Duplicate UpdateLog id " .. entry.Id)
	assert(type(entry.Title) == "string" and type(entry.Sections) == "table" and #entry.Sections > 0, "UpdateLog entry needs a Title and Sections: " .. entry.Id)
	for _, section in entry.Sections do
		assert(type(section.Title) == "string" and #section.Items > 0, "UpdateLog section needs a Title and Items: " .. entry.Id)
	end
	seen[entry.Id] = true
end

-- The newest update (first entry), or nil when the log is empty.
function UpdateLog.GetLatest(): Entry?
	return UpdateLog.Entries[1]
end

-- Number of lines in an entry (all sections).
function UpdateLog.ItemCount(entry: Entry): number
	local n = 0
	for _, section in entry.Sections do
		n += #section.Items
	end
	return n
end

return UpdateLog
