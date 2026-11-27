--[[
	Features
	Switches for the game's systems. The BASE GAME (current focus) is the core loop of world 1:
	  walk -> click enemy -> fighters run and attack -> coins burst out and fly to you ->
	  open the world's star with Yen -> equip better fighters -> push to stronger zones and the boss.

	Every other system is fully implemented and tested, but disabled here so the base stays simple.
	Turning a switch on re-enables it on the server (remotes stop answering "FeatureDisabled") and in the
	UI (buttons/tabs appear). Nothing else needs to change.
]]

local Features = {
	MultipleWorlds = false, -- worlds 2-5, world unlock/teleport (base game = world 1 only)
	Quests = true, -- main/daily quests (Quests menu)
	Achievements = false, -- (removed from the UI; milestone Upgrades replace it)
	Milestones = true, -- milestone Upgrades (Upgrades menu): permanent bonuses unlocked by playing
	Raids = false,
	Shop = false, -- currency shop + Robux products UI
	Upgrades = false, -- permanent upgrades (Damage/Yen/Luck/...)
	Events = false, -- global timed modifiers
	Items = false, -- item drops, potions, items tab
	Fusion = false,
	Evolution = false,
	Traits = false, -- random traits on summoned fighters
	PlayerLevel = false, -- player XP bar in the HUD (XP is still tracked silently)
	PremiumCurrencies = false, -- Gems / Gold / Tokens in the HUD
	SummonPity = false, -- show pity counters in the summon UI (pity itself always runs)
}

function Features.IsEnabled(name: string): boolean
	return (Features :: any)[name] == true
end

-- Test/dev helper: turn every switch on or off.
function Features.SetAll(enabled: boolean)
	for key, value in Features :: any do
		if type(value) == "boolean" then
			(Features :: any)[key] = enabled
		end
	end
end

return Features
