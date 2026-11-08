-- Pidge's Forever Guild: the Wishlist tab on the guild panel, just above the
-- Crafting Orders tab. Laid out like the orders page: a list of what
-- guildmates want, filtered to everyone's or your own, and a small form to
-- add an item.

local ADDON, ns = ...
local D = ns.D

local ROW_H = 38
local TAB_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local SUGGESTIONS = 6

local panel, tab, form
local state = { filter = "all", offset = 0 }

local FILTERS = {
	{ key = "all", label = "Everyone" },
	{ key = "mine", label = "My Wishes" },
}

local function act(fn, id)
	local ok, err = fn(id)
	if not ok and err then
		D.print(err)
	end
end

local function insertLink(link)
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	end
end

-- Rows ------------------------------------------------------------------------------

local function createRow(parent, i)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.08)

	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(30, 30)
	r.icon:SetPoint("LEFT", 6, 0)

	r.title = r:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
	r.title:SetPoint("RIGHT", r, "RIGHT", -100, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)

	r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -100, 0)
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(false)

	r.button = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.button:SetSize(80, 20)
	r.button:SetPoint("RIGHT", r, "RIGHT", -6, 0)
	r.button:SetScript("OnClick", function()
		local w = r.wish
		if not w then
			return
		end
		if w.owner == D.Me() then
			act(D.RemoveWish, w.id)
		else
			D._whisper(w.owner)
		end
	end)

	-- Officers' remove button (an X) for other members' wishes.
	r.remove = CreateFrame("Button", nil, r, "UIPanelCloseButton")
	r.remove:SetSize(22, 22)
	r.remove:SetPoint("RIGHT", r.button, "LEFT", -2, 0)
	r.remove:SetScript("OnClick", function()
		if r.wish then
			act(D.RemoveWish, r.wish.id)
		end
	end)
	r.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Remove from the wishlist")
		GameTooltip:AddLine("As an officer you can remove anyone's wish.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	r.remove:SetScript("OnLeave", GameTooltip_Hide)
	r.remove:Hide()

	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, button)
		local w = self.wish
		if not w then
			return
		end
		if button == "RightButton" and w.owner ~= D.Me() then
			D._whisper(w.owner)
		elseif IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
			insertLink(self.link)
		end
	end)
	r:SetScript("OnEnter", function(self)
		local w = self.wish
		if not w then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if w.itemID and w.itemID > 0 and GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(w.itemID)
		else
			GameTooltip:SetText(w.itemName ~= "" and w.itemName or "Unknown item")
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Wanted by", D.Short(w.owner), 1, 0.82, 0, 1, 1, 1)
		if w.note and w.note ~= "" then
			GameTooltip:AddLine('"' .. w.note .. '"', 1, 1, 1, true)
		end
		if w.owner ~= D.Me() then
			GameTooltip:AddLine("Right-click to whisper " .. D.Short(w.owner) .. ".", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	return r
end

local function fillRow(r, w)
	r.wish = w
	local name, icon, link = D._itemInfo(w)
	r.link = link
	r.icon:SetTexture(icon)
	r.title:SetText(name .. (w.qty > 1 and ("|cffffffff x" .. w.qty .. "|r") or ""))
	local mine = w.owner == D.Me()
	local bits = { mine and "You want this" or (D.Short(w.owner) .. " wants this") }
	if w.itemID and w.itemID > 0 and D.CraftProfession and D.CraftProfession(w.itemID) then
		local who = D.WhoCanMake and D.WhoCanMake(w.itemID)
		if who and #who > 0 then
			bits[#bits + 1] = "|cff80ff80craftable in the guild|r"
		end
	end
	if w.note and w.note ~= "" then
		bits[#bits + 1] = '"' .. w.note .. '"'
	end
	r.sub:SetText(table.concat(bits, " - "))
	r.button:SetText(mine and "Remove" or "Whisper")
	r.remove:SetShown(not mine and D.CanRemoveWish(w))
	r:Show()
end

local function visibleWishes()
	return D.Wishes(state.filter == "mine" and D.Me() or nil)
end
D._visibleWishes = visibleWishes

function D.RefreshWishlist()
	if not panel or not panel:IsShown() then
		return
	end
	for _, b in ipairs(panel.filterButtons) do
		if b.key == state.filter then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	local list = visibleWishes()
	local h = panel.list:GetHeight() or 0
	local fit = math.max(1, math.min(#panel.rows, math.floor(h / ROW_H)))
	if h <= 0 then
		fit = #panel.rows
	end
	local maxOffset = math.max(0, #list - fit)
	state.offset = math.min(math.max(0, state.offset), maxOffset)
	for i, r in ipairs(panel.rows) do
		local w = i <= fit and list[state.offset + i]
		if w then
			fillRow(r, w)
		else
			r.wish = nil
			r:Hide()
		end
	end
	panel.scrollBar.updating = true
	panel.scrollBar:SetMinMaxValues(0, maxOffset)
	panel.scrollBar:SetValue(state.offset)
	panel.scrollBar.updating = false
	panel.scrollBar:SetShown(maxOffset > 0)
	if #list == 0 then
		panel.empty:SetText(state.filter == "mine" and "Your wishlist is empty. Click Add Item to list something you want."
			or "Nobody has wished for anything yet.")
		panel.empty:Show()
	else
		panel.empty:Hide()
	end
	panel.count:SetText(#list == 1 and "1 item" or (#list .. " items"))
end

D.On("WISHES", function()
	D.RefreshWishlist()
end)

-- The add form ----------------------------------------------------------------------

local function input(parent, width, numeric, letters)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 22)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	if numeric then
		e:SetNumeric(true)
	end
	if letters then
		e:SetMaxLetters(letters)
	end
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	return e
end

local function label(parent, text, anchor, y)
	local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	l:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
	l:SetText(text)
	return l
end

local function setItem(id, name)
	form.itemID = id
	form.settingText = true
	form.item:SetText(name or "")
	form.settingText = false
	form.error:SetText("")
	for _, b in ipairs(form.suggestions) do
		b:Hide()
	end
end

local function updateSuggestions()
	local text = form.item:GetText() or ""
	local found = D.SearchItems(text, SUGGESTIONS, true)
	for i, b in ipairs(form.suggestions) do
		local s = found[i]
		if s and form.item:HasFocus() then
			b.id, b.name = s.id, s.name
			b.text:SetText(s.name)
			b:Show()
		else
			b:Hide()
		end
	end
end

local function resetForm()
	form.itemID = nil
	form.settingText = true
	form.item:SetText("")
	form.settingText = false
	form.qty:SetText("1")
	form.note:SetText("")
	form.error:SetText("")
	for _, b in ipairs(form.suggestions) do
		b:Hide()
	end
end

local function submit()
	local text = (form.item:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local id = form.itemID
	if not id and text ~= "" then
		id = D.FindItem(text, true)
	end
	local w, err = D.AddWish({ itemID = id or 0, itemName = text, qty = form.qty:GetText(), note = form.note:GetText() })
	if not w then
		form.error:SetText(err)
		return
	end
	state.filter, state.offset = "mine", 0
	D.ShowWishForm(false)
end
D._submitWish = submit

local function createForm(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", parent.box, "TOPLEFT", 0, -40)
	f:SetPoint("BOTTOMRIGHT", parent.box, "BOTTOMRIGHT", 0, 30)
	f:Hide()

	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT", 16, -8)
	top:SetSize(1, 1)

	label(f, "Item", top, 0)
	f.item = input(f, 260)
	f.item:SetPoint("TOPLEFT", top, "TOPLEFT", 110, 4)
	f.item:SetScript("OnTextChanged", function(self, user)
		if not f.settingText then
			f.itemID = nil
			updateSuggestions()
		end
	end)
	f.item:SetScript("OnEditFocusLost", function()
		if C_Timer then
			C_Timer.After(0.2, function()
				for _, b in ipairs(f.suggestions) do
					b:Hide()
				end
			end)
		end
	end)
	local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("LEFT", f.item, "RIGHT", 8, 0)
	hint:SetText("type a name or shift-click an item")

	f.suggestions = {}
	for i = 1, SUGGESTIONS do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(260, 20)
		b:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", -4, -2 - (i - 1) * 20)
		b:SetFrameLevel(f:GetFrameLevel() + 30)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		b.text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 6, 0)
		b:SetScript("OnClick", function(self)
			setItem(self.id, self.name)
			f.qty:SetFocus()
		end)
		b:Hide()
		f.suggestions[i] = b
	end

	label(f, "Quantity", top, -34)
	f.qty = input(f, 60, true, 4)
	f.qty:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -30)

	label(f, "Note", top, -68)
	f.note = input(f, 260, false, 60)
	f.note:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -64)

	f.error = f:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	f.error:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -96)
	f.error:SetWidth(380)
	f.error:SetJustifyH("LEFT")

	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	add:SetSize(110, 22)
	add:SetPoint("TOPLEFT", top, "TOPLEFT", 104, -118)
	add:SetText("Add to Wishlist")
	add:SetScript("OnClick", submit)
	f.add = add

	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(80, 22)
	cancel:SetPoint("LEFT", add, "RIGHT", 6, 0)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function()
		D.ShowWishForm(false)
	end)
	return f
end

-- A shift-clicked item goes into the item box while it has focus.
local function onInsertLink(link)
	if form and form:IsVisible() and form.item:HasFocus() and link then
		local id, name = D._parseLink(link)
		if id then
			D.LearnItem(id, name)
			setItem(id, name or D.ItemName(id) or "")
			return true
		end
	end
end
D._onWishInsertLink = onInsertLink
D._wishForm = function()
	return form
end

function D.ShowWishForm(show)
	if not panel then
		return
	end
	form = form or createForm(panel)
	if show then
		resetForm()
		form:Show()
		panel.list:Hide()
		panel.addButton:Hide()
		form.item:SetFocus()
	else
		form.item:ClearFocus()
		form:Hide()
		panel.list:Show()
		panel.addButton:Show()
		D.RefreshWishlist()
	end
end

-- The panel -------------------------------------------------------------------------

local function createPanel()
	local cf = CommunitiesFrame
	local p = CreateFrame("Frame", "PFGWishlistFrame", cf)
	p:SetPoint("TOPLEFT", cf.CommunitiesList, "TOPRIGHT", 0, 0)
	p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -6, 26)
	p:SetFrameLevel(500)
	p:EnableMouse(true)
	p:Hide()

	local box = CreateFrame("Frame", nil, p)
	box:SetPoint("TOPLEFT", cf.CommunitiesList, "TOPRIGHT", 24, -40)
	box:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -12, 30)
	p.box = box
	local okBorder, border = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if okBorder and border then
		border:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
		border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -3)
		if type(border.Bg) == "table" then
			border.Bg:Hide()
		end
		border:SetFrameLevel(p:GetFrameLevel() + 20)
		border:EnableMouse(false)
	end
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)

	p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
	p.title:SetPoint("LEFT", box, "TOPLEFT", 10, 16)
	p.title:SetText("Wishlist")

	p.addButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.addButton:SetSize(110, 22)
	p.addButton:SetPoint("RIGHT", box, "TOPRIGHT", -2, 16)
	p.addButton:SetText("Add Item")
	p.addButton:SetScript("OnClick", function()
		D.ShowWishForm(true)
	end)

	local header = box:CreateTexture(nil, "BORDER")
	header:SetTexture("Interface\\GuildFrame\\GuildFrame")
	header:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
	header:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
	header:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
	header:SetHeight(30)
	local line = box:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.45, 0.45, 0.45, 0.9)
	line:SetHeight(3)
	line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)

	p.filterButtons = {}
	local prev
	for i, flt in ipairs(FILTERS) do
		local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		b:SetSize(86, 22)
		if i == 1 then
			b:SetPoint("LEFT", header, "LEFT", 6, 0)
		else
			b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		end
		b:SetText(flt.label)
		b.key = flt.key
		b:SetScript("OnClick", function()
			state.filter, state.offset = flt.key, 0
			D.ShowWishForm(false)
		end)
		p.filterButtons[i] = b
		prev = b
	end

	p.list = CreateFrame("Frame", nil, p)
	p.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 5, -8)
	p.list:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 24)
	local ok, inset = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if ok and inset then
		inset:SetPoint("TOPLEFT", p.list, "TOPLEFT", -3, 3)
		inset:SetPoint("BOTTOMRIGHT", p.list, "BOTTOMRIGHT", 0, -2)
		if type(inset.Bg) == "table" then
			inset.Bg:Hide()
		end
		inset:SetFrameLevel(p:GetFrameLevel() + 20)
		inset:EnableMouse(false)
	end

	local bar = CreateFrame("Slider", nil, p)
	bar:SetPoint("TOPLEFT", p.list, "TOPRIGHT", 4, -3)
	bar:SetPoint("BOTTOMLEFT", p.list, "BOTTOMRIGHT", 4, 2)
	bar:SetWidth(16)
	bar:SetOrientation("VERTICAL")
	bar:SetValueStep(1)
	if bar.SetObeyStepOnDrag then
		bar:SetObeyStepOnDrag(true)
	end
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
	track:SetHorizTile(true)
	track:SetVertTile(true)
	bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	local thumb = bar:GetThumbTexture()
	if thumb then
		thumb:SetSize(18, 24)
	end
	bar:SetScript("OnValueChanged", function(self, value, userInput)
		if userInput ~= false and not self.updating then
			state.offset = math.floor(value + 0.5)
			D.RefreshWishlist()
		end
	end)
	p.scrollBar = bar
	p.list:EnableMouseWheel(true)
	p.list:SetScript("OnMouseWheel", function(_, delta)
		state.offset = math.max(0, state.offset - delta)
		D.RefreshWishlist()
	end)
	p.list:SetScript("OnSizeChanged", function()
		D.RefreshWishlist()
	end)

	p.rows = {}
	for i = 1, 12 do
		p.rows[i] = createRow(p.list, i)
		p.rows[i]:Hide()
	end

	p.empty = p.list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	p.empty:SetPoint("TOP", 0, -40)
	p.empty:SetWidth(420)

	p.count = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	p.count:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, 6)

	local help = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	help:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
	help:SetText("Only guildmates with Pidge's Forever Guild AddOn see the wishlist.")

	p:SetScript("OnShow", D.RefreshWishlist)
	return p
