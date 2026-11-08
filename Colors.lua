-- Pidge's Forever Guild: guild colors. The Guild Master picks a color for the
-- guild's name and for each rank (Settings.lua). They show:
--
-- * in player tooltips, where the guild line becomes "Rank of Guild";
-- * in chat, wherever someone types a known guild's name (with or without
--   the angle brackets).
--
-- Other guilds' colors come from their own members' addons: hovering a player
-- from a guild we don't know yet whispers them a hidden request ("CQ"), and
-- their addon answers with their guild's colors ("CS"). Guilds without the
-- addon stay white.

local ADDON, ns = ...
local D = ns.D

local issecret = issecretvalue or function()
	return false
end

local REFRESH = 86400 -- ask other guilds again after a day
local ASK_AGAIN = 300 -- but at most every 5 minutes per guild

local function others()
	if not PidgesForeverGuildDB then
		return {}
	end
	PidgesForeverGuildDB.otherGuilds = PidgesForeverGuildDB.otherGuilds or {}
	return PidgesForeverGuildDB.otherGuilds
end

local function myGuild()
	return (GetGuildInfo("player"))
end

-- { color = "rrggbb"?, ranks = { [rankIndex + 1] = "rrggbb" } } for a guild
-- by name, or nil if we know nothing about it.
function D.GuildColors(guild)
	if not guild or guild == "" then
		return nil
	end
	if guild == myGuild() then
		return D.Links()
	end
	return others()[guild]
end

local function paint(hex, text)
	return "|cff" .. (hex or "ffffff") .. text .. "|r"
end

-- "Rank of Guild" in that guild's colors.
function D.GuildLine(guild, rankName, rankIndex)
	local c = D.GuildColors(guild) or {}
	local rankHex = c.ranks and rankIndex and c.ranks[rankIndex + 1]
	local line = paint(c.color, guild)
	if rankName and rankName ~= "" then
		line = paint(rankHex, rankName) .. paint(nil, " of ") .. line
	end
	return line
end

-- Asking other guilds ------------------------------------------------------------

local asked = {} -- guild -> when we last asked

local function askColors(guild, target)
	if not guild or guild == myGuild() or not target then
		return
	end
	local known = others()[guild]
	local now = D.Now()
	if known and now - (known.seen or 0) < REFRESH then
		return
	end
	if asked[guild] and now - asked[guild] < ASK_AGAIN then
		return
	end
	asked[guild] = now
	D.SendWhisper(target, "CQ")
end
D._askColors = askColors

-- CQ: someone from another guild wants our colors.
local replied = {}
D.HandleWhisper("CQ", function(_, sender)
	local guild = myGuild()
	if not guild then
		return
	end
	local now = D.Now()
	if replied[sender] and now - replied[sender] < 60 then
		return
	end
	replied[sender] = now
	local l = D.Links()
	D.SendWhisper(sender, "CS", guild, l.t or 0, l.color or "", D.EncodeRanks(l.ranks), D.VERSION)
end)

-- CS guild t color ranks version: another guild's colors, which we asked for.
D.HandleWhisper("CS", function(f)
	local guild = f[2]
	if not guild or guild == "" or guild == myGuild() or not asked[guild] then
		return
	end
	local color = f[4] and f[4]:match("^%x%x%x%x%x%x$")
	others()[guild] = {
		color = color and color:lower() or nil,
		ranks = D.DecodeRanks(f[5]),
		t = tonumber(f[3]) or 0,
		seen = D.Now(),
	}
	D.Fire("COLORS", guild)
end)

-- Tooltips -----------------------------------------------------------------------

local function unitTarget(unit)
	local name, realm = UnitName(unit)
	if not name or issecret(name) then
		return nil
	end
	if realm and realm ~= "" and not issecret(realm) then
		return name .. "-" .. realm
	end
	return name
end

