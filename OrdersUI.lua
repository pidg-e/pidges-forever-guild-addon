-- Pidge's Forever Guild: the Crafting Orders tab on the guild panel. It sits under
-- Blizzard's side tabs (Chat, Roster, Benefits, Info) and covers the content
-- area while it's selected.

local ADDON, ns = ...
local D = ns.D
local S = D.STATUS

local ROW_H = 38
local TAB_ICON = "Interface\\Icons\\Trade_BlackSmithing"

local panel, tab

local FILTERS = {
	{ key = "open", label = "Open" },
	{ key = "mine", label = "My Orders" },
	{ key = "crafts", label = "My Crafts" },
	{ key = "history", label = "History" },
}

local state = { filter = "open", prof = nil, offset = 0 }

-- Helpers -------------------------------------------------------------------------

local function money(copper)
	if not copper or copper <= 0 then
		return nil
	end
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	if g > 0 and s > 0 then
		return ("%dg %ds"):format(g, s)
	elseif g > 0 then
		return ("%dg"):format(g)
	end
	return ("%ds"):format(s)
end
D._money = money

local function itemInfo(o)
	local name, link, quality, icon
	if o.itemID and o.itemID > 0 then
		local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
		if getInfo then
			name, link, quality, _, _, _, _, _, _, icon = getInfo(o.itemID)
		end
		if not icon then
			local getIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
			icon = getIcon and getIcon(o.itemID)
		end
	end
	if not name and o.itemID and o.itemID > 0 then
		name = D.ItemName(o.itemID) -- asks the game, so the row fills in later
	end
	name = name or (o.itemName ~= "" and o.itemName) or "Unknown item"
	if o.itemID and o.itemID > 0 then
		name = "[" .. name .. "]" -- reads as an item link; hover the row for the tooltip
	end
	local color = "|cffffffff"
	if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		color = ITEM_QUALITY_COLORS[quality].hex
	end
	local prof = D.PROF_BY_CODE[o.prof or ""]
	return color .. name .. "|r", icon or (prof and prof.icon) or "Interface\\Icons\\INV_Misc_QuestionMark", link
end

local function visible(o)
	local me = D.Me()
	if state.prof and o.prof ~= state.prof then
		return false
	end
	if state.filter == "open" then
		return o.status == S.OPEN
	elseif state.filter == "mine" then
		return o.requester == me and (o.status == S.OPEN or o.status == S.ACCEPTED)
	elseif state.filter == "crafts" then
		return o.crafter == me and o.status == S.ACCEPTED
	end
	return o.status == S.DONE or o.status == S.CANCELLED
end

local function whisper(name)
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	end
end

local function act(fn, id)
	local ok, err = fn(id)
	if not ok and err then
		D.print(err)
	end
end

