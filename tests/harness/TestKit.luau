--[[
	TestKit (Lune)
	Tiny describe/it/expect framework. Specs are files in tests/specs returning function(t).
]]

local TestKit = {}

local function fmt(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function TestKit.expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(("expected %s to be %s"):format(fmt(actual), fmt(expected)), 2)
		end
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(("expected tables to be deeply equal (got %s)"):format(fmt(actual)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(("expected %s to be truthy"):format(fmt(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(("expected %s to be falsy"):format(fmt(actual)), 2)
		end
	end
	function e.toBeNil()
		if actual ~= nil then
			error(("expected nil, got %s"):format(fmt(actual)), 2)
		end
	end
	function e.toBeGreaterThan(n)
		if not (actual > n) then
			error(("expected %s > %s"):format(fmt(actual), fmt(n)), 2)
		end
	end
	function e.toBeLessThan(n)
		if not (actual < n) then
			error(("expected %s < %s"):format(fmt(actual), fmt(n)), 2)
		end
	end
	function e.toBeCloseTo(n, eps)
		if math.abs(actual - n) > (eps or 1e-6) then
			error(("expected %s to be close to %s"):format(fmt(actual), fmt(n)), 2)
		end
	end
	function e.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end
	return e
end

function TestKit.newSuite(fileName)
	local suite = { File = fileName, Tests = {}, Prefix = {} }
	local t = {}
	function t.describe(name, fn)
		table.insert(suite.Prefix, name)
		fn()
		table.remove(suite.Prefix)
	end
	function t.it(name, fn)
		local full = table.concat(suite.Prefix, " > ")
		table.insert(suite.Tests, { Name = (if full ~= "" then full .. " > " else "") .. name, Fn = fn })
	end
	t.expect = TestKit.expect
	return suite, t
end

return TestKit
