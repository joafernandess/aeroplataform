--[[
	TableUtil
	Generic table helpers. Pure Luau, no Roblox APIs.
]]

local TableUtil = {}

function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[TableUtil.DeepCopy(k)] = TableUtil.DeepCopy(v)
	end
	return copy :: any
end

--[[
	Fills keys that exist in `template` but are missing (nil) in `target`, recursively.
	Existing values are never overwritten. Used to upgrade saved data when new fields are added.
	When types differ (e.g. corrupted save has a string where a table is expected) the template wins.
]]
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.DeepCopy(templateValue)
		elseif type(templateValue) == "table" then
			if type(current) ~= "table" then
				target[key] = TableUtil.DeepCopy(templateValue)
			else
				TableUtil.Reconcile(current, templateValue)
			end
		elseif type(current) ~= type(templateValue) then
			target[key] = templateValue
		end
	end
	return target
end

function TableUtil.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function TableUtil.Keys<K>(t: { [K]: any }): { K }
	local out = {}
	for k in t do
		table.insert(out, k)
	end
	return out
end

function TableUtil.ToSet<T>(list: { T }): { [T]: boolean }
	local out = {}
	for _, v in list do
		out[v] = true
	end
	return out
end

-- Appends `entry` to an array, trimming the oldest entries so the array never exceeds `limit`.
function TableUtil.PushBounded<T>(list: { T }, entry: T, limit: number)
	table.insert(list, entry)
	local overflow = #list - limit
	if overflow > 0 then
		table.move(list, overflow + 1, #list, 1)
		for i = #list - overflow + 1, #list do
			list[i] = nil
		end
	end
end

return TableUtil
