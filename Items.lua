-- Dreamscape: item names for the crafting order form. WoW has no way to
-- search every item by name, so the addon keeps its own list of items it has
-- come across: things in your bags, item links in chat, items on orders, and
-- the recipes guild crafters know. Crafters share what their recipes make,
-- which is what makes the suggestions useful: they're things someone in the
-- guild can actually craft.

local ADDON, ns = ...
local D = ns.D

-- Item names (the same for every guild, so kept outside the guild data) --------

local function cache()
	if not DreamscapeDB then
		return nil
	end
	DreamscapeDB.items = DreamscapeDB.items or {}
	return DreamscapeDB.items
end

local function getInfo(id)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if fn then
		return fn(id)
	end
end

-- Craftable items ------------------------------------------------------------------
-- DreamscapeDB.crafts[itemID] = profession code. Only these can be ordered.
-- The game tells us what's craftable three ways: recipe spells (on clients
-- with the modern profession API), recipe items ("Pattern: Robe of the
-- Archmage", a Tailoring recipe), and what guild crafters' recipes make.

local function crafts()
	if not DreamscapeDB then
		return nil
	end
	DreamscapeDB.crafts = DreamscapeDB.crafts or {}
	return DreamscapeDB.crafts
end

-- Recipe item names waiting for their product's name: lower name -> code.
local function recipeProducts()
	DreamscapeDB.recipeProducts = DreamscapeDB.recipeProducts or {}
	return DreamscapeDB.recipeProducts
end

local byName -- lower name -> itemID, built on first use

local function nameIndex()
	if not byName then
		byName = {}
		for id, name in pairs(cache() or {}) do
			byName[name:lower()] = byName[name:lower()] or id
		end
	end
	return byName
end

function D.SetCraftable(id, code)
	local c = crafts()
	if not c or not id or id <= 0 then
		return
	end
	code = D.PROF_BY_CODE[code or ""] and code or (c[id] or "")
	if c[id] ~= code then
		c[id] = code
		D.Fire("ITEMS", id)
	end
end

-- The profession that makes an item: a code, "" if craftable by an unknown
-- profession, or nil if it isn't craftable.
function D.CraftProfession(id)
	local c = crafts()
	return c and id and c[id]
end

-- Recipe items' subclass is the profession that learns them.
local RECIPE_CLASS = 9
local RECIPE_SUBCLASS = { [1] = "LW", [2] = "TL", [3] = "EG", [4] = "BS", [5] = "CK", [6] = "AL", [7] = "FA", [8] = "EN", [9] = "FI", [10] = "JC", [11] = "IN" }
local recipeSub = {} -- recipe item ID -> profession code, until its name is known

local function learnRecipeItem(name, code)
	local product = name:match("^[^:]+:%s*(.+)$")
	if not product or not code then
		return
	end
	product = product:lower()
	local id = nameIndex()[product]
	if id then
		D.SetCraftable(id, code)
	else
		recipeProducts()[product] = code
	end
end

function D.LearnItem(id, name)
	id = tonumber(id)
	local c = cache()
	if not c or not id or id <= 0 or not name or name == "" then
		return
	end
	if recipeSub[id] then
		learnRecipeItem(name, recipeSub[id])
		recipeSub[id] = nil
	end
	if c[id] ~= name then
		c[id] = name
		local lower = name:lower()
		if byName then
			byName[lower] = byName[lower] or id
		end
		local code = recipeProducts()[lower]
		if code then
			recipeProducts()[lower] = nil
			D.SetCraftable(id, code)
		end
		D.Fire("ITEMS", id)
	end
end

-- Names we don't know yet are asked for a few at a time; the game answers
-- with GET_ITEM_INFO_RECEIVED once it has them.
local wanted, wantedList = {}, {}

local function want(id)
	local c = cache()
	if c and not c[id] and not wanted[id] then
		wanted[id] = true
		wantedList[#wantedList + 1] = id
	end
end

local function resolve(id)
	local name = getInfo(id)
	if name then
		wanted[id] = nil
		D.LearnItem(id, name)
		return true
	end
	if C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(id)
	end
end

function D.ItemName(id)
	local c = cache()
	if c and c[id] then
		return c[id]
	end
	local name = getInfo(id)
	if name then
		D.LearnItem(id, name)
		return name
	end
	want(id)
end

-- Every item link in a piece of text.
function D.LearnLinks(text)
	if type(text) ~= "string" then
		return
	end
	for id, name in text:gmatch("|Hitem:(%d+)[^|]*|h%[(.-)%]|h") do
		D.LearnItem(id, name)
	end
end

local function scanBags()
	local slots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local link = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
	if not slots or not link then
		return
	end
	for bag = 0, 4 do
		for slot = 1, slots(bag) or 0 do
			D.LearnLinks(link(bag, slot))
		end
	end
end

-- The game's item list ------------------------------------------------------------
-- The client knows every item, but only by ID. So in the background, a little
-- at a time, we walk the IDs, keep the kinds of items people craft, and ask
-- the game for their names. That runs once (and again after a game patch),
-- and its progress is saved, so it picks up where it left off.

local SCAN_VERSION = 2 -- bump to walk the lists again after a change here
local SCAN_TO = 30000 -- Classic item IDs stop around 24,300
local SPELLS_TO = 60000 -- and recipe spell IDs well before this
local CHECK_PER_FRAME = 150 -- cheap lookups in the client's own data
local SPELLS_PER_FRAME = 300
local IN_FLIGHT = 20 -- names asked of the server at once
local CRAFTED_CLASSES = { [0] = true, [1] = true, [2] = true, [4] = true, [6] = true, [7] = true, [11] = true, [RECIPE_CLASS] = true }

local inFlight, inFlightCount = {}, 0

local function scanState()
	if not DreamscapeDB then
		return nil
	end
	local build = GetBuildInfo and select(4, GetBuildInfo()) or 0
	local st = DreamscapeDB.itemScan
	if not st or st.build ~= build or st.v ~= SCAN_VERSION then
		st = { build = build, v = SCAN_VERSION, next = 1, spell = 1 }
		DreamscapeDB.itemScan = st
	end
	return st
end

local function instant(id)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if fn then
		local itemID, _, _, _, _, classID, subclassID = fn(id)
		return itemID, classID, subclassID
	end
end

-- Profession of a recipe spell, from the modern profession API.
local function recipeProfession(spellID)
	local api = C_TradeSkillUI
	if api and api.GetTradeSkillLineForRecipe then
		local ok, _, lineName, parentID = pcall(api.GetTradeSkillLineForRecipe, spellID)
		if ok and lineName then
			local info = D.PROF_BY_NAME[lineName]
			if not info and parentID and api.GetTradeSkillDisplayName then
				local ok2, parentName = pcall(api.GetTradeSkillDisplayName, parentID)
				info = ok2 and parentName and D.PROF_BY_NAME[parentName]
			end
			if not info then
				for name, i in pairs(D.PROF_BY_NAME) do
					if lineName:find(name, 1, true) then
						info = i
						break
					end
				end
			end
			return info and info.code
		end
	end
end

-- One frame of walking recipe spells: what each one makes.
local function spellStep(st)
	local api = C_TradeSkillUI
	if not (api and api.GetRecipeSchematic) or st.spell > SPELLS_TO then
		return false
	end
	for _ = 1, SPELLS_PER_FRAME do
		local spellID = st.spell
		if spellID > SPELLS_TO then
			break
		end
		st.spell = spellID + 1
		local ok, schematic = pcall(api.GetRecipeSchematic, spellID, false)
		local out = ok and type(schematic) == "table" and schematic.outputItemID
		if out and out > 0 then
			D.SetCraftable(out, recipeProfession(spellID))
			D.ItemName(out)
		end
	end
	return true
end

-- One frame's worth of the walk. Returns false once there's nothing left.
local function scanStep(now)
	local st = scanState()
	if not st or not (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant) then
		return false
	end
	-- Give up on names the server never sent.
	for id, t in pairs(inFlight) do
		local c = cache()
		if (c and c[id]) or now - t > 10 then
			inFlight[id] = nil
			inFlightCount = inFlightCount - 1
		end
	end
	local spells = spellStep(st)
	if st.next > SCAN_TO then
		return spells or inFlightCount > 0
	end
	local c = cache()
	local checked = 0
	while checked < CHECK_PER_FRAME and inFlightCount < IN_FLIGHT and st.next <= SCAN_TO do
		local id = st.next
		st.next = id + 1
		checked = checked + 1
		local exists, classID, subclassID = instant(id)
		if exists and classID == RECIPE_CLASS then
			if c[id] then
				learnRecipeItem(c[id], RECIPE_SUBCLASS[subclassID])
			else
				recipeSub[id] = RECIPE_SUBCLASS[subclassID]
			end
		end
		if exists and CRAFTED_CLASSES[classID] and not c[id] then
			local name = getInfo(id)
			if name then
				D.LearnItem(id, name)
			else
				if C_Item and C_Item.RequestLoadItemDataByID then
					C_Item.RequestLoadItemDataByID(id)
				end
				inFlight[id] = now
				inFlightCount = inFlightCount + 1
				wanted[id] = true
			end
		end
	end
	return true
end
D._scanItemsStep = scanStep

-- How far along the walk is, for /ds items: items read, of how many, and
-- how many craftable items we know (and have names for).
function D.ItemScanProgress()
	local st = scanState()
	local n, named = 0, 0
	local c = cache() or {}
	for id in pairs(crafts() or {}) do
		n = n + 1
		if c[id] then
			named = named + 1
		end
	end
	return st and math.min(st.next - 1, SCAN_TO) or 0, SCAN_TO, n, named
end

-- Recipes ---------------------------------------------------------------------------
-- data.recipes[name] = { guid = , profs = { [code] = { ts = , ids = { [itemID] = true } } } }

local function recipes()
	local data = D.Data()
	if not data then
		return nil
	end
	data.recipes = data.recipes or {}
	return data.recipes
end

-- What the open profession window makes: code, { itemID, ... }.
function D.ScanRecipes()
	local ids, name = {}, nil
	local function add(link)
		local id = link and tonumber(link:match("item:(%d+)"))
		if id then
			ids[#ids + 1] = id
			D.LearnLinks(link)
		end
	end
	-- Classic: the trade skill window (and the craft window, for Enchanting).
	if GetTradeSkillLine and GetNumTradeSkills and GetTradeSkillItemLink then
		local line = GetTradeSkillLine()
		if line and line ~= "" and line ~= "UNKNOWN" then
			name = line
			for i = 1, GetNumTradeSkills() or 0 do
				local _, kind = GetTradeSkillInfo(i)
				if kind ~= "header" and kind ~= "subheader" then
					add(GetTradeSkillItemLink(i))
				end
			end
		end
	end
	if #ids == 0 and GetNumCrafts and GetCraftItemLink and (GetCraftDisplaySkillLine or GetCraftName) then
		local line = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetCraftName and GetCraftName())
		if line and line ~= "" then
			name = line
			for i = 1, GetNumCrafts() or 0 do
				local _, _, kind = GetCraftInfo(i)
				if kind ~= "header" then
					add(GetCraftItemLink(i))
				end
			end
		end
	end
	-- Modern clients.
	if #ids == 0 and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
		pcall(function()
			local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
			name = info and info.professionName or name
			for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
				local r = C_TradeSkillUI.GetRecipeInfo(rid)
				if r and r.learned then
					add(C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(rid))
				end
			end
		end)
	end
	local prof = name and D.PROF_BY_NAME[name]
	return prof and prof.code, ids
end

-- How many item IDs fit in one message after the other fields.
local PER_MESSAGE = 24

function D.SendRecipes(name)
	local all = recipes()
	local entry = all and all[name]
	if not entry then
		return
	end
	for code, r in pairs(entry.profs) do
		local list = {}
		for id in pairs(r.ids) do
			list[#list + 1] = id
		end
		table.sort(list)
		for i = 1, #list, PER_MESSAGE do
			D.Send("K", name, code, r.ts, entry.guid or "", table.concat(list, ",", i, math.min(#list, i + PER_MESSAGE - 1)))
		end
	end
end

-- Add what someone's recipes make. Returns true if anything was new.
-- A newer `ts` replaces the list (they re-shared it); the same `ts` adds to
-- it (the rest of a list that took several messages).
local function storeRecipes(name, code, ts, guid, ids)
	local all = recipes()
	if not all or not D.PROF_BY_CODE[code] then
		return false
	end
	guid = guid ~= "" and guid or nil
	if guid then
		-- Same character under another spelling of their name.
		for key, e in pairs(all) do
			if key ~= name and e.guid == guid then
				all[name] = all[name] or e
				all[key] = nil
			end
		end
	end
	local entry = all[name] or { profs = {} }
	all[name] = entry
	entry.guid = guid or entry.guid
	local r = entry.profs[code]
	if r and r.ts > ts then
		return false
	end
	if not r or r.ts < ts then
		r = { ts = ts, ids = {} }
		entry.profs[code] = r
	end
	local new = false
	for _, id in ipairs(ids) do
		if not r.ids[id] then
			r.ids[id] = true
			new = true
		end
		D.SetCraftable(id, code)
		D.ItemName(id)
	end
	if new then
		D.Fire("RECIPES", name)
	end
	return new
end

-- Read our open profession window and share it if it taught us anything.
-- Recipes are never forgotten, so what we've seen before is kept even when
-- a collapsed section hides it.
function D.UpdateMyRecipes()
	local code, ids = D.ScanRecipes()
	local all = recipes()
	if not code or #ids == 0 or not all then
		return
	end
	local me = D.Me()
	local mine = all[me]
	local old = mine and mine.profs[code]
	local list = {}
	for id in pairs(old and old.ids or {}) do
		list[#list + 1] = id
	end
	local grew = false
	for _, id in ipairs(ids) do
		if not (old and old.ids[id]) then
			list[#list + 1] = id
			grew = true
		end
	end
	if grew then
		storeRecipes(me, code, math.max(D.Now(), old and old.ts + 1 or 0), D.MyGUID() or "", list)
		D.SendRecipes(me)
	end
end

-- K <name> <code> <time> <guid> <id,id,...>
D.Handle("K", function(f)
	local name, code, ts = D.FullName(f[2]), f[3], tonumber(f[4])
	if not name or not ts then
		return
	end
	local ids = {}
	for id in (f[6] or ""):gmatch("%d+") do
		ids[#ids + 1] = tonumber(id)
	end
	storeRecipes(name, code, ts, f[5] or "", ids)
end)
D._storeRecipes = storeRecipes

-- Who can make this item: { { name, code }, ... }
function D.WhoCanMake(id)
	local out = {}
	for name, e in pairs(recipes() or {}) do
		for code, r in pairs(e.profs) do
			if r.ids[id] then
				out[#out + 1] = { name, code }
			end
		end
	end
	table.sort(out, function(a, b)
		return a[1] < b[1]
	end)
	return out
end

-- Searching --------------------------------------------------------------------------

-- Craftable items whose names contain `text`, best first: things the guild
-- can craft, then names that start with it, then the rest.
function D.SearchItems(text, limit)
	limit = limit or 8
	local out = {}
	text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if #text < 2 then
		return out
	end
	local makeable = {}
	for _, e in pairs(recipes() or {}) do
		for _, r in pairs(e.profs) do
			for id in pairs(r.ids) do
				makeable[id] = true
			end
		end
	end
	local craftable = crafts() or {}
	for id, name in pairs(cache() or {}) do
		local at = craftable[id] and name:lower():find(text, 1, true)
		if at then
			out[#out + 1] = { id = id, name = name, craft = makeable[id] or false, prefix = at == 1 }
		end
	end
	table.sort(out, function(a, b)
		if a.craft ~= b.craft then
			return a.craft
		end
		if a.prefix ~= b.prefix then
			return a.prefix
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	for i = #out, limit + 1, -1 do
		out[i] = nil
	end
	return out
end

-- The craftable item a typed name means, if we know one by exactly that name.
function D.FindItem(text)
	text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end
	local craftable = crafts() or {}
	for id, name in pairs(cache() or {}) do
		if craftable[id] and name:lower() == text then
			return id, name
		end
	end
	local name, link = getInfo(text)
	local id = link and tonumber(link:match("item:(%d+)"))
	if id and craftable[id] then
		D.LearnItem(id, name)
		return id, name
	end
end

-- Events -------------------------------------------------------------------------------

local CHAT_EVENTS = {
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
	"CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS",
}
local TRADE_EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }
local TRADE = {}
for _, e in ipairs(TRADE_EVENTS) do
	TRADE[e] = true
end

local ev = CreateFrame("Frame")
for _, e in ipairs(CHAT_EVENTS) do
	D.RegisterEvents(ev, e)
end
for _, e in ipairs(TRADE_EVENTS) do
	D.RegisterEvents(ev, e) -- the CRAFT_ ones are Classic only
end
D.RegisterEvents(ev, "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED")

local recipeScan, bagScan = false, false
ev:SetScript("OnEvent", function(_, event, a1)
	if not D.InDreamscape() then
		return
	end
	if event == "GET_ITEM_INFO_RECEIVED" then
		local id = tonumber(a1)
		if id and wanted[id] then
			resolve(id)
		end
	elseif TRADE[event] then
		-- The window fires these in bursts while it fills in.
		if not recipeScan and C_Timer then
			recipeScan = true
			C_Timer.After(1, function()
				recipeScan = false
				D.UpdateMyRecipes()
			end)
		end
	elseif event == "BAG_UPDATE_DELAYED" then
		if not bagScan and C_Timer then
			bagScan = true
			C_Timer.After(5, function()
				bagScan = false
				scanBags()
			end)
		end
	else
		D.LearnLinks(a1)
	end
end)

-- Ask for a few unknown names each frame rather than hundreds at once.
local scanning = false
local clock = 0
ev:SetScript("OnUpdate", function(_, elapsed)
	clock = clock + (elapsed or 0)
	if scanning then
		scanning = scanStep(clock)
	end
	for _ = 1, 5 do
		local id = table.remove(wantedList, 1)
		if not id then
			return
		end
		if wanted[id] then
			resolve(id)
		end
	end
end)

D.On("GUILD", function(member)
	if member then
		scanning = true
		scanBags()
		local data = D.Data()
		for _, o in pairs(data and data.orders or {}) do
			if o.itemID and o.itemID > 0 then
				if o.itemName ~= "" then
					D.LearnItem(o.itemID, o.itemName)
				end
			end
		end
	end
end)

-- Items on orders we hear about are worth knowing too.
D.On("ORDERS", function(id)
	local o = D.GetOrder(id)
	if o and o.itemID and o.itemID > 0 and o.itemName ~= "" then
		D.LearnItem(o.itemID, o.itemName)
	end
end)

D.Command("items", function()
	local done, total, craftable, named = D.ItemScanProgress()
	D.print(("knows %d craftable items, %d with names so far (read %d of %d item IDs)."):format(craftable, named, done, total))
end, "/ds items - how many items the order form can suggest")