end

-- The tab -----------------------------------------------------------------------------

local blizzardTabs = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }

local function setChecked()
	local on = panel and panel:IsShown()
	tab:SetChecked(on and true or false)
	if on then
		for _, key in ipairs(blizzardTabs) do
			if CommunitiesFrame[key] then
				CommunitiesFrame[key]:SetChecked(false)
			end
		end
	end
end

function D.ShowWishlist(show)
	if not panel then
		return
	end
	if show then
		if not panel:IsShown() then
			D.ShowOrders(false)
			D.CoverGuildContent()
		end
		panel:Show()
		D.ShowWishForm(false)
	else
		if form then
			form.item:ClearFocus()
		end
		if panel:IsShown() then
			panel:Hide()
			D.UncoverGuildContent()
		end
	end
	setChecked()
end

D.On("PANEL", function(which)
	if which ~= "wishlist" then
		D.ShowWishlist(false)
	end
end)

local function updateTab()
	local info = CommunitiesFrame.GuildInfoTab
	local shown = info and info:IsShown() and D.InGuild()
	tab:SetShown(shown and true or false)
	if not shown then
		D.ShowWishlist(false)
	else
		setChecked()
	end
end

local function createTab()
	local cf = CommunitiesFrame
	local ok, t = pcall(CreateFrame, "CheckButton", "PFGWishlistTab", cf, "CommunitiesFrameTabTemplate")
	if not ok or not t then
		t = CreateFrame("CheckButton", "PFGWishlistTab", cf)
		t:SetSize(32, 32)
	end
	if type(t.Icon) ~= "table" then
		t.Icon = t:CreateTexture(nil, "ARTWORK")
		t.Icon:SetSize(30, 30)
		t.Icon:SetPoint("CENTER")
	end
	t.Icon:SetTexture(TAB_ICON)
	t.tooltip = "Wishlist"
	-- Just above the Crafting Orders tab, spaced like Blizzard's tabs.
	if PFGOrdersTab then
		t:SetPoint("BOTTOMLEFT", PFGOrdersTab, "TOPLEFT", 0, 20)
	else
		t:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", 0, 12)
	end
	t:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		D.ShowWishlist(true)
	end)
	t:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Wishlist")
		GameTooltip:AddLine("List items you want or need, and see what your guildmates are after.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", GameTooltip_Hide)
	t:Hide()
	return t
