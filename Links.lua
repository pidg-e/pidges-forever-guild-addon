-- Dreamscape: link buttons on the guild panel's Info tab, level with the
-- "Info" title above the Message of the Day: Discord, then Warcraft Logs and
-- the addon's GitHub page to its left. WoW can't open web pages, so clicking one shows its link ready to
-- copy (Ctrl+C) and paste into a browser.

local ADDON, ns = ...
local D = ns.D

local MEDIA = "Interface\\AddOns\\Dreamscape\\media\\"
local ICON_SIZE = 22
local GAP = 4

-- Right to left, starting at the right edge of the MOTD box.
D.LINKS = {
	{
		key = "Discord",
		title = "Discord",
		tooltip = "Discord",
		url = "https://discord.gg/4uNGKeyyjN",
		icon = MEDIA .. "discord",
		hint = "Press Ctrl+C to copy, then paste it in your browser.",
	},
	{
		key = "Logs",
		title = "Warcraft Logs",
		tooltip = "Warcraft Logs",
		url = "https://forever.warcraftlogs.com/guild/id/833285",
		icon = MEDIA .. "logs",
		hint = "Press Ctrl+C to copy, then paste it in your browser.",
	},
	{
		key = "GitHub",
		title = "Dreamscape Addon",
		tooltip = "Dreamscape Addon",
		url = "https://github.com/pidg-e/dreamscape-addon",
		icon = MEDIA .. "github",
		hint = "Press Ctrl+C to copy, then paste it in your browser.",
	},
}
D.DISCORD_INVITE = D.LINKS[1].url

-- The link popup -------------------------------------------------------------

local popup

local function createPopup()
	local f = CreateFrame("Frame", "DreamscapeLinkPopup", UIParent, "BackdropTemplate")
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
	popup.url = link.url
	popup.icon:SetTexture(link.icon)
	popup.title:SetText(link.title)
	popup.hint:SetText(link.hint)
	if popup:IsShown() then
		popup.reset(popup.box)
	else
		popup:Show()
	end
end

function D.ShowDiscordInvite()
	D.ShowLink(D.LINKS[1])
end

function D.ShowLogs()
	D.ShowLink(D.LINKS[2])
end

-- The buttons on the guild Info tab -----------------------------------------

local buttons = {}

-- Blizzard moves the Message of the Day up when the guild has no challenges
-- (always, on Classic), so find whichever header the MOTD box hangs from.
local function placeButtons()
	local first = buttons[1]
	local info = first and first:GetParent()
	if not info then
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
	for _, b in ipairs(buttons) do
		b:SetShown(D.InDreamscape())
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
	for i = 2, #buttons do
		buttons[i]:ClearAllPoints()
		buttons[i]:SetPoint("RIGHT", buttons[i - 1], "LEFT", -GAP, 0)
	end
end
D._placeButtons = placeButtons

local function makeButton(info, link)
	local b = CreateFrame("Button", "Dreamscape" .. link.key .. "Button", info)
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

D.Command("discord", D.ShowDiscordInvite, "/ds discord - the guild's Discord invite link")
D.Command({ "logs", "wcl" }, D.ShowLogs, "/ds logs - the guild's Warcraft Logs page")
D.Command({ "github", "addon" }, function()
	D.ShowLink(D.LINKS[3])
end, "/ds github - the addon's GitHub page")
