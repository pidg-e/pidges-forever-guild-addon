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

-- Colors are "rrggbb" (nil = default white). ranks[i] / officers[i] are for
-- rank index i - 1 (1 = Guild Master).
local function encodeRanks(ranks)
	local out = {}
	for i = 1, 10 do
		out[i] = ranks and ranks[i] or ""
	end
	return (table.concat(out, ","):gsub(",+$", ""))
end

local function decodeRanks(s)
	local ranks, i = {}, 0
	for v in ((s or "") .. ","):gmatch("(.-),") do
		i = i + 1
		if v:match("^%x%x%x%x%x%x$") then
			ranks[i] = v:lower()
		end
	end
	return ranks
end

local function encodeOfficers(officers)
	if not officers then
		return ""
	end
	local out = {}
	for i = 1, 10 do
		out[i] = (i == 1 or officers[i]) and "1" or "0"
	end
	return (table.concat(out):gsub("0+$", ""))
end

local function decodeOfficers(s)
	if not s or s == "" then
		return nil
	end
	local officers = {}
	for i = 1, #s do
		officers[i] = s:sub(i, i) == "1"
	end
	officers[1] = true
	return officers
end

local function validColor(c)
	return type(c) == "string" and c:match("^%x%x%x%x%x%x$") and c:lower() or nil
end
D.EncodeRanks, D.DecodeRanks, D.EncodeOfficers, D.DecodeOfficers = encodeRanks, decodeRanks, encodeOfficers, decodeOfficers

-- Everything but the time, to tell whether anything changed.
local function signature(l)
	return table.concat({ l.discord or "", l.logs or "", l.color or "", encodeRanks(l.ranks), encodeOfficers(l.officers) }, "|")
end

local function store(links)
	local data = D.Data()
	if not data then
		return
	end
	local old = data.links or {}
	data.links = links
	if signature(old) ~= signature(links) then
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
		D.Send("LS", l.t, l.discord or "", l.logs or "", l.gm and "1" or "0", l.color or "", encodeRanks(l.ranks), encodeOfficers(l.officers))
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
	local new = {
		discord = opt(D.NormalizeDiscord(f[3] or "") or ""),
		logs = opt(D.NormalizeLogs(f[4] or "") or ""),
		t = t,
		color = validColor(f[6]),
		ranks = decodeRanks(f[7]),
		officers = decodeOfficers(f[8]),
	}
	local have = D.Links()
	if D.IsGuildMaster(sender) then
		if not have.gm or have.t ~= t or signature(have) ~= signature(new) then
			new.gm = true
			store(new)
		end
	elseif not have.gm and (not have.t or t > have.t) then
		-- Passed on by a guildmate: good enough until the Guild Master says otherwise.
		new.gm = false
		store(new)
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

-- Save new settings (Guild Master only). extra = { color, ranks, officers }
-- (left out: keep what we have). Returns true, or false and why not.
function D.SaveLinks(discordText, logsText, extra)
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
	local have = D.Links()
	extra = extra or have
	store({
		discord = opt(discord),
		logs = opt(logs),
		t = D.Now(),
		gm = true,
		color = validColor(extra.color),
		ranks = extra.ranks,
		officers = extra.officers,
	})
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

local function hexToRGB(hex)
	hex = hex or "ffffff"
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function rgbToHex(r, g, b)
	local function c(v)
		return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
	end
	return ("%02x%02x%02x"):format(c(r), c(g), c(b))
end
D.HexToRGB, D.RGBToHex = hexToRGB, rgbToHex

-- Open WoW's color picker on `hex`; onChange(hex) as the color changes (and
-- with the old color if cancelled).
local function pickColor(hex, onChange)
	local cp = ColorPickerFrame
	if not cp then
		return
	end
	local r, g, b = hexToRGB(hex)
	local function apply()
		onChange(rgbToHex(cp:GetColorRGB()))
	end
	local function cancel()
		onChange(hex)
	end
	if cp.SetupColorPickerAndShow then
		cp:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, swatchFunc = apply, cancelFunc = cancel })
	else
		cp.func, cp.cancelFunc, cp.hasOpacity = apply, cancel, false
		cp.previousValues = { r, g, b }
		cp:SetColorRGB(r, g, b)
		cp:Hide()
		cp:Show()
	end
