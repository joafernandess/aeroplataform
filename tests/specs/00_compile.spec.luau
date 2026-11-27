-- Every Luau file in src/ must compile (catches syntax errors in client code that other specs don't load).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Runtime = require("../harness/Runtime")

return function(t)
	t.describe("compile", function()
		for _, path in Runtime.ListSourceFiles(".") do
			t.it(path, function()
				luau.compile(fs.readFile(path))
			end)
		end
	end)
end