end

D.OnGuildPanel(function()
	local cf = CommunitiesFrame
	if not cf.GuildInfoTab then
		return
	end
	panel = createPanel()
	tab = createTab()

	-- Any other tab closes the wishlist before Blizzard shows its view.
	local hooked = {}
	local function hookTab(t)
		if type(t) == "table" and t ~= tab and not hooked[t] and t.HookScript then
			hooked[t] = true
			t:HookScript("PreClick", function()
				D.ShowWishlist(false)
			end)
		end
	end
	local function hookSideTabs()
		for _, key in ipairs(blizzardTabs) do
			hookTab(cf[key])
		end
		for _, child in ipairs({ cf:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "CheckButton" then
				hookTab(child)
			end
		end
	end
	hookSideTabs()
	if cf.UpdateCommunitiesTabs then
		hooksecurefunc(cf, "UpdateCommunitiesTabs", function()
			hookSideTabs()
			updateTab()
		end)
	end
	if cf.SetDisplayMode then
		hooksecurefunc(cf, "SetDisplayMode", function()
			if panel:IsShown() then
				D.ForgetCoveredContent()
				panel:Hide()
				setChecked()
			end
		end)
	end
	D.On("GUILD", updateTab)
	cf:HookScript("OnHide", function()
		D.ShowWishlist(false)
	end)
	updateTab()

	if ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
	end
end)

D.Command({ "wishlist", "wish" }, function()
	if not CommunitiesFrame or not panel then
		if ToggleGuildFrame then
			ToggleGuildFrame()
		end
	elseif not CommunitiesFrame:IsShown() then
		ShowUIPanel(CommunitiesFrame)
	end
	if C_Timer then
		C_Timer.After(0, function()
			if panel and tab and tab:IsShown() then
				D.ShowWishlist(true)
			end
		end)
	end
end, "/pfg wishlist - open the guild wishlist")
