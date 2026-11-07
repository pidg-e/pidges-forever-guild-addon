-- Pidge's Forever Guild: the guild's own links (Discord invite, Warcraft Logs
-- page), set by the Guild Master under Guild Control > Pidge's Forever
-- Settings.
--
-- The links are kept in the guild's Info text, one line each:
--
--   Discord: discord.gg/abc123
--   Warcraft Logs: forever.warcraftlogs.com/guild/id/12345
--
-- Every member's client already receives that text, whether or not the Guild
-- Master is online, and only ranks allowed to edit it can change it, so
-- nobody can spoof the links. Members without the addon still see readable
-- links in the Info box.
--
-- WoW only lets its own Guild Information editor change the Info text, so
-- Save fills the links into that editor and the Guild Master clicks Accept.
-- Once the new text comes back, a guild addon message tells everyone online
-- to fetch it right away.

local ADDON, ns = ...
local D = ns.D

local MAX_INFO = 500 -- the server keeps at most this many characters of Info text

local function trim(s)
	return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Links: parsing and writing ------------------------------------------------------

-- What the Guild Master typed -> "https://discord.gg/code", "" for nothing,
-- or nil if it isn't an invite. A bare code is accepted.
function D.NormalizeDiscord(text)
	text = trim(text):gsub("^<", ""):gsub(">$", ""):gsub("^%a+://", ""):gsub("^www%.", "")
	if text == "" then
		return ""
	end
	local code = text:match("^discord%.gg/([%w%-_]+)/?$")
		or text:match("^discord%.com/invite/([%w%-_]+)/?$")
		or text:match("^discordapp%.com/invite/([%w%-_]+)/?$")
		or text:match("^([%w%-_]+)$")
	return code and ("https://discord.gg/" .. code) or nil
end

-- A Warcraft Logs guild page -> its https link, "" or nil. A bare number is
-- taken as a WoW Forever guild id.
function D.NormalizeLogs(text)
	text = trim(text):gsub("^<", ""):gsub(">$", ""):gsub("^%a+://", "")
	if text == "" then
		return ""
	end
	if text:match("^%d+$") then
		return "https://forever.warcraftlogs.com/guild/id/" .. text
	end
	local host, path = text:match("^([%w%.%-]*warcraftlogs%.com)(/guild/%S+)$")
	return host and ("https://" .. host .. path) or nil
end

-- Our lines in the Info text. Only lines that hold a real link count, so a
-- line like "Discord: ask an officer" is left alone.
local function parseLine(line)
	local d = line:match("^%s*[Dd][Ii][Ss][Cc][Oo][Rr][Dd]%s*:%s*(%S+)%s*$")
	if d and d:find("discord", 1, true) then
		local url = D.NormalizeDiscord(d)
		if url and url ~= "" then
			return "discord", url
		end
	end
	local l = line:match("^%s*[Ww]arcraft%s*[Ll]ogs%s*:%s*(%S+)%s*$")
	if l and l:find("warcraftlogs", 1, true) then
		local url = D.NormalizeLogs(l)
		if url and url ~= "" then
			return "logs", url
		end
	end
end

