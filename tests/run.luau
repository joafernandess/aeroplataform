--[[
	Test runner (Lune)
	Usage (from the repository root):   lune run tests/run [filter]
	Every file in tests/specs must return function(t) where t = { describe, it, expect }.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local TestKit = require("./harness/TestKit")

local filter = process.args[1]
local files = fs.readDir("tests/specs")
table.sort(files)

local passed, failed = 0, 0
local failures = {}

for _, file in files do
	if string.match(file, "%.luau$") and (not filter or string.find(file, filter, 1, true)) then
		local specName = string.gsub(file, "%.luau$", "")
		local spec = require("./specs/" .. specName)
		local suite, t = TestKit.newSuite(file)
		local okDefine, defineErr = pcall(spec, t)
		if not okDefine then
			failed += 1
			table.insert(failures, ("%s (load): %s"):format(file, tostring(defineErr)))
		end
		for _, test in suite.Tests do
			local ok, err = xpcall(test.Fn, debug.traceback)
			if ok then
				passed += 1
			else
				failed += 1
				table.insert(failures, ("%s > %s\n    %s"):format(file, test.Name, tostring(err)))
			end
		end
		print(("%s %s"):format(stdio.color("blue") .. "•" .. stdio.color("reset"), file))
	end
end

print("")
for _, failure in failures do
	print(stdio.color("red") .. "FAIL " .. stdio.color("reset") .. failure)
end
print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
