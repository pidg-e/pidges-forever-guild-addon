-- Pidge's Forever Guild: shared setup. Saved data, names, guild addon messages and the
-- guild panel loader that the other files build on.

local ADDON, ns = ...

PidgesForeverGuild = PidgesForeverGuild or {}
local D = PidgesForeverGuild
ns.D = D

D.PREFIX = "PidgesForever" -- addon message prefix (16 characters at most)
D.TITLE = "Pidge's Forever Guild AddOn"
D.COLOR = "|cff9b7bff"
D.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"

function D.print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(D.COLOR .. "Pidge's Forever|r: " .. msg)
end

-- Names -----------------------------------------------------------------------

local myName

function D.MyGUID()
	return UnitGUID and UnitGUID("player")
end

-- Our name as guildmates' addons see it ("Name-Realm"), so names compare
-- equal everywhere. Our best guess comes from UnitName and the realm, but
-- the server's spelling can differ (WoW Forever adds surnames, for one), so
-- at login we send ourselves a hello and use the sender name it comes back
-- with. That spelling is remembered for next time.
function D.Me()
	if not myName then
		local saved = PidgesForeverGuildDB and PidgesForeverGuildDB.me and PidgesForeverGuildDB.me[D.MyGUID() or ""]
		if saved then
			myName = saved
		else
			local name = UnitName("player")
			local realm = GetNormalizedRealmName and GetNormalizedRealmName()
			return realm and realm ~= "" and (name .. "-" .. realm) or name
		end
	end
	return myName
end

local helloNonce

local function learnMyName(sender)
	myName = sender
	local guid = D.MyGUID()
	if guid and PidgesForeverGuildDB then
		PidgesForeverGuildDB.me = PidgesForeverGuildDB.me or {}
		PidgesForeverGuildDB.me[guid] = sender
	end
	D.Fire("ME", sender)
end

-- Adds our realm to a bare name ("Bob" -> "Bob-Realm").
function D.FullName(name)
	if not name or name == "" then
		return nil
	end
	if name:find("-", 1, true) then
		return name
	end
	local realm = D.Me():match("%-(.+)$")
	return realm and (name .. "-" .. realm) or name
end

-- Name for display: "Hip Hop-SomeRealm" -> "Hip Hop". Names can hold
-- spaces (WoW Forever surnames) but never a hyphen, so the realm is
-- everything after the last one.
function D.Short(name)
	if not name or name == "" then
		return "?"
	end
	return (name:gsub("%-[^%-]*$", ""))
end

function D.Now()
	return GetServerTime and GetServerTime() or time()
end

-- Saved data ----------------------------------------------------------------
-- PidgesForeverGuildDB.guilds[guild] = { orders = { [id] = order }, profs = { [name] = entry } }

-- Are we in a guild? Nothing in the addon shows or talks otherwise.
-- The guild name can take a few seconds to arrive after login, so until it
-- does this is false and the "GUILD" event fires once it changes (or when we
-- move to another guild).
function D.InGuild()
	return D.GuildKey() ~= nil
end

-- "Guild Name-Realm": saved data is kept per guild, so a character that
-- changes guild (or an alt in another one) never mixes the two.
function D.GuildKey()
	if not IsInGuild() then
		return nil
	end
	local name, _, _, realm = GetGuildInfo("player")
	if not name or name == "" then
		return nil
	end
	realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName())
	if realm and realm ~= "" then
		return name .. "-" .. realm
	end
	return name
end

function D.Data()
	local key = D.GuildKey()
	if not key then
		return nil
	end
	PidgesForeverGuildDB.guilds = PidgesForeverGuildDB.guilds or {}
	local g = PidgesForeverGuildDB.guilds[key]
	if not g then
		g = { orders = {}, profs = {} }
		PidgesForeverGuildDB.guilds[key] = g
	end
	return g
end

-- Ranks -----------------------------------------------------------------------------

-- Names are compared without realm and case.
function D.SameName(a, b)
	return a and b and D.Short(a):lower() == D.Short(b):lower() or false
end

-- A guildmate's rank index (0 = Guild Master) from the roster, or nil.
function D.RankIndexOf(name)
	if D.SameName(name, D.Me()) then
		local _, _, rankIndex = GetGuildInfo("player")
		return rankIndex
	end
	if not GetNumGuildMembers or not GetGuildRosterInfo then
		return nil
	end
	for i = 1, (GetNumGuildMembers()) or 0 do
		local n, _, rankIndex = GetGuildRosterInfo(i)
		if n and D.SameName(n, name) then
			return rankIndex
		end
	end
