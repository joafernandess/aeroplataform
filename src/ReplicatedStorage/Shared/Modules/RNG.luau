--[[
	RNG
	Thin wrapper over Roblox's Random so gameplay code depends on an injectable interface.
	Tests replace the generator with a seeded or scripted one via RNG.new(seed) / custom objects.
]]

export type Generator = {
	NextNumber: (self: Generator, min: number?, max: number?) -> number,
	NextInteger: (self: Generator, min: number, max: number) -> number,
}

local RNG = {}

function RNG.new(seed: number?): Generator
	if seed then
		return Random.new(seed) :: any
	end
	return Random.new() :: any
end

--[[
	Picks a key from a { [key] = weight } map. Iteration order of Luau dictionaries is not stable, so
	keys are sorted first to make results reproducible with a seeded generator.
]]
function RNG.WeightedPick<K>(generator: Generator, weights: { [K]: number }): K?
	local keys = {}
	local total = 0
	for key, weight in weights do
		if type(weight) == "number" and weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if total <= 0 then
		return nil
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local roll = generator:NextNumber() * total
	local cumulative = 0
	for _, key in keys do
		cumulative += weights[key]
		if roll < cumulative then
			return key
		end
	end
	return keys[#keys]
end

function RNG.PickFromList<T>(generator: Generator, list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[generator:NextInteger(1, #list)]
end

function RNG.Chance(generator: Generator, probability: number): boolean
	if probability <= 0 then
		return false
	end
	if probability >= 1 then
		return true
	end
	return generator:NextNumber() < probability
end

return RNG
