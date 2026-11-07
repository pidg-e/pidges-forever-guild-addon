-- Pidge's Forever Guild: the guild's own links (Discord invite, Warcraft Logs
-- page), set by the Guild Master under Guild Control > Pidge's Forever
-- Settings.
--
-- WoW doesn't let addons change the guild's Info text (not even by filling
-- in Blizzard's own editor), so the links travel as guild addon messages:
--
-- * The Guild Master's addon sends them on Save, when they log in, and when
--   anyone asks ("LQ").
-- * Everyone keeps a copy in their saved data, so the buttons show straight
--   after login, and answers "LQ" too, so members who log in while the Guild
--   Master is offline still get them.
-- * Links straight from the Guild Master always win. A copy passed on by
--   someone else is only taken while we have nothing from the Guild Master
--   yet, so a member can't overrule the Guild Master.

local ADDON, ns = ...
local D = ns.D

local function trim(s)
	return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Checking links ------------------------------------------------------------------

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

-- The current guild's links ---------------------------------------------------------
-- data.links = { discord = url?, logs = url?, t = time set, gm = true if it
-- came from the Guild Master }

function D.Links()
	local data = D.Data()
	return data and data.links or {}
end

local function store(links)
	local data = D.Data()
	if not data then
		return
	end
	local old = data.links or {}
	data.links = links
	if old.discord ~= links.discord or old.logs ~= links.logs then
		D.Fire("LINKS")
	end
end

local function opt(s)
	return s ~= "" and s or nil
end

-- Is this sender ("Name-Realm") the Guild Master? Read from the roster
-- (rank 0); names are compared without realm and case.
local function plain(name)
	return (D.Short(name or "")):lower()
end

function D.IsGuildMaster(sender)
	if not GetNumGuildMembers or not GetGuildRosterInfo then
		return false
	end
	local want = plain(sender)
	for i = 1, (GetNumGuildMembers()) or 0 do
		local name, _, rankIndex = GetGuildRosterInfo(i)
		if rankIndex == 0 then
			return plain(name) == want
		end
	end
	return false
end

local function sendLinks()
	local l = D.Links()
	if l.t then
		D.Send("LS", l.t, l.discord or "", l.logs or "", l.gm and "1" or "0")
	end
end

local function requestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

-- "LS" t discord logs fromGM: the guild's links.
local answered = false
D.Handle("LS", function(f, sender)
	answered = true
	local t = tonumber(f[2])
	if not t then
		return
	end
	local discord, logs = opt(D.NormalizeDiscord(f[3] or "") or ""), opt(D.NormalizeLogs(f[4] or "") or "")
	local have = D.Links()
	if D.IsGuildMaster(sender) then
		if not have.gm or have.t ~= t or have.discord ~= discord or have.logs ~= logs then
			store({ discord = discord, logs = logs, t = t, gm = true })
		end
	elseif not have.gm and (not have.t or t > have.t) then
		-- Passed on by a guildmate: good enough until the Guild Master says otherwise.
		store({ discord = discord, logs = logs, t = t, gm = false })
	end
end)

-- "LQ": someone wants the links. The Guild Master answers at once; others
-- wait a moment and stay quiet if someone else answered first.
D.Handle("LQ", function()
	if not D.Links().t then
		return
	end
	if IsGuildLeader() then
		sendLinks()
	elseif C_Timer then
		answered = false
		C_Timer.After(2 + math.random() * 4, function()
			if not answered then
				sendLinks()
			end
		end)
	end
end)

D.On("GUILD", function(member)
	if not member then
		D.Fire("LINKS")
		return
	end
	requestRoster()
	if C_Timer then
		C_Timer.After(10, function()
			if not D.InGuild() then
				return
			end
			if IsGuildLeader() then
				local l = D.Links()
				if l.t and not l.gm then
					-- We're the Guild Master now: what we have is ours to stand by.
					l.gm = true
				end
				sendLinks()
			else
				D.Send("LQ")
			end
		end)
	end
end)

-- Save new links (Guild Master only). Returns true, or false and why not.
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
	store({ discord = opt(discord), logs = opt(logs), t = D.Now(), gm = true })
	sendLinks()
	return true
end

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
	where:SetText("Sent to guildmates with the addon when you save, and again whenever you log in. Members who were offline get them from you or from any guildmate who has them.")

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
		local links = D.Links()
		p.discord:SetText(links.discord or "")
		p.logs:SetText(links.logs or "")
		p.discord:SetCursorPosition(0)
		p.logs:SetCursorPosition(0)
	end
	p.fill = fill

	local function doSave()
		p.discord:ClearFocus()
		p.logs:ClearFocus()
		local ok, err = D.SaveLinks(p.discord:GetText(), p.logs:GetText())
		if ok then
			fill()
			p.status:SetTextColor(0.3, 1, 0.3)
			p.status:SetText("Saved. Guildmates with the addon will see these buttons.")
		else
			p.status:SetTextColor(1, 0.3, 0.3)
			p.status:SetText(err)
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