local function onUnitTooltip(tooltip)
	if tooltip ~= GameTooltip or not D.InGuild() or not tooltip.GetUnit then
		return
	end
	local _, unit = tooltip:GetUnit()
	if not unit or issecret(unit) or not UnitIsPlayer(unit) then
		return
	end
	local guild, rankName, rankIndex = GetGuildInfo(unit)
	if not guild or issecret(guild) or issecret(rankName) then
		return
	end
	local prefix = tooltip:GetName()
	for i = 2, tooltip:NumLines() do
		local fs = _G[prefix .. "TextLeft" .. i]
		local text = fs and fs:GetText()
		if text and not issecret(text) and text:find(guild, 1, true) then
			fs:SetText(D.GuildLine(guild, rankName, rankIndex))
			fs:SetTextColor(1, 1, 1)
			break
		end
	end
	askColors(guild, unitTarget(unit))
end

local function safeTooltip(tooltip)
	pcall(onUnitTooltip, tooltip)
end
D._onUnitTooltip = onUnitTooltip

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, safeTooltip)
elseif GameTooltip and GameTooltip.HookScript then
	GameTooltip:HookScript("OnTooltipSetUnit", safeTooltip)
end

-- Chat ----------------------------------------------------------------------------
-- A message filter, which the default chat frames and chat addons (Prat,
-- Chatter, Chattynator) all run messages through before showing them.

-- Guilds whose name we color: { lower = "name", hex = "rrggbb" }, longest first
-- so "Dream Team" wins over "Dream".
local function coloredGuilds()
	local list = {}
	local mine = myGuild()
	local myColor = D.Links().color
	if mine and myColor then
		list[#list + 1] = { lower = mine:lower(), hex = myColor }
	end
	for name, c in pairs(others()) do
		if c.color and name ~= mine then
			list[#list + 1] = { lower = name:lower(), hex = c.color }
		end
	end
	table.sort(list, function(a, b)
		return #a.lower > #b.lower
	end)
	return list
end

local function isWordChar(c)
	return c ~= "" and c:match("[%w\128-\255]") ~= nil
end

-- Color guild names in plain text (no links or codes in it).
local function colorPlain(text, list)
	local lower = text:lower()
	local out, pos = {}, 1
	while pos <= #text do
		local bestS, bestE, bestHex
		for _, g in ipairs(list) do
			local from = pos
			while true do
				local s, e = lower:find(g.lower, from, true)
				if not s then
					break
				end
				if not isWordChar(text:sub(s - 1, s - 1)) and not isWordChar(text:sub(e + 1, e + 1)) then
					if not bestS or s < bestS then
						bestS, bestE, bestHex = s, e, g.hex
					end
					break
				end
				from = s + 1
			end
		end
		if not bestS then
			break
		end
		if text:sub(bestS - 1, bestS - 1) == "<" and text:sub(bestE + 1, bestE + 1) == ">" and bestS - 1 >= pos then
			bestS, bestE = bestS - 1, bestE + 1
		end
		out[#out + 1] = text:sub(pos, bestS - 1)
		out[#out + 1] = "|cff" .. bestHex .. text:sub(bestS, bestE) .. "|r"
		pos = bestE + 1
	end
	out[#out + 1] = text:sub(pos)
	return table.concat(out)
end

-- Links, textures, atlases and existing color codes are left alone.
local SKIP = { "|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", "|H.-|h.-|h", "|T.-|t", "|A.-|a", "|c%x%x%x%x%x%x%x%x", "|r", "|n" }

function D.ColorGuildNames(msg)
	if type(msg) ~= "string" or issecret(msg) or msg == "" then
		return msg
	end
	local list = coloredGuilds()
	if #list == 0 then
		return msg
	end
	local out, pos = {}, 1
	while pos <= #msg do
		local s, e
		for _, pat in ipairs(SKIP) do
			local ps, pe = msg:find(pat, pos)
			if ps and (not s or ps < s) then
				s, e = ps, pe
			end
		end
		if not s then
			break
		end
		out[#out + 1] = colorPlain(msg:sub(pos, s - 1), list)
		out[#out + 1] = msg:sub(s, e)
		pos = e + 1
	end
	out[#out + 1] = colorPlain(msg:sub(pos), list)
	return table.concat(out)
end

local function filter(_, _, msg, ...)
	if not D.InGuild() then
		return false
	end
	local ok, new = pcall(D.ColorGuildNames, msg)
	if ok and new ~= msg then
		return false, new, ...
	end
	return false
end

local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_SYSTEM",
}

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
	for _, event in ipairs(CHAT_EVENTS) do
		pcall(addFilter, event, filter)
	end
end