end
D._pickColor = pickColor

local function makeSwatch(parent, onClick)
	local sw = CreateFrame("Button", nil, parent)
	sw:SetSize(16, 16)
	sw.border = sw:CreateTexture(nil, "BACKGROUND")
	sw.border:SetAllPoints()
	sw.border:SetColorTexture(0.6, 0.6, 0.6, 1)
	sw.fill = sw:CreateTexture(nil, "ARTWORK")
	sw.fill:SetPoint("TOPLEFT", 1, -1)
	sw.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	sw:SetScript("OnClick", onClick)
	function sw:SetHex(hex)
		self.fill:SetColorTexture(hexToRGB(hex))
	end
	return sw
end

local function guildName()
	return (GetGuildInfo("player")) or "Guild"
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
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("Pidge's Forever Settings")

	-- Two pages: Links, and Colors & Ranks.
	p.pages, p.tabs = {}, {}
	local function showPage(i)
		for j, page in ipairs(p.pages) do
			page:SetShown(i == j)
			p.tabs[j]:SetEnabled(i ~= j)
		end
		p.page = i
		if p.where then
			p.where:SetText(i == 1 and "Sent to guildmates with the addon when you save and whenever you log in."
				or "Right-click a color to reset it to white. Officers can remove anyone's crafting orders.")
		end
	end
	p.showPage = showPage
	for i, label in ipairs({ "Links", "Colors & Ranks" }) do
		local t = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		t:SetSize(i == 1 and 70 or 120, 20)
		if i == 1 then
			t:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
		else
			t:SetPoint("LEFT", p.tabs[1], "RIGHT", 4, 0)
		end
		t:SetText(label)
		t:SetScript("OnClick", function()
			showPage(i)
		end)
		p.tabs[i] = t
		local page = CreateFrame("Frame", nil, p)
		page:SetPoint("TOPLEFT", 0, -62)
		page:SetPoint("BOTTOMRIGHT", 0, 60)
		p.pages[i] = page
	end

	-- Links page.
	local links = p.pages[1]
	local intro = links:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", 10, 0)
	intro:SetWidth(290)
	intro:SetJustifyH("LEFT")
	intro:SetText("These links appear as buttons on the guild Info tab for every member with the addon. Leave a box empty to hide its button.")
	p.discord = makeBox(links, "Discord invite", "An invite link (discord.gg/...) or just its code.", intro, -12)
	p.logs = makeBox(links, "Warcraft Logs guild page", "The guild's page link (warcraftlogs.com/guild/...).", p.discord.note, -10)
	p.discord.next, p.logs.next = p.logs, p.discord

	-- Colors & Ranks page.
	local colors = p.pages[2]
	local gLabel = colors:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	gLabel:SetPoint("TOPLEFT", 10, 0)
	gLabel:SetText("Guild name")
	p.guildSwatch = makeSwatch(colors, function(_, button)
		if button == "RightButton" then
			p.work.color = nil
			p.refreshColors()
		else
			pickColor(p.work.color, function(hex)
				p.work.color = hex
				p.refreshColors()
			end)
		end
	end)
	p.guildSwatch:SetPoint("TOPLEFT", gLabel, "BOTTOMLEFT", 0, -6)
	p.guildPreview = colors:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	p.guildPreview:SetPoint("LEFT", p.guildSwatch, "RIGHT", 8, 0)

	local rLabel = colors:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	rLabel:SetPoint("TOPLEFT", p.guildSwatch, "BOTTOMLEFT", 0, -10)
	rLabel:SetText("Ranks")
	local oLabel = colors:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	oLabel:SetText("Officer")

	p.rankRows = {}
	for i = 1, 10 do
		local row = CreateFrame("Frame", nil, colors)
		row:SetSize(290, 18)
		row:SetPoint("TOPLEFT", rLabel, "BOTTOMLEFT", 0, -4 - (i - 1) * 18)
		row.swatch = makeSwatch(row, function(_, button)
			if button == "RightButton" then
				p.work.ranks[i] = nil
				p.refreshColors()
			else
				pickColor(p.work.ranks[i], function(hex)
					p.work.ranks[i] = hex
					p.refreshColors()
				end)
			end
		end)
		row.swatch:SetPoint("LEFT", 0, 0)
		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row.swatch, "RIGHT", 8, 0)
		row.officer = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.officer:SetSize(18, 18)
		row.officer:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		row.officer:SetScript("OnClick", function(self)
			p.work.officers[i] = self:GetChecked() and true or false
			p.status:SetText("")
		end)
		p.rankRows[i] = row
	end
	oLabel:ClearAllPoints()
	oLabel:SetPoint("BOTTOMRIGHT", p.rankRows[1], "TOPRIGHT", 0, 2)

	function p.refreshColors()
		local w = p.work
		p.guildSwatch:SetHex(w.color)
		p.guildPreview:SetText("|cff" .. (w.color or "ffffff") .. "<" .. guildName() .. ">|r")
		local n = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
		for i, row in ipairs(p.rankRows) do
			if i <= n then
				row.swatch:SetHex(w.ranks[i])
				local rankName = GuildControlGetRankName and GuildControlGetRankName(i) or ("Rank " .. i)
				row.name:SetText("|cff" .. (w.ranks[i] or "ffffff") .. rankName .. "|r")
				row.officer:SetChecked(i == 1 or w.officers[i] == true)
				row.officer:SetEnabled(i ~= 1)
				row:Show()
			else
				row:Hide()
			end
		end
		p.status:SetText("")
	end

	local where = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	where:SetPoint("BOTTOMLEFT", 10, 34)
	where:SetWidth(290)
	where:SetJustifyH("LEFT")
	p.where = where

	p.status = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	p.status:SetPoint("BOTTOMLEFT", 10, 10)
	p.status:SetPoint("RIGHT", -124, 0)
	p.status:SetJustifyH("LEFT")

	local save = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	save:SetSize(110, 22)
	save:SetPoint("BOTTOMRIGHT", -6, 6)
	save:SetText(SAVE or "Save")
	p.save = save

	local function fill()
		local l = D.Links()
		p.discord:SetText(l.discord or "")
		p.logs:SetText(l.logs or "")
		p.discord:SetCursorPosition(0)
		p.logs:SetCursorPosition(0)
		local ranks, officers = {}, {}
		for i = 1, 10 do
			ranks[i] = l.ranks and l.ranks[i]
			if l.officers then
				officers[i] = l.officers[i] == true
			else
				officers[i] = i <= 2
			end
		end
		p.work = { color = l.color, ranks = ranks, officers = officers }
		p.refreshColors()
	end
	p.fill = fill

	local function doSave()
		p.discord:ClearFocus()
		p.logs:ClearFocus()
		local ok, err = D.SaveLinks(p.discord:GetText(), p.logs:GetText(), p.work)
		if ok then
			fill()
			p.status:SetTextColor(0.3, 1, 0.3)
			p.status:SetText("Saved and sent to the guild.")
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
		fill()
		p.status:SetText("")
		showPage(p.page or 1)
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
	-- Don't throw away what the Guild Master is in the middle of editing.
	if panel and panel:IsShown() and not panel.discord:HasFocus() and not panel.logs:HasFocus() and not (ColorPickerFrame and ColorPickerFrame:IsShown()) then
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
end, "/pfg settings - (Guild Master) the guild's links, colors and officer ranks")
