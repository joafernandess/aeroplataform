--[[
	Codes
	Redeemable codes (Codes menu). Codes are case-insensitive and each player can redeem each code once
	(the claim is saved in the player's profile, so rejoining doesn't allow a second claim).

	Fields:
	  Code       text players type (letters/numbers, <= 32 chars)
	  Rewards    shared reward format: { Yen?, Gems?, Gold?, Tokens?, XP?, Items? = { [id] = n }, Units? = { unitId } }
	  ExpiresAt  optional unix time (UTC) after which the code stops working
	  Level      optional minimum player level

	No codes are active yet. Add real ones here when you announce them, e.g.:
	  { Code = "RELEASE", Rewards = { Yen = 500 } },
]]

export type CodeDef = { Code: string, Rewards: { [string]: any }, ExpiresAt: number?, Level: number? }

local Codes = {}

Codes.List = {} :: { CodeDef }

-- Codes are stored upper-case without surrounding spaces.
function Codes.Normalize(text: string): string
	return string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
end

Codes.ByCode = {} :: { [string]: CodeDef }
for _, def in Codes.List do
	local key = Codes.Normalize(def.Code)
	assert(#key > 0 and #key <= 32, "Invalid code text: " .. tostring(def.Code))
	assert(Codes.ByCode[key] == nil, "Duplicate code " .. key)
	Codes.ByCode[key] = def
end

function Codes.Get(text: string): CodeDef?
	return Codes.ByCode[Codes.Normalize(text)]
end

return Codes
