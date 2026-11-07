-- Pidge's Forever Guild: guild members' professions. Each member's addon reads their own
-- professions and shares them with the guild; everyone keeps what they hear,
-- so you can see a member's professions even while they're offline. Shown in
-- a panel under the member details on the guild roster.

local ADDON, ns = ...
local D = ns.D

-- code, English name (as the skill window names it), icon
D.PROFESSIONS = {
	{ "AL", "Alchemy", "Interface\\Icons\\Trade_Alchemy" },
	{ "BS", "Blacksmithing", "Interface\\Icons\\Trade_BlackSmithing" },
	{ "EN", "Enchanting", "Interface\\Icons\\Trade_Engraving" },
	{ "EG", "Engineering", "Interface\\Icons\\Trade_Engineering" },
	{ "HB", "Herbalism", "Interface\\Icons\\Trade_Herbalism" },
	{ "LW", "Leatherworking", "Interface\\Icons\\Trade_LeatherWorking" },
	{ "MN", "Mining", "Interface\\Icons\\Trade_Mining" },
	{ "SK", "Skinning", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ "TL", "Tailoring", "Interface\\Icons\\Trade_Tailoring" },
	{ "JC", "Jewelcrafting", "Interface\\Icons\\INV_Misc_Gem_01" },
	{ "IN", "Inscription", "Interface\\Icons\\INV_Inscription_Tradeskill01" },
	{ "CK", "Cooking", "Interface\\Icons\\INV_Misc_Food_15" },
	{ "FA", "First Aid", "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
	{ "FI", "Fishing", "Interface\\Icons\\Trade_Fishing" },
}
local BY_CODE, BY_NAME = {}, {}
for i, p in ipairs(D.PROFESSIONS) do
	local info = { code = p[1], name = p[2], icon = p[3], order = i }
	BY_CODE[p[1]] = info
	BY_NAME[p[2]] = info
end
D.PROF_BY_CODE = BY_CODE
D.PROF_BY_NAME = BY_NAME

-- Professions that make things people can order.
D.CRAFTING = { "AL", "BS", "EN", "EG", "LW", "TL", "JC", "IN", "CK", "FA" }

-- Reading our own -----------------------------------------------------------------

-- Returns a list of { code, rank, max }.
function D.ScanProfessions()
	local list, seen = {}, {}
	local function add(name, rank, max)
		local info = name and BY_NAME[name]
		if info and not seen[info.code] then
			seen[info.code] = true
			list[#list + 1] = { info.code, rank or 0, max or 0 }
		end
	end
	-- Classic: the skill list (Character > Skills). Collapsed sections hide
	-- their skills, so open any that are closed first.
	if GetNumSkillLines and GetSkillLineInfo then
		if ExpandSkillHeader then
			for i = GetNumSkillLines(), 1, -1 do
				local _, isHeader, isExpanded = GetSkillLineInfo(i)
				if isHeader and not isExpanded then
					ExpandSkillHeader(i)
				end
			end
		end
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
			if not isHeader then
				add(name, rank, max)
			end
		end
	end
	-- Modern clients: the professions API.
	if GetProfessions and GetProfessionInfo then
		for _, idx in pairs({ GetProfessions() }) do
			if idx then
				local name, _, rank, max = GetProfessionInfo(idx)
				add(name, rank, max)
			end
		end
	end
	table.sort(list, function(a, b)
		return BY_CODE[a[1]].order < BY_CODE[b[1]].order
	end)
	return list
end

local function encode(list)
	local parts = {}
	for i, p in ipairs(list) do
		parts[i] = p[1] .. ":" .. p[2] .. ":" .. p[3]
	end
	return table.concat(parts, ",")
end
D._encodeProfs = encode

local function decode(s)
	local list = {}
	for code, rank, max in (s or ""):gmatch("(%u%u):(%d+):(%d+)") do
		if BY_CODE[code] then
			list[#list + 1] = { code, tonumber(rank), tonumber(max) }
		end
	end
	return list
end
D._decodeProfs = decode

-- The guild's professions ----------------------------------------------------

-- Names aren't reliable here: on WoW Forever the roster shows "First Last"
-- while the game tells the addon just "First". So each entry also keeps the
-- character's GUID, which is the same everywhere, and lookups try that first.

local function byGUID(profs, guid)
	if not guid or guid == "" then
		return nil
	end
	for key, entry in pairs(profs) do
		if entry.guid == guid then
			return entry, key
		end
	end
end

-- What we know about a member: { ts = time, list = {...}, guid = } or nil.
function D.GetProfessions(name, guid)
	local data = D.Data()
	if not data then
		return nil
	end
	return byGUID(data.profs, guid) or (name and data.profs[D.FullName(name)])
end

local function store(name, ts, list, guid)
	local data = D.Data()
	if not data then
		return false
	end
	guid = guid ~= "" and guid or nil
	local old, oldKey = byGUID(data.profs, guid)
	old = old or data.profs[name]
	if old and old.ts >= ts and (oldKey or name) == name then
		return false
	end
	if old and old.ts > ts then
		return false
	end
	if oldKey and oldKey ~= name then
		data.profs[oldKey] = nil -- same character under another spelling
	end
	data.profs[name] = { ts = ts, list = list, guid = guid or (old and old.guid) }
	D.Fire("PROFESSIONS", name, guid)
	return true
end

function D.SendProfessions(name)
	local entry = D.GetProfessions(name)
	if entry then
		D.Send("P", name, entry.ts, encode(entry.list), entry.guid or "")
	end
end

-- Re-read ours and tell the guild if anything changed (or if asked to).
function D.UpdateMyProfessions(force)
	local data = D.Data()
	if not data then
		return
	end
	local list = D.ScanProfessions()
	local me, guid = D.Me(), D.MyGUID()
	-- Drop what an older version saved under our name as UnitName spells it.
	local guess = D.FullName(UnitName("player"))
	if guess ~= me and data.profs[guess] and not data.profs[guess].guid then
		data.profs[guess] = nil
	end
	local old, oldKey = byGUID(data.profs, guid)
	old = old or data.profs[me]
	if force or not old or oldKey ~= me or encode(old.list) ~= encode(list) then
		store(me, math.max(D.Now(), old and old.ts + 1 or 0), list, guid)
		D.SendProfessions(me)
	end
end

-- P <name> <time> <AL:250:300,...> <guid>
D.Handle("P", function(f)
	local name, ts = f[2], tonumber(f[3])
	if name and name ~= "" and ts then
		store(D.FullName(name), ts, decode(f[4]), f[5])
	end
end)

-- Once we learn how the server spells our name, file ours under it.
D.On("ME", function()
	D.UpdateMyProfessions()
end)

-- Members who know a profession, best first: { { name, rank, max }, ... }
function D.Crafters(code)
	local out = {}
	local data = D.Data()
	if not data then
		return out
	end
	for name, entry in pairs(data.profs) do
		for _, p in ipairs(entry.list) do
			if p[1] == code then
				out[#out + 1] = { name, p[2], p[3] }
			end
		end
	end
	table.sort(out, function(a, b)
		if a[2] ~= b[2] then
			return a[2] > b[2]
		end
		return a[1] < b[1]
	end)
	return out
end

local scanPending = false
local ev = CreateFrame("Frame")
D.RegisterEvents(ev, "SKILL_LINES_CHANGED", "PLAYER_GUILD_UPDATE")
ev:SetScript("OnEvent", function()
	-- Skill changes come in bursts (every skill-up), so wait a moment.
	if scanPending or not C_Timer then
		return
	end
	scanPending = true
	C_Timer.After(10, function()
		scanPending = false
		D.UpdateMyProfessions()
	end)
end)

D.On("GUILD", function(member)
	if member and C_Timer then
		C_Timer.After(6, function()
			D.UpdateMyProfessions(true)
		end)
	end
end)

-- The roster panel -------------------------------------------------------------

local panel
local ROW = 18

local function ago(ts)
	local s = math.max(0, D.Now() - ts)
	if s < 3600 then
		return "just now"
	elseif s < 86400 then
		return ("%d h ago"):format(s / 3600)
	end
	return ("%d days ago"):format(s / 86400)
end

local function usable(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return type(v) == "string" and v ~= "" and v or nil
end

local function memberGUID(memberInfo)
	local guid
	pcall(function()
		guid = usable(memberInfo and memberInfo.guid)
	end)
	return guid
end

local function memberName(detail, memberInfo)
	local name
	pcall(function()
		name = usable(memberInfo and memberInfo.name)
	end)
	if not name then
		pcall(function()
			name = usable(detail.Name:GetText())
		end)
	end
	return name and D.FullName(name)
end

local function createPanel(detail)
	local p = CreateFrame("Frame", "PFGMemberProfessions", detail)
	p:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, 2)
	p:SetPoint("TOPRIGHT", detail, "BOTTOMRIGHT", 0, 2)
	p:SetHeight(60)
	p:EnableMouse(true)
	p:SetFrameLevel(detail:GetFrameLevel())

	local bg = p:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 8, -4)
	bg:SetPoint("BOTTOMRIGHT", -2, 4)
	bg:SetColorTexture(0, 0, 0, 0.8)
	-- Same border as the member details above it.
	local ok, border = pcall(CreateFrame, "Frame", nil, p, "DialogBorderDarkTemplate")
	if ok and border then
		border:SetPoint("TOPLEFT", 4, 0)
		border:SetPoint("BOTTOMRIGHT", 6, 1)
	end

	p.title = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 18, -14)
	p.title:SetText("Professions")

	p.note = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	p.note:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -6)
	p.note:SetPoint("RIGHT", p, "RIGHT", -14, 0)
	p.note:SetJustifyH("LEFT")

	p.rows = {}
	for i = 1, #D.PROFESSIONS do
		local r = CreateFrame("Frame", nil, p)
		r:SetSize(170, ROW)
		r:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4 - (i - 1) * ROW)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(14, 14)
		r.icon:SetPoint("LEFT")
		r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
		r.rank = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		r.rank:SetPoint("RIGHT", p, "RIGHT", -16, 0)
		r.rank:SetPoint("TOP", r, "TOP", 0, -3)
		r:Hide()
		p.rows[i] = r
	end
	return p