local function lines(text)
	local out = {}
	for line in ((text or ""):gsub("\r\n?", "\n") .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	return out
end

-- Guild Info text -> { discord = url, logs = url } (either may be missing).
function D.ParseLinks(text)
	local links = {}
	for _, line in ipairs(lines(text)) do
		local kind, url = parseLine(line)
		if kind and not links[kind] then
			links[kind] = url
		end
	end
	return links
end

local function bare(url)
	return (url:gsub("^https://", ""))
end

-- The Info text with our lines replaced by these links ("" drops one).
function D.BuildInfoText(old, discord, logs)
	local keep = {}
	for _, line in ipairs(lines(old)) do
		if not parseLine(line) then
			keep[#keep + 1] = line
		end
	end
	while #keep > 0 and keep[#keep]:match("^%s*$") do
		keep[#keep] = nil
	end
	local add = {}
	if discord and discord ~= "" then
		add[#add + 1] = "Discord: " .. bare(discord)
	end
	if logs and logs ~= "" then
		add[#add + 1] = "Warcraft Logs: " .. bare(logs)
	end
	if #add > 0 then
		if #keep > 0 then
			keep[#keep + 1] = ""
		end
		for _, line in ipairs(add) do
			keep[#keep + 1] = line
		end
	end
	return table.concat(keep, "\n")
end

-- The current guild's links ---------------------------------------------------------
-- Kept in saved data too, so the buttons are right straight after login,
-- before the Info text arrives.

function D.Links()
	local data = D.Data()
	return data and data.links or {}
end

-- The guild Info text. Modern clients only have C_GuildInfo.GetInfoText and
-- SetInfoText; older ones have the global functions.
local function getInfoText()
	if C_GuildInfo and C_GuildInfo.GetInfoText then
		return C_GuildInfo.GetInfoText() or ""
	end
	if GetGuildInfoText then
		return GetGuildInfoText() or ""
	end
end

local function rosterLoaded()
	return (GetNumGuildMembers and GetNumGuildMembers() or 0) > 0
end

-- Links the Guild Master saved that aren't in the Info text yet. WoW only
-- lets its own Guild Information editor change that text (an addon calling
-- SetInfoText is blocked), so Save keeps them here and fills them into that
-- editor when it opens; the Guild Master then clicks Accept.
local pendingEdit

function D.PendingLinks()
	return pendingEdit
end

local function setLinks(links)
	local data = D.Data()
	if not data then
		return
	end
	local old = data.links or {}
	if old.discord ~= links.discord or old.logs ~= links.logs then
		data.links = { discord = links.discord, logs = links.logs }
		D.Fire("LINKS")
	end
end

local function requestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- Read the links from the Info text, once it has arrived. The text comes with
-- the roster, so an empty text before the roster is loaded means "not here
-- yet", not "no links".
function D.ReadGuildLinks()
	if not D.InGuild() then
		return
	end
	local text = getInfoText()
	if not text or (text == "" and not rosterLoaded()) then
		return
	end
	local links = D.ParseLinks(text)
	setLinks(links)
	if pendingEdit and links.discord == pendingEdit.discord and links.logs == pendingEdit.logs then
		pendingEdit = nil
		D.Send("L")
		D.print("your guild's links are saved. Guildmates with the addon will see the new buttons.")
		D.Fire("LINKS_SAVED")
	end
end

local watcher = CreateFrame("Frame")
D.RegisterEvents(watcher, "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE")
watcher:SetScript("OnEvent", function()
	D.ReadGuildLinks()
end)

D.On("GUILD", function(member)
	if member then
		D.ReadGuildLinks()
		requestRoster()
	else
		D.Fire("LINKS")
	end
end)

-- "L": the Guild Master changed the links; fetch the new Info text.
D.Handle("L", function()
	if C_Timer then
		C_Timer.After(2, requestRoster)
	else
		requestRoster()
	end
end)

-- Save new links (Guild Master only). Returns true and "saved" when the Info
-- text already has them, true and "edit" when they wait for the Guild
-- Information editor, or false and why not.
function D.SaveLinks(discordText, logsText)
	if not D.InGuild() or not IsGuildLeader() then
		return false, "Only the Guild Master can change these."
	end
	local discord = D.NormalizeDiscord(discordText)
	if not discord then
		return false, "That doesn't look like a Discord invite (discord.gg/...)."
	end
	local logs = D.NormalizeLogs(logsText)
	if not logs then
		return false, "That doesn't look like a Warcraft Logs guild page (warcraftlogs.com/guild/...)."
	end
	local old = getInfoText()
	-- Never write over an Info text we haven't seen yet.
	if not old or (old == "" and not rosterLoaded()) then
		requestRoster()
		return false, "The guild's Info text hasn't loaded yet. Try again in a few seconds."
	end
	local new = D.BuildInfoText(old, discord, logs)
	if #new > MAX_INFO then
		return false, ("The guild's Info text is too long to add these (%d of %d characters). Shorten it under Guild Information first."):format(#new, MAX_INFO)
	end
	if new == old then
		pendingEdit = nil
		return true, "saved"
	end
	pendingEdit = { discord = discord ~= "" and discord or nil, logs = logs ~= "" and logs or nil }
	D.print("almost done: open the guild's Info tab, click Edit next to Guild Information, then Accept. Your links are filled in for you.")
	return true, "edit"
end

-- Blizzard's Guild Information editor: when the Guild Master opens it with
-- links waiting, put them in. Only the edit box's text is touched, so
-- Blizzard's Accept button still saves it as normal.
local editorHint

local function editorBox()
	local f = CommunitiesGuildTextEditFrame
	local c = f and f.Container
	local sf = c and c.ScrollFrame
	return sf and sf.EditBox
end

local function onEditorOpened(frame, editType)
	if editorHint then
		editorHint:Hide()
	end
	local box = editorBox()
	if editType ~= "info" or not pendingEdit or not box or not IsGuildLeader() then
		return
	end
	box:SetText(D.BuildInfoText(box:GetText() or "", pendingEdit.discord or "", pendingEdit.logs or ""))
	box:SetCursorPosition(0)
	if not editorHint then
		editorHint = CreateFrame("Frame", "PFGInfoEditHint", frame, "BackdropTemplate")
		editorHint:SetSize(300, 40)
		editorHint:SetPoint("BOTTOM", frame, "TOP", 0, -4)
		if editorHint.SetBackdrop then
			editorHint:SetBackdrop({
				bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 12,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			editorHint:SetBackdropColor(0, 0, 0, 0.9)
		end
		local text = editorHint:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
		text:SetWidth(280)
		text:SetText(D.COLOR .. "Pidge's Forever|r added your links at the end. Click Accept to save them.")
		frame:HookScript("OnHide", function()
			editorHint:Hide()
		end)
	end
	editorHint:Show()
end

D.OnGuildPanel(function()
	if CommunitiesGuildTextEditFrame_SetType then
		hooksecurefunc("CommunitiesGuildTextEditFrame_SetType", onEditorOpened)
	end
end)

-- Guild Control > Pidge's Forever Settings ---------------------------------------
-- An extra entry in the Guild Control dropdown, for the Guild Master only.

local TAB = "PidgesForever"
local BLIZZARD_PAGES = {
	"GuildControlUIRankOrderFrame",
	"GuildControlUIRankSettingsFrame",
	"GuildControlUIRankBankFrame",
	"GuildControlUIRankDiscordFrame",
}
local panel

local function makeBox(parent, label, hint, anchor, y)
	local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
	text:SetText(label)

	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(280, 22)
	box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 6, -4)
	box:SetAutoFocus(false)
	box:SetMaxLetters(200)
	box:SetFontObject("ChatFontNormal")

	local note = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -3)
	note:SetWidth(290)
	note:SetJustifyH("LEFT")
	note:SetText(hint)
	box.note = note
	return box
end

local function createPanel()
	local gc = GuildControlUI
	local p = CreateFrame("Frame", "PFGGuildControlFrame", gc)
	local hbar = _G.GuildControlUIHbar
	if hbar then
		p:SetPoint("TOPLEFT", hbar, "BOTTOMLEFT", 5, -3)
	else
		p:SetPoint("TOPLEFT", gc, "TOPLEFT", 17, -60)
	end
	p:SetPoint("BOTTOMRIGHT", gc, "BOTTOMRIGHT", -12, 12)
	p:Hide()

	local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 10, -12)
	title:SetText("Pidge's Forever Settings")

	local intro = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetWidth(290)
	intro:SetJustifyH("LEFT")
	intro:SetText("These links appear as buttons on the guild Info tab for every member with the addon. Leave a box empty to hide its button.")

	p.discord = makeBox(p, "Discord invite", "An invite link (discord.gg/...) or just its code.", intro, -16)
	p.logs = makeBox(p, "Warcraft Logs guild page", "The guild's page link (warcraftlogs.com/guild/...).", p.discord.note, -14)
	p.discord.next, p.logs.next = p.logs, p.discord

	local where = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	where:SetPoint("TOPLEFT", p.logs.note, "BOTTOMLEFT", 0, -16)
	where:SetWidth(290)
	where:SetJustifyH("LEFT")
	where:SetText("Saved as two lines at the end of the guild's Info text, so members without the addon can read them too. After Save, confirm with Accept in WoW's Guild Information window.")

	p.status = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -12)
	p.status:SetWidth(290)
	p.status:SetJustifyH("LEFT")

	local save = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	save:SetSize(110, 22)
	save:SetPoint("BOTTOMRIGHT", -6, 6)
	save:SetText(SAVE or "Save")
	p.save = save

	local function fill()
		local links = pendingEdit or D.Links()
		p.discord:SetText(links.discord or "")
		p.logs:SetText(links.logs or "")
		p.discord:SetCursorPosition(0)
		p.logs:SetCursorPosition(0)
	end
	p.fill = fill

	local function doSave()
		p.discord:ClearFocus()
		p.logs:ClearFocus()
		local ok, how = D.SaveLinks(p.discord:GetText(), p.logs:GetText())
		if ok and how == "edit" then
			fill()
			p.status:SetTextColor(1, 0.82, 0)
			p.status:SetText("Almost done. WoW only lets its own window change the Info text: open the guild's Info tab, click Edit next to Guild Information, then Accept. Your links are already filled in.")
		elseif ok then
			fill()
			p.status:SetTextColor(0.3, 1, 0.3)
			p.status:SetText("Saved. Guildmates with the addon will see these buttons.")
		else
			p.status:SetTextColor(1, 0.3, 0.3)
			p.status:SetText(how)
		end
	end
	save:SetScript("OnClick", doSave)

	for _, box in ipairs({ p.discord, p.logs }) do
		box:SetScript("OnEnterPressed", doSave)
		box:SetScript("OnEscapePressed", box.ClearFocus)
		box:SetScript("OnTabPressed", function(self)
			self.next:SetFocus()
		end)
		box:SetScript("OnTextChanged", function(_, userInput)
			if userInput then
				p.status:SetText("")
			end
		end)
	end

	p:SetScript("OnShow", function()
		p.status:SetText("")
		fill()
	end)
	-- Blizzard's own entries don't know about this page, so step aside as
	-- soon as one of them is picked.
	p:SetScript("OnUpdate", function(self)
		if GuildControlUI.selectedTab ~= TAB or not IsGuildLeader() then
			self:Hide()
		end
	end)
	return p
end

local function isSelected()
	return GuildControlUI and GuildControlUI.selectedTab == TAB
end

function D.ShowGuildControlSettings(fromMenu)
	local gc = GuildControlUI
	if not gc then
		return
	end
	gc.selectedTab = TAB
	gc.numSkipUpdates = 0
	if StaticPopup_Hide then
		StaticPopup_Hide("CONFIRM_RANK_AUTHENTICATOR_REMOVE")
	end
	for _, name in ipairs(BLIZZARD_PAGES) do
		local f = _G[name]
		if f then
			f:Hide()
		end
	end
	panel = panel or createPanel()
	gc.currFrame = panel
	gc.rankUpdate = function() end -- Blizzard calls this on rank changes
	panel:Show()
	-- Picked from the dropdown, it updates its own text; otherwise (/pfg
	-- settings) rebuild it so it shows our entry's name.
	if not fromMenu and gc.dropdown and gc.dropdown.GenerateMenu then
		gc.dropdown:GenerateMenu()
	end
end

if Menu and Menu.ModifyMenu then
	Menu.ModifyMenu("MENU_GUILD_PERMISSIONS", function(_, rootDescription)
		if D.InGuild() and IsGuildLeader() then
			rootDescription:CreateRadio("Pidge's Forever Settings", isSelected, D.ShowGuildControlSettings, TAB)
		end
	end)
end

D.On("LINKS_SAVED", function()
	if panel and panel:IsShown() then
		panel.status:SetTextColor(0.3, 1, 0.3)
		panel.status:SetText("Saved. Guildmates with the addon will see these buttons.")
	end
end)

D.On("LINKS", function()
	if panel and panel:IsShown() and not panel.discord:HasFocus() and not panel.logs:HasFocus() then
		panel.fill()
	end
end)

local function loadAddOn(name)
	if C_AddOns and C_AddOns.LoadAddOn then
		return C_AddOns.LoadAddOn(name)
	end
	return LoadAddOn and LoadAddOn(name)
end

D.Command("settings", function()
	if not IsGuildLeader() then
		D.print("only the Guild Master can change the guild's links.")
		return
	end
	if not GuildControlUI then
		loadAddOn("Blizzard_GuildControlUI")
	end
	if GuildControlUI then
		GuildControlUI:Show()
		D.ShowGuildControlSettings()
	end
end, "/pfg settings - (Guild Master) set the guild's Discord and Warcraft Logs links")
