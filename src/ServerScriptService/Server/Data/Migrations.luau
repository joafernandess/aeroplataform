--[[
	Migrations
	Ordered upgrade steps for saved data. Migrations[n] converts a profile from version n to n + 1.

	How to change the data format safely:
	  1. Bump DataTemplate.CurrentVersion to N + 1.
	  2. Add Migrations[N] = function(data) ... end that rewrites old fields into the new shape.
	  3. Add a test in tests/specs that loads an old-format profile and checks the result.
	Reconcile (fill missing defaults) runs AFTER migrations, so migrations only need to handle
	renamed/removed/restructured fields.
]]

local Migrations: { [number]: (data: { [string]: any }) -> () } = {}

-- Example for the future:
-- Migrations[1] = function(data)
-- 	data.Currencies.Coins = data.Currencies.Yen
-- end

local function run(data: { [string]: any }, targetVersion: number): (boolean, string?)
	local version = tonumber(data.DataVersion) or 0
	if version < 1 then
		-- Profiles written before versioning existed are treated as version 1.
		version = 1
	end
	if version > targetVersion then
		return false, ("Profile version %d is newer than server version %d"):format(version, targetVersion)
	end
	while version < targetVersion do
		local step = Migrations[version]
		if not step then
			return false, ("Missing migration from version %d"):format(version)
		end
		step(data)
		version += 1
	end
	data.DataVersion = targetVersion
	return true, nil
end

return {
	Steps = Migrations,
	Run = run,
}