end

-- Is this us? The roster may leave off the realm, or add a surname.
function D.IsMe(name, guid)
	if guid then
		return guid == D.MyGUID()
	end
	if not name then
		return false
	end
	local base, mine = name:gsub("%-.*$", ""), UnitName("player")
	return name == D.Me() or base == mine or base:match("^(%S+) ") == mine
end

function D.ShowMemberProfessions(detail, name, guid)
	if not D.InGuild() then
		if panel then
			panel:Hide()
		end
		return
	end
	panel = panel or createPanel(detail)
	if D.IsMe(name, guid) then
		-- Always show our own as they are right now.
		name, guid = D.Me(), D.MyGUID()
		D.UpdateMyProfessions()
	end
	panel.name, panel.guid = name, guid
	local entry = (name or guid) and D.GetProfessions(name, guid)
	for _, r in ipairs(panel.rows) do
		r:Hide()
	end
	local lines = 0
	if entry and #entry.list > 0 then
		for i, prof in ipairs(entry.list) do
			local info, r = BY_CODE[prof[1]], panel.rows[i]
			r.icon:SetTexture(info.icon)
			r.name:SetText(info.name)
			r.rank:SetText(("%d / %d"):format(prof[2], prof[3]))
			r:Show()
		end
		lines = #entry.list
		panel.note:ClearAllPoints()
		panel.note:SetPoint("TOPLEFT", panel.rows[lines], "BOTTOMLEFT", 0, -6)
		panel.note:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
		panel.note:SetText(D.IsMe(name, guid) and "" or ("Updated " .. ago(entry.ts)))
	else
		panel.note:ClearAllPoints()
		panel.note:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
		panel.note:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
		if entry then
			panel.note:SetText("No professions.")
		else
			panel.note:SetText("Unknown. They need Pidge's Forever Guild AddOn, and to log in once with it.")
		end
	end
	local noteH = (panel.note:GetText() or "") == "" and 0 or (panel.note:GetStringHeight() or 12) + 6
	panel:SetHeight(42 + lines * ROW + noteH)
	panel:Show()
