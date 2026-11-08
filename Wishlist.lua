-- Pidge's Forever Guild: the guild wishlist. Members list items they want or
-- need; everyone with the addon can see the list. Wishes travel and sync just
-- like crafting orders (Orders.lua): live changes go out at once, and the
-- login/fingerprint sync carries the rest.
--
-- Only the member who made a wish can change it; officers can remove anyone's.

local ADDON, ns = ...
local D = ns.D

local MAX_NOTE = 60
local MAX_PER_PLAYER = 30
local KEEP_REMOVED = 14 * 86400
local KEEP_OPEN = 90 * 86400

-- Wire format: <kind> id owner itemID itemName qty note status created updated rev
local FIELDS = { "id", "owner", "itemID", "itemName", "qty", "note", "status", "created", "updated", "rev" }
local NUMBERS = { itemID = true, qty = true, created = true, updated = true, rev = true }
local VALID = { open = true, removed = true }

local function toFields(w)
	local out = {}
	for i, k in ipairs(FIELDS) do
		out[i] = w[k] or ""
	end
	return out
end

local function fromFields(f)
	local w = {}
	for i, k in ipairs(FIELDS) do
		local v = f[i + 1]
		if NUMBERS[k] then
			v = tonumber(v) or 0
		end
		w[k] = v
	end
	if not w.id or w.id:sub(1, 2) ~= "w:" or not w.owner or w.owner == "" or not VALID[w.status] then
		return nil
	end
	w.qty = math.max(1, w.qty)
	w.note = (w.note or ""):sub(1, MAX_NOTE)
	return w
end
D._wishFromFields = fromFields

local function wishes()
	local data = D.Data()
	if not data then
		return nil
	end
	data.wishes = data.wishes or {}
	return data.wishes
end

local function send(kind, w, bulk)
	(bulk and D.SendBulk or D.Send)(kind, unpack(toFields(w)))
end

D.RegisterSynced(wishes, function(w)
	send("WJ", w, true)
end)

function D.GetWish(id)
	local all = wishes()
	return all and all[id]
end

-- Open wishes, newest first. owner: only that member's.
function D.Wishes(owner)
	local list = {}
	for _, w in pairs(wishes() or {}) do
		if w.status == "open" and (not owner or w.owner == owner) then
			list[#list + 1] = w
		end
	end
	table.sort(list, function(a, b)
		if a.created ~= b.created then
			return a.created > b.created
		end
		return a.id > b.id
	end)
	return list
end

-- Receiving ------------------------------------------------------------------------

local function allowed(sender, new, old)
	if old and old.owner ~= new.owner then
		return false
	end
	if sender == new.owner then
		return true
	end
	return old ~= nil and old.status == "open" and new.status == "removed" and D.IsOfficer(sender)
end

function D.ReceiveWish(w, sender, relayed)
	local all = wishes()
	if not all or not w then
		return false
	end
	local old = all[w.id]
	if old and (old.rev or 0) >= (w.rev or 0) then
		return false
	end
	if not relayed and not allowed(sender, w, old) then
		return false
	end
	all[w.id] = w
	if not relayed and w.owner == D.Me() and sender ~= D.Me() and w.status == "removed" then
		D.print(("%s removed %s from your wishlist."):format(D.Short(sender), w.itemName ~= "" and w.itemName or "an item"))
	end
	D.Fire("WISHES", w.id)
	return true
end

-- WI = a live change, WJ = a copy sent during a sync.
D.Handle("WI", function(f, sender)
	D.ReceiveWish(fromFields(f), sender, false)
end)
D.Handle("WJ", function(f, sender)
	D.ReceiveWish(fromFields(f), sender, true)
end)

-- Making changes -------------------------------------------------------------------

local function commit(w)
	w.rev = (w.rev or 0) + 1
	w.updated = D.Now()
	wishes()[w.id] = w
	D.Fire("WISHES", w.id)
	send("WI", w)
	return w
end

-- D.AddWish{ itemID=, itemName=, qty=, note= }
function D.AddWish(t)
	if not wishes() then
		return nil, "You need to be in a guild."
	end
	local name = (t.itemName or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if (t.itemID or 0) == 0 and name == "" then
		return nil, "Pick an item: type its name or shift-click it."
	end
	local me = D.Me()
	if #D.Wishes(me) >= MAX_PER_PLAYER then
		return nil, ("Your wishlist is full (%d items). Remove something first."):format(MAX_PER_PLAYER)
	end
	local now = D.Now()
	return commit({
		id = ("w:%s:%d:%d"):format(me, now, math.random(100000, 999999)),
		owner = me,
		itemID = t.itemID or 0,
		itemName = name,
		qty = math.max(1, math.floor(tonumber(t.qty) or 1)),
		note = (t.note or ""):sub(1, MAX_NOTE),
		status = "open",
		created = now,
		rev = 0,
	}), nil
end

function D.CanRemoveWish(w)
	return w and w.status == "open" and (w.owner == D.Me() or D.IsOfficer())
end

function D.RemoveWish(id)
	local w = D.GetWish(id)
	if not w then
		return nil, "That wish is gone."
	elseif not D.CanRemoveWish(w) then
		return nil, "Only its owner or an officer can remove that."
	end
	local c = {}
	for k, v in pairs(w) do
		c[k] = v
	end
	c.status = "removed"
	return commit(c), nil
end

function D.PruneWishes()
	local all = wishes()
	if not all then
		return
	end
	local now = D.Now()
	for id, w in pairs(all) do
		local age = now - (w.updated or 0)
		if age > KEEP_OPEN or (w.status == "removed" and age > KEEP_REMOVED) then
			all[id] = nil
		end
	end
end

D.On("GUILD", function(member)
	if member then
		D.PruneWishes()
	end
end)
