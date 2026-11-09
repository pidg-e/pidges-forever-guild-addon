-- Pidge's Forever Guild: link buttons on the guild panel's Info tab, level
-- with the "Info" title above the Message of the Day. The addon's own
-- (CurseForge) button is always there; the guild's Discord and Warcraft Logs
-- buttons appear to its right once the Guild Master has set them (see
-- Settings.lua), pushing it to the left. WoW can't open web pages, so
-- clicking one shows its link ready to copy (Ctrl+C) and paste into a browser.

local ADDON, ns = ...
local D = ns.D

local ICON_SIZE = 22
local GAP = 4
local HINT = "Press Ctrl+C to copy, then paste it in your browser."

-- Right to left, starting at the right edge of the MOTD box. A link with a
-- "setting" only shows once the guild has one (D.Links()[setting]).
D.LINKS = {
	{
		key = "Discord",
		title = "Discord",
		tooltip = "Discord",
		setting = "discord",
		icon = D.MEDIA .. "discord",
		hint = HINT,
	},
	{
		key = "Logs",
		title = "Warcraft Logs",
		tooltip = "Warcraft Logs",
		setting = "logs",
		icon = D.MEDIA .. "logs",
		hint = HINT,
	},
	{
		key = "CurseForge",
		title = D.TITLE,
		tooltip = D.TITLE .. " on CurseForge",
		url = "https://www.curseforge.com/wow/addons/pidges-forever-guild-addon",
		icon = D.MEDIA .. "curseforge",
		hint = HINT,
	},
}

-- The link's address right now, or nil if the guild hasn't set it.
function D.LinkURL(link)
	if link.setting then
		return D.Links()[link.setting]
	end
	return link.url
end

-- The link popup -------------------------------------------------------------

local popup

local function createPopup()
	local f = CreateFrame("Frame", "PFGLinkPopup", UIParent, "BackdropTemplate")
	f:SetSize(340, 104)
	f:SetPoint("CENTER", 0, 120)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:Hide()

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(20, 20)
	f.icon:SetPoint("TOPLEFT", 20, -18)

	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(290, 22)
	box:SetPoint("TOP", 0, -46)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetJustifyH("CENTER")
	local function reset(self)
		self:SetText(f.url or "")
		self:SetFocus()
		self:HighlightText()
	end
	f.reset = reset
	-- Keep the link intact whatever gets typed, so Ctrl+C always copies it.
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			reset(self)
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEscapePressed", function()
		f:Hide()
	end)
	box:SetScript("OnEnterPressed", function()
		f:Hide()
	end)
	f.box = box

	f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.hint:SetPoint("TOP", box, "BOTTOM", 0, -6)

	f:SetScript("OnShow", function()
		reset(box)
	end)
	f:SetScript("OnHide", function()
		box:ClearFocus()
	end)
	tinsert(UISpecialFrames, f:GetName()) -- Esc closes it
	return f
end

function D.ShowLink(link)
	popup = popup or createPopup()
	popup.url = D.LinkURL(link)
	popup.icon:SetTexture(link.icon)
	popup.title:SetText(link.title)
	popup.hint:SetText(link.hint)
	if popup:IsShown() then
		popup.reset(popup.box)
	else
		popup:Show()
	end
end

-- For /pfg discord and /pfg logs.
local function showSetting(link)
	if D.LinkURL(link) then
		D.ShowLink(link)
	elseif IsGuildLeader() then
		D.print("your guild has no " .. link.title .. " link yet. Add it under Guild Control > Pidge's Forever Settings (or /pfg settings).")
	else
		D.print("your guild has no " .. link.title .. " link yet. The Guild Master can add one.")
	end
end

function D.ShowDiscordInvite()
	showSetting(D.LINKS[1])
end

function D.ShowLogs()
	showSetting(D.LINKS[2])
end

-- The buttons on the guild Info tab -----------------------------------------

local buttons = {}

-- Blizzard moves the Message of the Day up when the guild has no challenges
-- (always, on Classic), so find whichever header the MOTD box hangs from.
local function placeButtons()
	local info = buttons[1] and buttons[1]:GetParent()
	if not info then
		return
	end
	-- Only the buttons with a link, right to left.
	local shown = {}
	for _, b in ipairs(buttons) do
		local on = D.InGuild() and D.LinkURL(b.link) ~= nil
		b:SetShown(on)
		if on then
			shown[#shown + 1] = b
		end
	end
	local first = shown[1]
	if not first then
		return
	end
	local header = info.Header1
	local motd = info.MOTDScrollFrame
	if motd and motd.GetPoint then
		local _, relativeTo = motd:GetPoint(1)
		if relativeTo then
			header = relativeTo
		end
	end
	first:ClearAllPoints()
	local title = info.TitleText
	if title then
		-- Level with the "Info" title, right-aligned with the MOTD box. In
		-- Blizzard's layout the box's right edge is 42 past the title's.
		local dx = 42
		local hr, tr = header and header.GetRight and header:GetRight(), title:GetRight()
		if hr and tr then
			dx = hr - tr
		end
		first:SetPoint("RIGHT", title, "RIGHT", dx - 6, 0)
	elseif header then
		first:SetPoint("BOTTOMRIGHT", header, "TOPRIGHT", -6, 6)
	else
		first:SetPoint("TOPRIGHT", info, "TOPRIGHT", -6, 24)
	end
	for i = 2, #shown do
		shown[i]:ClearAllPoints()
		shown[i]:SetPoint("RIGHT", shown[i - 1], "LEFT", -GAP, 0)
	end
	-- The version text sits just left of the leftmost button.
	D.leftmostButton = shown[#shown]
	D.Fire("BUTTONS_PLACED")
end
D._placeButtons = placeButtons

local function makeButton(info, link)
	local b = CreateFrame("Button", "PFG" .. link.key .. "Button", info)
	b.link = link
	b:SetSize(ICON_SIZE, ICON_SIZE)
	b:SetFrameLevel(info:GetFrameLevel() + 10)
	b:SetNormalTexture(link.icon)
	b:SetPushedTexture(link.icon)
	b:GetPushedTexture():SetVertexColor(0.75, 0.75, 0.75)
	b:SetHighlightTexture(link.icon, "ADD")
	b:GetHighlightTexture():SetAlpha(0.35)
	b:SetScript("OnClick", function()
		D.ShowLink(link)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(link.tooltip)
		GameTooltip:AddLine("Click for the link.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function addButtons()
	local info = CommunitiesFrame and CommunitiesFrame.GuildDetailsFrame and CommunitiesFrame.GuildDetailsFrame.Info
	if #buttons > 0 or not info then
		return
	end
	for i, link in ipairs(D.LINKS) do
		buttons[i] = makeButton(info, link)
	end
	placeButtons()
	info:HookScript("OnShow", placeButtons)
	if CommunitiesGuildInfoFrame_UpdateChallenges then
		hooksecurefunc("CommunitiesGuildInfoFrame_UpdateChallenges", placeButtons)
	end
end

D.OnGuildPanel(addButtons)
D.On("GUILD", placeButtons)
D.On("LINKS", placeButtons)

D.Command("discord", D.ShowDiscordInvite, "/pfg discord - the guild's Discord invite link")
D.Command({ "logs", "wcl" }, D.ShowLogs, "/pfg logs - the guild's Warcraft Logs page")
D.Command({ "curseforge", "addon", "github" }, function()
	D.ShowLink(D.LINKS[3])
end, "/pfg curseforge - the addon's CurseForge page")
