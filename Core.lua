-- Dreamscape: shared setup. Saved data, names, guild addon messages and the
-- guild panel loader that the other files build on.

local ADDON, ns = ...

Dreamscape = Dreamscape or {}
local D = Dreamscape
ns.D = D

D.PREFIX = "Dreamscape"
D.GUILD_NAME = "Dreamscape" -- every feature is for members of this guild only
D.COLOR = "|cff9b7bff"

function D.print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(D.COLOR .. "Dreamscape|r: " .. msg)
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
		local saved = DreamscapeDB and DreamscapeDB.me and DreamscapeDB.me[D.MyGUID() or ""]
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
	if guid and DreamscapeDB then
		DreamscapeDB.me = DreamscapeDB.me or {}
		DreamscapeDB.me[guid] = sender
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
-- DreamscapeDB.guilds[guild] = { orders = { [id] = order }, profs = { [name] = entry } }

-- Are we in <Dreamscape>? Nothing in the addon shows or talks otherwise.
-- The guild name can take a few seconds to arrive after login, so until it
-- does this is false and the "GUILD" event fires once it changes.
function D.InDreamscape()
	if not IsInGuild() then
		return false
	end
	return GetGuildInfo("player") == D.GUILD_NAME
end

function D.GuildKey()
	return D.InDreamscape() and D.GUILD_NAME or nil
end

function D.Data()
	local key = D.GuildKey()
	if not key then
		return nil
	end
	DreamscapeDB.guilds = DreamscapeDB.guilds or {}
	local g = DreamscapeDB.guilds[key]
	if not g then
		g = { orders = {}, profs = {} }
		DreamscapeDB.guilds[key] = g
	end
	return g
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
local queue = {}
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

local function rawSend(msg)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(D.PREFIX, msg, "GUILD")
	elseif SendAddonMessage then
		SendAddonMessage(D.PREFIX, msg, "GUILD")
	end
end

function D.Send(...)
	if not D.InDreamscape() then
		return
	end
	local msg = D.Pack(...)
	if #msg > 250 then
		msg = msg:sub(1, 250)
	end
	queue[#queue + 1] = msg
end

local comm = CreateFrame("Frame")
comm:SetScript("OnUpdate", function(_, elapsed)
	tokens = math.min(MAX_TOKENS, tokens + elapsed / REFILL)
	while tokens >= 1 and #queue > 0 do
		tokens = tokens - 1
		rawSend(table.remove(queue, 1))
	end
end)

local handlers = {}

-- Register a handler for one message type: fn(fields, sender)
function D.Handle(kind, fn)
	handlers[kind] = fn
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

local wasMember = false
local function checkGuild()
	local now = D.InDreamscape()
	if now ~= wasMember then
		wasMember = now
		D.Fire("GUILD", now)
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
			DreamscapeDB = DreamscapeDB or {}
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
		if prefix ~= D.PREFIX or channel ~= "GUILD" or not sender or not D.InDreamscape() then
			return
		end
		sender = D.FullName(sender)
		local fields = D.Unpack(msg)
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

-- /ds ---------------------------------------------------------------------------

local commands, helps = {}, {}

-- D.Command({"logs", "wcl"}, fn, "/ds logs - ...")
function D.Command(names, fn, help)
	for _, n in ipairs(type(names) == "table" and names or { names }) do
		commands[n] = fn
	end
	if help then
		helps[#helps + 1] = help
	end
end

SLASH_DREAMSCAPE1 = "/ds"
SLASH_DREAMSCAPE2 = "/dreamscape"
SlashCmdList.DREAMSCAPE = function(msg)
	if not D.InDreamscape() then
		D.print("this addon is only for members of <" .. D.GUILD_NAME .. ">.")
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