end

-- Officers and up: the Guild Master, plus the ranks the Guild Master ticked
-- in the settings (by default the rank just below them).
function D.IsOfficerRank(rankIndex)
	if rankIndex == nil then
		return false
	end
	if rankIndex == 0 then
		return true
	end
	local s = D.Links and D.Links() or {}
	local officers = s.officers
	if officers then
		return officers[rankIndex + 1] == true
	end
	return rankIndex == 1
end

function D.IsOfficer(name)
	return D.IsOfficerRank(D.RankIndexOf(name or D.Me()))
end

-- Version ---------------------------------------------------------------------------

local function metadata(field)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(ADDON, field)
	end
	return GetAddOnMetadata and GetAddOnMetadata(ADDON, field)
end
D.VERSION = metadata("Version") or "0"

-- -1, 0 or 1 comparing "1.2.0"-style versions.
function D.CompareVersions(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do
		pa[#pa + 1] = tonumber(n)
	end
	for n in tostring(b):gmatch("%d+") do
		pb[#pb + 1] = tonumber(n)
	end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x < y and -1 or 1
		end
	end
	return 0
end

-- Callbacks ---------------------------------------------------------------------

local listeners = {}

function D.On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end

function D.Fire(event, ...)
	for _, fn in ipairs(listeners[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok and D.debug then
			D.print("error in " .. event .. ": " .. tostring(err))
		end
	end
end

-- Guild addon messages --------------------------------------------------------
-- Messages are tab-separated fields; the first is the message type. They go
-- out through a small queue so a burst (like a sync) stays under the server's
-- addon message limits.

local SEP = "\t"
-- Two queues: live changes (a new order, an accept, the guild's links) always
-- go before bulk catch-up traffic (sync answers), so a big sync never holds
-- up what someone just clicked.
local live, bulk = {}, {}
local tokens, MAX_TOKENS, REFILL = 6, 6, 1.0 -- burst of 6, then 1 per second

function D.Escape(s)
	s = tostring(s or "")
	return (s:gsub("[\t\n\r|]", " "))
end

function D.Pack(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = D.Escape((select(i, ...)))
	end
	return table.concat(parts, SEP)
end

function D.Unpack(msg)
	local out = {}
	for field in (msg .. SEP):gmatch("(.-)" .. SEP) do
		out[#out + 1] = field
	end
	return out
end

-- Returns false if the client says we're sending too fast (modern clients
-- drop the message and report it rather than queueing it).
local function rawSend(item)
	local result
	local channel = item.target and "WHISPER" or "GUILD"
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		result = C_ChatInfo.SendAddonMessage(D.PREFIX, item.msg, channel, item.target)
	elseif SendAddonMessage then
		result = SendAddonMessage(D.PREFIX, item.msg, channel, item.target)
	end
	local codes = Enum and Enum.SendAddonMessageResult
	if type(result) == "number" and codes then
		return result ~= codes.AddonMessageThrottle and result ~= codes.ChannelThrottle and result ~= codes.GeneralError
	end
	return true
end

local function enqueue(q, target, ...)
	if not D.InGuild() then
		return
	end
	local msg = D.Pack(...)
	if #msg > 250 then
		msg = msg:sub(1, 250)
	end
	q[#q + 1] = { msg = msg, target = target }
end

-- A live change: sent as soon as the rate limit allows.
function D.Send(...)
	enqueue(live, nil, ...)
end

-- Catch-up traffic: sent when nothing live is waiting.
function D.SendBulk(...)
	enqueue(bulk, nil, ...)
end

-- To one player (any guild), e.g. asking another guild for its colors.
function D.SendWhisper(target, ...)
	enqueue(live, target, ...)
end

function D.QueueSizes()
	return #live, #bulk
end

local comm = CreateFrame("Frame")
comm:SetScript("OnUpdate", function(_, elapsed)
	tokens = math.min(MAX_TOKENS, tokens + elapsed / REFILL)
	while tokens >= 1 and (#live > 0 or #bulk > 0) do
		tokens = tokens - 1
		local q = #live > 0 and live or bulk
		if rawSend(q[1]) then
			table.remove(q, 1)
		else
			tokens = -1 -- throttled: keep the message and back off a moment
		end
	end
end)

local handlers, whisperHandlers = {}, {}

-- Register a handler for one guild message type: fn(fields, sender)
function D.Handle(kind, fn)
	handlers[kind] = fn
end

-- Register a handler for one whispered message type (from anyone, in any
-- guild): fn(fields, sender)
function D.HandleWhisper(kind, fn)
	whisperHandlers[kind] = fn
end

-- Register events, skipping any this client doesn't have (registering an
-- unknown event is an error, and events differ between Classic and modern
-- clients).
function D.RegisterEvents(frame, ...)
	for i = 1, select("#", ...) do
		pcall(frame.RegisterEvent, frame, (select(i, ...)))
	end
end

D.RegisterEvents(comm, "CHAT_MSG_ADDON", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE")

local lastGuild = nil
local function checkGuild()
	local now = D.GuildKey()
	if now ~= lastGuild then
		lastGuild = now
		D.Fire("GUILD", now ~= nil)
	end
end
D.CheckGuild = checkGuild

-- Joined (or the guild finished loading after login): say hello now if the
-- one sent at login was dropped.
D.On("GUILD", function(member)
	if member and helloNonce then
		D.Send("H", helloNonce)
	end
end)
comm:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
	if event == "ADDON_LOADED" then
		if a1 == ADDON then
			PidgesForeverGuildDB = PidgesForeverGuildDB or {}
			if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
				C_ChatInfo.RegisterAddonMessagePrefix(D.PREFIX)
			end
		end
		D.Fire("ADDON_LOADED", a1)
	elseif event == "PLAYER_LOGIN" then
		helloNonce = tostring(math.random(100000, 999999))
		D.Send("H", helloNonce)
		-- The guild often isn't loaded yet at login (and Send drops messages
		-- until it is), so ask again shortly if nothing came back.
		if C_Timer then
			C_Timer.After(5, function()
				if helloNonce then
					D.Send("H", helloNonce)
				end
			end)
		end
		D.Fire("LOGIN")
		checkGuild()
	elseif event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
		checkGuild()
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, channel, sender = a1, a2, a3, a4
		if prefix ~= D.PREFIX or not sender or not D.InGuild() then
			return
		end
		sender = D.FullName(sender)
		local fields = D.Unpack(msg)
		if channel == "WHISPER" then
			local fn = whisperHandlers[fields[1]]
			if fn then
				pcall(fn, fields, sender)
			end
			return
		elseif channel ~= "GUILD" then
			return
		end
		if fields[1] == "H" and helloNonce and fields[2] == helloNonce then
			helloNonce = nil
			if sender ~= myName then
				learnMyName(sender)
			end
			return
		end
		if sender == D.Me() then
			return
		end
		local fn = handlers[fields[1]]
		if fn then
			local ok, err = pcall(fn, fields, sender)
			if not ok and D.debug then
				D.print("bad message from " .. sender .. ": " .. tostring(err))
			end
		end
	end
end)

-- Guild panel -------------------------------------------------------------------
-- Blizzard_Communities (the guild panel) loads the first time it's opened.
-- D.OnGuildPanel(fn) runs fn once it exists.

local panelCallbacks = {}
local panelReady = false

local function isLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function panelLoaded()
	if panelReady or not CommunitiesFrame then
		return
	end
	panelReady = true
	for _, fn in ipairs(panelCallbacks) do
		local ok, err = pcall(fn)
		if not ok then
			D.print("couldn't add to the guild panel: " .. tostring(err))
		end
	end
end

function D.OnGuildPanel(fn)
	table.insert(panelCallbacks, fn)
end

D.On("ADDON_LOADED", function(name)
	if name == "Blizzard_Communities" or (name == ADDON and isLoaded("Blizzard_Communities")) then
		panelLoaded()
	end
end)

-- /pfg --------------------------------------------------------------------------

local commands, helps = {}, {}

-- D.Command({"logs", "wcl"}, fn, "/pfg logs - ...")
function D.Command(names, fn, help)
	for _, n in ipairs(type(names) == "table" and names or { names }) do
		commands[n] = fn
	end
	if help then
		helps[#helps + 1] = help
	end
end

SLASH_PIDGESFOREVERGUILD1 = "/pfg"
SLASH_PIDGESFOREVERGUILD2 = "/pidgesforever"
SlashCmdList.PIDGESFOREVERGUILD = function(msg)
	if not D.InGuild() then
		D.print("join a guild to use this addon.")
		return
	end
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local fn = commands[cmd:lower()]
	if fn then
		fn(rest)
	else
		for _, line in ipairs(helps) do
			D.print(line)
		end
	end
end
