-- Pidge's Forever Guild: a "Guild Order" button on the profession window. It opens the guild
-- crafting orders with a new order already filled in for the selected
-- recipe's item and profession.
--
-- Works with the modern profession window (Blizzard_Professions) and the
-- Classic trade skill window (Blizzard_TradeSkillUI); whichever this client has.

local ADDON, ns = ...
local D = ns.D

-- Opening the order form ------------------------------------------------------------

-- Open the guild panel on Crafting Orders with a new order for this item.
function D.StartOrderFor(id, name, code)
	if not D.InGuild() then
		D.print("crafting orders are only for guild members.")
		return
	end
	if not id or id <= 0 then
		return
	end
	if not (CommunitiesFrame and CommunitiesFrame:IsShown()) then
		if ToggleGuildFrame then
			ToggleGuildFrame()
		end
	end
	-- The guild panel may need a moment to load and pick the guild.
	local tries = 0
	local function fill()
		tries = tries + 1
		local tab = PFGOrdersTab
		if tab and tab:IsShown() then
			D.ShowOrders(true)
			D.ShowOrderForm(true)
			D._setOrderItem(id, name or D.ItemName(id) or "")
			local form = D._orderForm()
			if code and D.PROF_BY_CODE[code] and form then
				form.prof = code
				form.profButton:SetText(D.PROF_BY_CODE[code].name)
			end
			if form then
				form.item:ClearFocus()
				form.qty:SetFocus()
				if form.qty.HighlightText then
					form.qty:HighlightText()
				end
			end
		elseif tries < 20 and C_Timer then
			C_Timer.After(0.1, fill)
		end
	end
	if C_Timer then
		C_Timer.After(0, fill)
	else
		fill()
	end
end

-- The selected recipe -------------------------------------------------------------

local function linkID(link)
	return link and tonumber(link:match("item:(%d+)")), link and link:match("%[(.-)%]")
end

-- What the open profession window's selected recipe makes: id, name, code.
function D.SelectedRecipeItem()
	-- Modern profession window.
	local pf = ProfessionsFrame
	if pf and pf:IsShown() and pf.CraftingPage and pf.CraftingPage.SchematicForm then
		local ok, info = pcall(pf.CraftingPage.SchematicForm.GetRecipeInfo, pf.CraftingPage.SchematicForm)
		if ok and type(info) == "table" and info.recipeID and C_TradeSkillUI then
			local id
			if C_TradeSkillUI.GetRecipeSchematic then
				local ok2, s = pcall(C_TradeSkillUI.GetRecipeSchematic, info.recipeID, false)
				id = ok2 and type(s) == "table" and s.outputItemID
			end
			if not id and C_TradeSkillUI.GetRecipeItemLink then
				id = linkID(C_TradeSkillUI.GetRecipeItemLink(info.recipeID))
			end
			local code
			if C_TradeSkillUI.GetBaseProfessionInfo then
				local ok3, base = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
				local p = ok3 and type(base) == "table" and D.PROF_BY_NAME[base.professionName or ""]
				code = p and p.code
			end
			if id and id > 0 then
				return id, D.ItemName(id), code or D.CraftProfession(id)
			end
		end
	end
	-- Classic trade skill window.
	if TradeSkillFrame and TradeSkillFrame:IsShown() and GetTradeSkillSelectionIndex and GetTradeSkillItemLink then
		local index = GetTradeSkillSelectionIndex()
		local id, name = linkID(index and index > 0 and GetTradeSkillItemLink(index))
		if id then
			local line = GetTradeSkillLine and GetTradeSkillLine()
			local p = line and D.PROF_BY_NAME[line]
			return id, name, p and p.code or D.CraftProfession(id)
		end
	end
	-- Classic craft window (Enchanting): only recipes that make an item.
	if CraftFrame and CraftFrame:IsShown() and GetCraftSelectionIndex and GetCraftItemLink then
		local index = GetCraftSelectionIndex()
		local id, name = linkID(index and index > 0 and GetCraftItemLink(index))
		if id then
			return id, name, D.CraftProfession(id)
		end
	end
end

-- The button --------------------------------------------------------------------------

local buttons = {}

local function refresh(b)
	b:SetShown(D.InGuild())
	local id = D.SelectedRecipeItem()
	b:SetEnabled(id ~= nil)
end

local function makeButton(parent, anchor)
	if not parent or not anchor or buttons[parent] then
		return
	end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	-- Above Create All, lined up with its left edge.
	b:SetSize(math.max(140, anchor.GetWidth and anchor:GetWidth() or 0), 22)
	b:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 10, 16)
	b:SetText("Guild Order")
	b:SetMotionScriptsWhileDisabled(true)
	b:SetScript("OnClick", function()
		local id, name, code = D.SelectedRecipeItem()
		if id then
			D.StartOrderFor(id, name, code)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Guild Crafting Order")
		if self:IsEnabled() then
			GameTooltip:AddLine("Ask the guild to craft this for you.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Pick a recipe that makes an item.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	-- Keep up with the selected recipe without hooking Blizzard's code.
	local wait = 0
	b:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - (elapsed or 0)
		if wait <= 0 then
			wait = 0.25
			refresh(self)
		end
	end)
	buttons[parent] = b
	refresh(b)
	return b
end
D._craftButtons = buttons

local function attach()
	local pf = ProfessionsFrame
	if pf and pf.CraftingPage and pf.CraftingPage.CreateAllButton then
		makeButton(pf.CraftingPage, pf.CraftingPage.CreateAllButton)
	end
	if TradeSkillFrame and TradeSkillCreateAllButton then
		makeButton(TradeSkillFrame, TradeSkillCreateAllButton)
	end
	if CraftFrame and CraftCreateButton then
		makeButton(CraftFrame, CraftCreateButton)
	end
end
D._attachCraftButtons = attach

D.On("ADDON_LOADED", function(name)
	if name == "Blizzard_Professions" or name == "Blizzard_TradeSkillUI" or name == "Blizzard_CraftUI" or name == ADDON then
		attach()
	end
end)