-- The buttons a row offers, depending on who you are and where the order is.
-- Returns a list of { label, fn }.
function D.OrderActions(o)
	local me = D.Me()
	local list = {}
	if o.status == S.OPEN then
		if o.requester == me then
			list[#list + 1] = { "Cancel", D.CancelOrder }
		else
			list[#list + 1] = { "Accept", D.AcceptOrder }
		end
	elseif o.status == S.ACCEPTED then
		if o.crafter == me then
			list[#list + 1] = { "Done", D.CompleteOrder }
			list[#list + 1] = { "Give Back", D.AbandonOrder }
		end
		if o.requester == me then
			list[#list + 1] = { "Received", D.CompleteOrder }
			list[#list + 1] = { "Cancel", D.CancelOrder }
		end
	end
	return list
end

local function statusText(o)
	if o.status == S.OPEN then
		return "|cff66ff66Open|r"
	elseif o.status == S.ACCEPTED then
		return "|cffffd100Crafting:|r " .. D.Short(o.crafter)
	elseif o.status == S.DONE then
		return "|cff999999Done" .. (o.crafter and (" by " .. D.Short(o.crafter)) or "") .. "|r"
	end
	return "|cff999999Cancelled|r"
end

-- Menus ---------------------------------------------------------------------------

local function professionMenu(owner, current, allowAny, onPick)
	local codes = D.CRAFTING
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, root)
			if allowAny then
				root:CreateRadio("All professions", function()
					return current() == nil
				end, function()
					onPick(nil)
				end)
			end
			for _, code in ipairs(codes) do
				root:CreateRadio(D.PROF_BY_CODE[code].name, function()
					return current() == code
				end, function()
					onPick(code)
				end)
			end
		end)
		return
	end
	-- No menu API: step through the list instead.
	local options = allowAny and { false } or {}
	for _, c in ipairs(codes) do
		options[#options + 1] = c
	end
	local cur = current() or false
	for i, c in ipairs(options) do
		if c == cur then
			onPick(options[i % #options + 1] or nil)
			return
		end
	end
	onPick(options[1] or nil)
end

-- The order list ------------------------------------------------------------------

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
	r.title:SetPoint("RIGHT", r, "RIGHT", -230, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)

	r.sub = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
	r.sub:SetPoint("RIGHT", r, "RIGHT", -230, 0)
	r.sub:SetJustifyH("LEFT")
	r.sub:SetWordWrap(false)

	r.status = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	r.status:SetPoint("RIGHT", r, "RIGHT", -150, 0)
	r.status:SetWidth(80)
	r.status:SetJustifyH("RIGHT")

	r.buttons = {}
	for b = 1, 2 do
		local btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		btn:SetSize(68, 20)
		if b == 1 then
			btn:SetPoint("RIGHT", r, "RIGHT", -6, 0)
		else
			btn:SetPoint("RIGHT", r.buttons[1], "LEFT", -4, 0)
		end
		btn:SetScript("OnClick", function(self)
			if self.fn and r.order then
				act(self.fn, r.order.id)
			end
		end)
		r.buttons[b] = btn
	end

	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, button)
		local o = self.order
		if not o then
			return
		end
		local other = o.requester == D.Me() and o.crafter or o.requester
		if button == "RightButton" and other then
			whisper(other)
		elseif IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
			if ChatFrameUtil and ChatFrameUtil.InsertLink then
				ChatFrameUtil.InsertLink(self.link)
			elseif ChatEdit_InsertLink then
				ChatEdit_InsertLink(self.link)
			end
		end
	end)
	r:SetScript("OnEnter", function(self)
		local o = self.order
		if not o then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if o.itemID and o.itemID > 0 and GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(o.itemID)
		else
			GameTooltip:SetText(o.itemName ~= "" and o.itemName or "Unknown item")
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Requested by", D.Short(o.requester), 1, 0.82, 0, 1, 1, 1)
		if o.crafter then
			GameTooltip:AddDoubleLine("Crafter", D.Short(o.crafter), 1, 0.82, 0, 1, 1, 1)
		end
		if o.note and o.note ~= "" then
			GameTooltip:AddLine('"' .. o.note .. '"', 1, 1, 1, true)
		end
		local other = o.requester == D.Me() and o.crafter or o.requester
		if other and other ~= D.Me() then
			GameTooltip:AddLine("Right-click to whisper " .. D.Short(other) .. ".", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)
	return r
end

local function fillRow(r, o)
	r.order = o
	local name, icon, link = itemInfo(o)
	r.link = link
	r.icon:SetTexture(icon)
	r.title:SetText(name .. (o.qty > 1 and (" |cffffffffx" .. o.qty .. "|r") or ""))
	local bits = {}
	local prof = D.PROF_BY_CODE[o.prof or ""]
	if prof then
		bits[#bits + 1] = prof.name
	end
	bits[#bits + 1] = "for " .. (o.requester == D.Me() and "you" or D.Short(o.requester))
	local tip = money(o.tip)
	if tip then
		bits[#bits + 1] = "|cffffd100tip " .. tip .. "|r"
	end
	if o.note and o.note ~= "" then
		bits[#bits + 1] = "|cffaaaaaa" .. o.note .. "|r"
	end
	r.sub:SetText(table.concat(bits, "  ·  "))
	r.status:SetText(statusText(o))
	local actions = D.OrderActions(o)
	for b, btn in ipairs(r.buttons) do
		local a = actions[b]
		if a then
			btn:SetText(a[1])
			btn.fn = a[2]
			btn:Show()
		else
			btn.fn = nil
			btn:Hide()
		end
	end
	r:Show()
end

local EMPTY = {
	open = "No open orders right now. Click New Order to ask the guild for something.",
	mine = "You have no open orders. Click New Order to place one.",
	crafts = "You aren't crafting anything. Accept an order from the Open list.",
	history = "Finished and cancelled orders show up here for two weeks.",
}

function D.RefreshOrders()
	if not panel or not panel:IsShown() then
		return
	end
	local list = {}
	for _, o in ipairs(D.Orders()) do
		if visible(o) then
			list[#list + 1] = o
		end
	end
	local rows = panel.rows
	local fit = math.max(1, math.floor((panel.list:GetHeight() or (ROW_H * 6)) / ROW_H))
	state.offset = math.max(0, math.min(state.offset, #list - fit))
	for i, r in ipairs(rows) do
		local o = i <= fit and list[i + state.offset]
		if o then
			fillRow(r, o)
		else
			r.order = nil
			r:Hide()
		end
	end
	panel.empty:SetShown(#list == 0)
	panel.empty:SetText(EMPTY[state.filter])
	if #list > fit then
		panel.count:SetText(("%d-%d of %d  (scroll for more)"):format(state.offset + 1, math.min(#list, state.offset + fit), #list))
	else
		panel.count:SetText(#list > 0 and (#list .. (#list == 1 and " order" or " orders")) or "")
	end
	local bar = panel.scrollBar
	if bar then
		local max = math.max(0, #list - fit)
		bar.updating = true
		bar:SetMinMaxValues(0, max)
		bar:SetValue(state.offset)
		bar.updating = false
		bar:SetShown(max > 0)
	end
	for _, b in ipairs(panel.filterButtons) do
		if b.key == state.filter then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	local p = D.PROF_BY_CODE[state.prof or ""]
	panel.profButton:SetText(p and p.name or "All professions")
end

D.On("ORDERS", function()
	D.RefreshOrders()
end)
-- Item names arrive from the game (lots at once while the item list is
-- being read), so catch up on them twice a second at most.
local itemsPending = false
D.On("ITEMS", function()
	if itemsPending or not panel or not panel:IsShown() then
		return
	end
	itemsPending = true
	local function catchUp()
		itemsPending = false
		D.RefreshOrders()
		if D._formHasFocus and D._formHasFocus() then
			D._updateSuggestions()
		end
	end
	if C_Timer then
		C_Timer.After(0.5, catchUp)
	else
		catchUp()
	end
end)

-- The new order form ----------------------------------------------------------------

local form

local function parseLink(link)
	local id = link and tonumber(link:match("item:(%d+)"))
	local name = link and link:match("%[(.-)%]")
	return id, name
end
D._parseLink = parseLink

local function updateCrafters()
	local code = form.prof
	local makers = form.itemID and form.itemID > 0 and D.WhoCanMake(form.itemID) or {}
	if #makers > 0 then
		local names = {}
		for i, m in ipairs(makers) do
			if i > 6 then
				names[#names + 1] = "..."
				break
			end
			names[#names + 1] = D.Short(m[1])
		end
		form.crafters:SetText("|cffffd100Can make this:|r " .. table.concat(names, ", "))
		return
	end
	if not code then
		form.crafters:SetText("Pick a profession to see who in the guild can make it.")
		return
	end
	local names = {}
	for i, c in ipairs(D.Crafters(code)) do
		if i > 6 then
			names[#names + 1] = "..."
			break
		end
		names[#names + 1] = ("%s |cffaaaaaa(%d)|r"):format(D.Short(c[1]), c[2])
	end
	if #names == 0 then
		form.crafters:SetText("No one with the addon has shared " .. D.PROF_BY_CODE[code].name .. " yet.")
	else
		form.crafters:SetText("|cffffd100Crafters:|r " .. table.concat(names, ", "))
	end
end

local function label(parent, text, anchor, y)
	local l = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	l:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, y)
	l:SetText(text)
	return l
end

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

local SUGGESTIONS = 8

local function itemColor(id)
	local _, _, quality = (C_Item and C_Item.GetItemInfo or GetItemInfo or function() end)(id)
	if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		return ITEM_QUALITY_COLORS[quality].hex
	end
	return "|cffffffff"
end

local function itemIcon(id)
	local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
	return fn and id and id > 0 and fn(id) or nil
end

local function showItemTooltip(owner, id)
	if not id or id <= 0 then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(id)
	else
		GameTooltip:SetHyperlink("item:" .. id)
	end
	GameTooltip:Show()
end

local function hideSuggestions()
	if form and form.suggest then
		form.suggest:Hide()
	end
end

-- Fill the item box with a real item, so the order links to it.
local function setItem(id, name)
	form.itemID = id
	form.item:SetText(name or "")
	form.item:SetCursorPosition(0)
	form.itemIcon.icon:SetTexture(itemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
	form.itemIcon:Show()
	-- The profession that makes it, picked for you.
	local code = D.CraftProfession(id)
	if not D.PROF_BY_CODE[code or ""] then
		local m = D.WhoCanMake(id)[1]
		code = m and m[2]
	end
	if D.PROF_BY_CODE[code or ""] then
		form.prof = code
		form.profButton:SetText(D.PROF_BY_CODE[code].name)
	end
	form.error:SetText("")
	if form.placeholder then
		form.placeholder:Hide()
	end
	hideSuggestions()
	updateCrafters()
end
D._setOrderItem = setItem

local function updateSuggestions()
	local list = D.SearchItems(form.item:GetText(), SUGGESTIONS)
	local box = form.suggest
	for i, r in ipairs(box.rows) do
		local it = list[i]
		r.id, r.itemName = it and it.id, it and it.name
		if it then
			r.icon:SetTexture(itemIcon(it.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
			r.text:SetText(itemColor(it.id) .. "[" .. it.name .. "]|r")
			local m = it.craft and D.WhoCanMake(it.id)[1]
			r.who:SetText(m and D.Short(m[1]) or "")
			r:Show()
		else
			r:Hide()
		end
	end
	box:SetHeight(#list * 20 + 8)
	box:SetShown(#list > 0 and form.item:HasFocus())
end
D._updateSuggestions = updateSuggestions
D._formHasFocus = function()
	return form and form:IsVisible() and form.item:HasFocus()
end

local function createSuggestions(f)
	local box = CreateFrame("Frame", nil, f)
	box:SetPoint("TOPLEFT", f.item, "BOTTOMLEFT", -6, -2)
	box:SetWidth(330)
	box:SetFrameLevel(f:GetFrameLevel() + 50)
	box:EnableMouse(true)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.95)
	local edge = box:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.5, 0.45, 0.3, 1)
	bg:SetDrawLayer("ARTWORK", -8)
	box.rows = {}
	for i = 1, SUGGESTIONS do
		local r = CreateFrame("Button", nil, box)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
		r:SetPoint("RIGHT", box, "RIGHT", -4, 0)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		r.icon = r:CreateTexture(nil, "OVERLAY")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 2, 0)
		r.who = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.who:SetPoint("RIGHT", -4, 0)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r.text:SetPoint("RIGHT", r.who, "LEFT", -6, 0)
		r.text:SetJustifyH("LEFT")
		r.text:SetWordWrap(false)
		r:SetScript("OnClick", function(self)
			if self.id then
				setItem(self.id, self.itemName)
				f.item:ClearFocus()
			end
		end)
		r:SetScript("OnEnter", function(self)
			showItemTooltip(self, self.id)
			if self.id and GameTooltip.AddLine then
				local makers = D.WhoCanMake(self.id)
				if #makers > 0 then
					local names = {}
					for k, m in ipairs(makers) do
						names[k] = D.Short(m[1])
					end
					GameTooltip:AddLine("Can make it: " .. table.concat(names, ", "), 0.4, 1, 0.4, true)
					GameTooltip:Show()
				end
			end
		end)
		r:SetScript("OnLeave", GameTooltip_Hide)
		r:Hide()
		box.rows[i] = r
	end
	box:Hide()
	return box
end

local function resetForm()
	form.itemID, form.prof = 0, state.prof
	form.item:SetText("")
	form.itemIcon:Hide()
	form.placeholder:Show()
	hideSuggestions()
	form.qty:SetText("1")
	form.tip:SetText("")
	form.note:SetText("")
	form.error:SetText("")
	local p = D.PROF_BY_CODE[form.prof or ""]
	form.profButton:SetText(p and p.name or "Choose...")
	updateCrafters()
end

local function createForm(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetAllPoints(parent.list)
	f:Hide()
	form = f

	local top = CreateFrame("Frame", nil, f)
	top:SetPoint("TOPLEFT", 16, -8)
	top:SetSize(1, 1)

	label(f, "Item", top, 0)
	f.item = input(f, 300)
	f.item:SetPoint("TOPLEFT", top, "TOPLEFT", 110, 4)
	-- The picked item's icon; hover it to see the item.
	f.itemIcon = CreateFrame("Button", nil, f)
	f.itemIcon:SetSize(22, 22)
	f.itemIcon:SetPoint("LEFT", f.item, "RIGHT", 6, 0)
	f.itemIcon.icon = f.itemIcon:CreateTexture(nil, "ARTWORK")
	f.itemIcon.icon:SetAllPoints()
	f.itemIcon:SetScript("OnEnter", function(self)
		showItemTooltip(self, f.itemID)
	end)
	f.itemIcon:SetScript("OnLeave", GameTooltip_Hide)
	f.itemIcon:Hide()
	f.item:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			f.itemID = 0 -- typing: not an item until one is picked
			f.itemIcon:Hide()
			updateSuggestions()
			updateCrafters()
		end
	end)
	f.item:SetScript("OnEnterPressed", function(self)
		local first = f.suggest.rows[1]
		if f.suggest:IsShown() and first.id then
			setItem(first.id, first.itemName)
		end
		self:ClearFocus()
	end)
	f.item:SetScript("OnEditFocusLost", function()
		-- Wait a moment, so a click on a suggestion still lands.
		if C_Timer then
			C_Timer.After(0.2, hideSuggestions)
		else
			hideSuggestions()
		end
	end)
	-- Hint shown inside the empty box, so it never runs off the panel.
	f.placeholder = f.item:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	f.placeholder:SetPoint("LEFT", f.item, "LEFT", 2, 0)
	f.placeholder:SetPoint("RIGHT", f.item, "RIGHT", -4, 0)
	f.placeholder:SetJustifyH("LEFT")
	f.placeholder:SetText("Type to search, or shift-click an item")
	f.item:HookScript("OnTextChanged", function(self)
		f.placeholder:SetShown((self:GetText() or "") == "")
	end)

	label(f, "Quantity", top, -34)
	f.qty = input(f, 50, true, 4)
	f.qty:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -30)

	label(f, "Profession", top, -68)
	f.profButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.profButton:SetSize(150, 22)
	f.profButton:SetPoint("TOPLEFT", top, "TOPLEFT", 104, -63)
	f.profButton:SetScript("OnClick", function(self)
		professionMenu(self, function()
			return f.prof
		end, false, function(code)
			f.prof = code
			local p = D.PROF_BY_CODE[code or ""]
			self:SetText(p and p.name or "Choose...")
			updateCrafters()
		end)
	end)

	label(f, "Tip (gold)", top, -102)
	f.tip = input(f, 70, true, 6)
	f.tip:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -98)
	local tipHint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tipHint:SetPoint("LEFT", f.tip, "RIGHT", 10, 0)
	tipHint:SetText("Optional, paid to the crafter")

	label(f, "Note", top, -136)
	f.note = input(f, 380, false, 60)
	f.note:SetPoint("TOPLEFT", top, "TOPLEFT", 110, -132)

	f.crafters = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.crafters:SetPoint("TOPLEFT", top, "TOPLEFT", 0, -172)
	f.crafters:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	f.crafters:SetJustifyH("LEFT")

	f.error = f:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	f.error:SetPoint("TOPLEFT", f.crafters, "BOTTOMLEFT", 0, -10)

	local post = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	post:SetSize(110, 24)
	post:SetPoint("TOPLEFT", top, "TOPLEFT", 104, -218)
	post:SetText("Post Order")
	post:SetScript("OnClick", function()
		local tip = tonumber(f.tip:GetText()) or 0
		if (f.itemID or 0) == 0 then
			local id, name = D.FindItem(f.item:GetText())
			if not id then
				f.error:SetText("Pick a craftable item from the suggestions, or shift-click one into the box.")
				return
			end
			setItem(id, name)
		end
		if not D.CraftProfession(f.itemID) then
			f.error:SetText("That item can't be crafted.")
			return
		end
		local ok, err = D.PlaceOrder({
			itemID = f.itemID,
			itemName = f.item:GetText(),
			qty = tonumber(f.qty:GetText()) or 1,
			prof = f.prof,
			tip = tip * 10000,
			note = f.note:GetText(),
		})
		if not ok then
			f.error:SetText(err or "Couldn't post that order.")
			return
		end
		D.ShowOrderForm(false)
		state.filter = "mine"
		state.offset = 0
		D.RefreshOrders()
	end)

	local back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	back:SetSize(80, 24)
	back:SetPoint("LEFT", post, "RIGHT", 8, 0)
	back:SetText("Back")
	back:SetScript("OnClick", function()
		D.ShowOrderForm(false)
	end)
	f.post = post
	f.suggest = createSuggestions(f)
	return f
end

-- A shift-clicked item goes into the form's item box while it has focus.
local function onInsertLink(link)
	if form and form:IsVisible() and form.item:HasFocus() and link then
		local id, name = parseLink(link)
		if id then
			D.LearnItem(id, name)
			if not D.CraftProfession(id) then
				form.error:SetText((name or "That item") .. " can't be crafted.")
				return true
			end
			setItem(id, name or D.ItemName(id) or "")
			return true
		end
	end
end
D._onInsertLink = onInsertLink
D._orderForm = function()
	return form
end

function D.ShowOrderForm(show)
	if not panel then
		return
	end
	form = form or createForm(panel)
	if show then
		resetForm()
		form:Show()
		panel.list:Hide()
		panel.newButton:Hide()
		form.item:SetFocus()
	else
		form.item:ClearFocus()
		form:Hide()
		panel.list:Show()
		panel.newButton:Show()
		D.RefreshOrders()
	end
end

-- The panel -------------------------------------------------------------------------

local function createPanel()
	local cf = CommunitiesFrame
	-- Laid out like the guild Info page: the title sits on the frame's grey
	-- strip at the top (which shows through), and the content fills the same
	-- box that Info and Guild News share.
	local p = CreateFrame("Frame", "PFGOrdersFrame", cf)
	p:SetPoint("TOPLEFT", cf.CommunitiesList, "TOPRIGHT", 0, 0)
	p:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -6, 26)
	p:SetFrameLevel(500)
	p:EnableMouse(true)
	p:Hide()

	local box = CreateFrame("Frame", nil, p)
	box:SetPoint("TOPLEFT", cf.CommunitiesList, "TOPRIGHT", 24, -40)
	box:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -12, 30)
	p.box = box
	-- Grey inset border round the box, as Blizzard draws round its pages,
	-- which also parts it from the community list's scroll bar.
	local okBorder, border = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if okBorder and border then
		border:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
		border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -3)
		if type(border.Bg) == "table" then
			border.Bg:Hide()
		end
		border:SetFrameLevel(p:GetFrameLevel() + 20)
		border:EnableMouse(false)
		p.boxBorder = border
	end
	-- The same marble background as the roster and the rest of the panel.
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
	bg:SetHorizTile(true)
	bg:SetVertTile(true)

	-- Same spot and font as the "Info" title.
	p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalMed1")
	p.title:SetPoint("LEFT", box, "TOPLEFT", 10, 16)
	p.title:SetText("Crafting Orders")

	p.newButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.newButton:SetSize(110, 22)
	p.newButton:SetPoint("RIGHT", box, "TOPRIGHT", -2, 16)
	p.newButton:SetText("New Order")

	-- The filter row sits on a header bar like Info's section headers.
	local header = box:CreateTexture(nil, "BORDER")
	header:SetTexture("Interface\\GuildFrame\\GuildFrame")
	header:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
	header:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
	header:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
	header:SetHeight(30)
	p.newButton:SetScript("OnClick", function()
		D.ShowOrderForm(true)
	end)

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
			D.ShowOrderForm(false)
		end)
		p.filterButtons[i] = b
		prev = b
	end

	p.profButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	p.profButton:SetSize(140, 22)
	p.profButton:SetPoint("LEFT", prev, "RIGHT", 16, 0)
	p.profButton:SetScript("OnClick", function(self)
		professionMenu(self, function()
			return state.prof
		end, true, function(code)
			state.prof, state.offset = code, 0
			D.RefreshOrders()
		end)
	end)

	p.list = CreateFrame("Frame", nil, p)
	p.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 5, -8)
	p.list:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 24)

	-- A grey inset border round the list, and the scroll bar beside it,
	-- like the roster's.
	local ok, inset = pcall(CreateFrame, "Frame", nil, p, "InsetFrameTemplate")
	if ok and inset then
		inset:SetPoint("TOPLEFT", p.list, "TOPLEFT", -3, 3)
		inset:SetPoint("BOTTOMRIGHT", p.list, "BOTTOMRIGHT", 0, -2)
		if type(inset.Bg) == "table" then
			inset.Bg:Hide()
		end
		inset:SetFrameLevel(p:GetFrameLevel() + 20)
		inset:EnableMouse(false)
		p.inset = inset
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
			D.RefreshOrders()
		end
	end)
	p.scrollBar = bar
	p.list:EnableMouseWheel(true)
	p.list:SetScript("OnMouseWheel", function(_, delta)
		state.offset = math.max(0, state.offset - delta)
		D.RefreshOrders()
	end)
	p.list:SetScript("OnSizeChanged", function()
		D.RefreshOrders()
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
	help:SetText("Only guildmates with Pidge's Forever Guild AddOn see these orders.")

	p:SetScript("OnShow", D.RefreshOrders)
	return p
end

-- The tab -----------------------------------------------------------------------------

local blizzardTabs = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }

-- Blizzard's content frames can sit above ours (the chat box and member list
-- set their own frame levels), so while our panel is up they're hidden, and
-- put back when it closes.
local CONTENT = {
	"Chat", "ChatEditBox", "MemberList", "StreamDropdown", "StreamDropDownMenu",
	"CommunitiesControlFrame", "AddToChatButton", "GuildMemberListDropdown", "GuildMemberListDropDownMenu",
	"CommunityMemberListDropdown", "CommunitiesCalendarButton", "GuildBenefitsFrame", "GuildDetailsFrame",
	"GuildNameAlertFrame", "GuildMemberDetailFrame", "InvitationFrame", "TicketFrame", "ClubFinderInvitationFrame",
	"GuildFinderFrame", "CommunityFinderFrame", "ApplicantList", "VoiceChatHeadset", "PostingExpirationText",
	"GuildLogButton", "GuildRecruitmentButton", "GuildControlButton", "ChatEditBoxBackground",
}
local covered = {}

local function cover()
	local cf = CommunitiesFrame
	for _, key in ipairs(CONTENT) do
		local f = cf[key]
		if type(f) == "table" and f.IsShown and f:IsShown() and f.Hide then
			covered[#covered + 1] = f
			f:Hide()
		end
	end
end

local function uncover()
	for i = #covered, 1, -1 do
		covered[i]:Show()
		covered[i] = nil
	end
end

local function setChecked()
	local cf = CommunitiesFrame
	local on = panel and panel:IsShown()
	tab:SetChecked(on and true or false)
	if on then
		for _, key in ipairs(blizzardTabs) do
			if cf[key] then
				cf[key]:SetChecked(false)
			end
		end
	end
end

local synced = false

function D.ShowOrders(show)
	if not panel then
		return
	end
	if show then
		if not panel:IsShown() then
			cover()
		end
		panel:Show()
		if not synced then
			synced = true
			D.RequestSync()
		end
		D.ShowOrderForm(false)
	else
		if form then
			form.item:ClearFocus()
		end
		hideSuggestions()
		panel:Hide()
		uncover()
	end
	setChecked()
end

-- Our tab shows whenever Blizzard's guild tabs do (a guild is selected), and
-- only while we are in a guild.
local function updateTab()
	local cf = CommunitiesFrame
	local info = cf.GuildInfoTab
	local shown = info and info:IsShown() and D.InGuild()
	tab:SetShown(shown and true or false)
	if not shown then
		D.ShowOrders(false)
	else
		setChecked()
	end
end

local function createTab()
	local cf = CommunitiesFrame
	local ok, t = pcall(CreateFrame, "CheckButton", "PFGOrdersTab", cf, "CommunitiesFrameTabTemplate")
	if not ok or not t then
		t = CreateFrame("CheckButton", "PFGOrdersTab", cf)
		t:SetSize(32, 32)
	end
	if type(t.Icon) ~= "table" then
		t.Icon = t:CreateTexture(nil, "ARTWORK")
		t.Icon:SetSize(30, 30)
		t.Icon:SetPoint("CENTER")
	end
	t.Icon:SetTexture(TAB_ICON)
	t.tooltip = "Crafting Orders"
	-- At the bottom of the tab column, apart from Blizzard's tabs.
	t:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", 0, 12)
	t:SetScript("OnClick", function()
		if PlaySound and SOUNDKIT then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
		D.ShowOrders(true)
	end)
	t:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Crafting Orders")
		GameTooltip:AddLine("Ask the guild to craft something, or fill a guildmate's order.", 1, 1, 1, true)
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

	-- Any other tab on the guild panel closes ours: Blizzard's four, and
	-- the rest of the side column (like Preferred Play Settings). Closing
	-- happens before the click, so Blizzard then shows its own view on top
	-- of the frames we put back.
	local hooked = {}
	local function hookTab(t)
		if type(t) == "table" and t ~= tab and not hooked[t] and t.HookScript then
			hooked[t] = true
			t:HookScript("PreClick", function()
				D.ShowOrders(false)
			end)
		end
	end
	for _, key in ipairs(blizzardTabs) do
		hookTab(cf[key])
	end
	local function hookSideTabs()
		for _, child in ipairs({ cf:GetChildren() }) do
			if child.GetObjectType and child:GetObjectType() == "CheckButton" then
				hookTab(child)
			end
		end
	end
	hookSideTabs()
	if cf.UpdateCommunitiesTabs then
		hooksecurefunc(cf, "UpdateCommunitiesTabs", function()
			hookSideTabs() -- tabs Blizzard made since
			updateTab()
		end)
	end
	if cf.SetDisplayMode then
		hooksecurefunc(cf, "SetDisplayMode", function()
			-- Blizzard switched views (a tab, another club, a settings page):
			-- that view is what should show now.
			if panel:IsShown() then
				wipe(covered)
				D.ShowOrders(false)
			end
		end)
	end
	D.On("GUILD", updateTab)
	cf:HookScript("OnHide", function()
		D.ShowOrders(false)
	end)
	updateTab()

	if ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
	end
end)

D.Command({ "orders", "craft" }, function()
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
				D.ShowOrders(true)
			end
		end)
	end
end, "/pfg orders - open the guild's crafting orders")
