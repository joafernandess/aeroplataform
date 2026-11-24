--[[
	NumberFormat
	Display helpers for the UI (1.25K, 3.4M, 1h 02m...).
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function NumberFormat.Abbreviate(value: number, decimals: number?): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	value = math.abs(value)
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = tostring(math.floor(value))
	else
		local places = decimals or 2
		text = string.format("%." .. places .. "f", value):gsub("%.?0+$", "") .. SUFFIXES[index]
	end
	return if negative then "-" .. text else text
end

function NumberFormat.Commas(value: number): string
	local formatted = tostring(math.floor(value))
	local k
	repeat
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

function NumberFormat.Duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

function NumberFormat.Percent(fraction: number, decimals: number?): string
	return string.format("%." .. (decimals or 1) .. "f%%", fraction * 100)
end

return NumberFormat