end

D.OnGuildPanel(function()
	local detail = CommunitiesFrame.GuildMemberDetailFrame
	if not detail or not detail.DisplayMember then
		return
	end
	-- The panel is a child of the details frame, so it hides along with it.
	hooksecurefunc(detail, "DisplayMember", function(self, _, memberInfo)
		D.ShowMemberProfessions(self, memberName(self, memberInfo), memberGUID(memberInfo))
	end)
end)

D.On("GUILD", function(member)
	if panel and not member then
		panel:Hide()
	end
end)

D.On("PROFESSIONS", function(name, guid)
	if panel and panel:IsVisible() and (panel.name == name or (guid and panel.guid == guid)) then
		D.ShowMemberProfessions(panel:GetParent(), panel.name, panel.guid)
	end
end)

-- /pfg profs: what the addon sees, for troubleshooting.
D.Command("profs", function()
	local apis = {}
	if GetSkillLineInfo then
		apis[#apis + 1] = ("skill list (%d lines)"):format(GetNumSkillLines and GetNumSkillLines() or 0)
	end
	if GetProfessions then
		apis[#apis + 1] = "professions API"
	end
	D.print("reading from: " .. (#apis > 0 and table.concat(apis, ", ") or "nothing!"))
	local list = D.ScanProfessions()
	local parts = {}
	for i, p in ipairs(list) do
		parts[i] = ("%s %d/%d"):format(BY_CODE[p[1]].name, p[2], p[3])
	end
	D.print("you have: " .. (#parts > 0 and table.concat(parts, ", ") or "none found"))
	if not D.Data() then
		D.print("guild not loaded yet (" .. (IsInGuild() and "in a guild" or "not in a guild") .. "), so nothing is saved.")
		return
	end
	D.UpdateMyProfessions(true)
	local n = 0
	for _ in pairs(D.Data().profs) do
		n = n + 1
	end
	D.print(("saved as %s; know professions for %d member(s)."):format(D.Me(), n))
end, "/pfg profs - check what professions the addon can see")
