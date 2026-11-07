-- Pidge's Forever Guild: guild crafting orders. Orders live in every member's saved data
-- and travel over guild addon messages, so anyone with the addon sees the same
-- board, even for members who are offline.
--
-- An order goes open -> accepted (a crafter took it) -> done, or cancelled.
-- The requester can change anything about their own order; anyone can accept
-- an open order; the crafter who accepted it can give it back or mark it done.

local ADDON, ns = ...
local D = ns.D

D.STATUS = { OPEN = "open", ACCEPTED = "accepted", DONE = "done", CANCELLED = "cancelled" }
local S = D.STATUS
local VALID_STATUS = { open = true, accepted = true, done = true, cancelled = true }

local MAX_NOTE = 60
local KEEP_FINISHED = 14 * 86400 -- done/cancelled orders are forgotten after this
local KEEP_ANY = 60 * 86400

-- Wire format ---------------------------------------------------------------------
-- <kind> id requester itemID itemName qty prof tip status crafter created updated rev note

local FIELDS = { "id", "requester", "itemID", "itemName", "qty", "prof", "tip", "status", "crafter", "created", "updated", "rev", "note" }
local NUMBERS = { itemID = true, qty = true, tip = true, created = true, updated = true, rev = true }

local function toFields(o)
	local out = {}
	for i, k in ipairs(FIELDS) do
		out[i] = o[k] or ""
	end
	return out
end

local function fromFields(f)
	local o = {}
	for i, k in ipairs(FIELDS) do
		local v = f[i + 1]
		if NUMBERS[k] then
			v = tonumber(v) or 0
		end
		o[k] = v
	end
	if o.crafter == "" then
		o.crafter = nil
	end
	if not o.id or o.id == "" or not o.requester or o.requester == "" or not VALID_STATUS[o.status] then
		return nil
	end
	o.qty = math.max(1, o.qty)
	o.note = (o.note or ""):sub(1, MAX_NOTE)
	return o
end
D._orderFromFields = fromFields

local function send(kind, o, isBulk)
	(isBulk and D.SendBulk or D.Send)(kind, unpack(toFields(o)))
end

-- Storage -------------------------------------------------------------------------

local function orders()
	local data = D.Data()
	return data and data.orders
end

function D.GetOrder(id)
	local all = orders()
	return all and all[id]
end

-- All orders, newest first.
function D.Orders()
	local list = {}
	for _, o in pairs(orders() or {}) do
		list[#list + 1] = o
	end
	table.sort(list, function(a, b)
		if a.created ~= b.created then
			return a.created > b.created
		end
		return a.id > b.id
	end)
	return list
end

-- Is `new` a later version of `old`? Higher rev wins; if two people accept
-- the same order at once, the alphabetically first crafter wins everywhere.
local function newer(new, old)
	if not old then
		return true
	end
	if new.rev ~= old.rev then
		return new.rev > old.rev
	end
	return new.status == S.ACCEPTED and old.status == S.ACCEPTED and (new.crafter or "") < (old.crafter or "")
end

-- May `sender` make this change? (Only for live changes, not sync relays.)
local function allowed(sender, new, old)
	if old and old.requester ~= new.requester then
		return false
	end
	if sender == new.requester then
		return true
	end
	if not old then
		return false
	end
	if old.status == S.OPEN and new.status == S.ACCEPTED and new.crafter == sender then
		return true
	end
	if old.status == S.ACCEPTED and old.crafter == sender then
		return (new.status == S.OPEN and not new.crafter) or (new.status == S.DONE and new.crafter == sender)
	end
	-- Two crafters accepted at once: let the tie-break settle it.
	return old.status == S.ACCEPTED and new.status == S.ACCEPTED and new.crafter == sender and new.rev == old.rev
end

local function notify(old, new, by)
	local me = D.Me()
	local item = new.itemName ~= "" and new.itemName or "your order"
	if new.requester == me and by ~= me then
		if new.status == S.ACCEPTED and (not old or old.status ~= S.ACCEPTED) then
			D.print(("%s accepted your order for %s."):format(D.Short(new.crafter), item))
		elseif new.status == S.DONE and (not old or old.status ~= S.DONE) then
			D.print(("%s finished your order for %s."):format(D.Short(by), item))
		elseif new.status == S.OPEN and old and old.status == S.ACCEPTED then
			D.print(("%s gave your order for %s back; it's open again."):format(D.Short(by), item))
		end
	elseif old and old.crafter == me and by ~= me and new.status == S.CANCELLED then
		D.print(("%s cancelled their order for %s."):format(D.Short(by), item))
	end
end

-- Take in an order from a message. Returns true if it changed anything.
function D.ReceiveOrder(o, sender, relayed)
	local all = orders()
	if not all or not o then
		return false
	end
	local old = all[o.id]
	if not newer(o, old) then
		return false
	end
	if not relayed and not allowed(sender, o, old) then
		return false
	end
	all[o.id] = o
	if not relayed then
		notify(old, o, sender)
	end
	D.Fire("ORDERS", o.id)
	return true
end

-- O = a live change, R = a copy sent during a sync.
D.Handle("O", function(f, sender)
	D.ReceiveOrder(fromFields(f), sender, false)
end)
D.Handle("R", function(f, sender)
	D.ReceiveOrder(fromFields(f), sender, true)
end)

-- Making changes ------------------------------------------------------------------

local function commit(o)
	o.rev = (o.rev or 0) + 1
	o.updated = D.Now()
	orders()[o.id] = o
	D.Fire("ORDERS", o.id)
	send("O", o)
	return o
end

local function copy(o)
	local c = {}
	for k, v in pairs(o) do
		c[k] = v
	end
	return c
end

-- D.PlaceOrder{ itemID=, itemName=, qty=, prof=, tip= (copper), note= }
function D.PlaceOrder(t)
	if not orders() then
		return nil, "You need to be in a guild."
	end
	local name = t.itemName and t.itemName:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if (t.itemID or 0) == 0 and name == "" then
		return nil, "Pick an item: type its name or shift-click it."
	end
	local now = D.Now()
	local me = D.Me()
	return commit({
		id = ("%s:%d:%d"):format(me, now, math.random(100, 999)),
		requester = me,
		itemID = t.itemID or 0,
		itemName = name,
		qty = math.max(1, math.floor(tonumber(t.qty) or 1)),
		prof = D.PROF_BY_CODE[t.prof or ""] and t.prof or "",
		tip = math.max(0, math.floor(tonumber(t.tip) or 0)),
		status = S.OPEN,
		created = now,
		rev = 0,
		note = (t.note or ""):sub(1, MAX_NOTE),
	}), nil
end

local function change(id, check, apply)
	local o = D.GetOrder(id)
	if not o then
		return nil, "That order is gone."
	end
	local err = check(o)
	if err then
		return nil, err
	end
	local c = copy(o)
	apply(c)
	return commit(c), nil
end

function D.AcceptOrder(id)
	return change(id, function(o)
		if o.status ~= S.OPEN then
			return "Someone already took that order."
		end
	end, function(o)
		o.status, o.crafter = S.ACCEPTED, D.Me()
	end)
end

function D.AbandonOrder(id)
	return change(id, function(o)
		if o.status ~= S.ACCEPTED or o.crafter ~= D.Me() then
			return "That isn't your order to give back."
		end
	end, function(o)
		o.status, o.crafter = S.OPEN, nil
	end)
end

function D.CompleteOrder(id)
	return change(id, function(o)
		local me = D.Me()
		if o.status ~= S.ACCEPTED or (o.crafter ~= me and o.requester ~= me) then
			return "Only the crafter or the requester can finish an accepted order."
		end
	end, function(o)
		o.status = S.DONE
	end)
end

function D.CancelOrder(id)
	return change(id, function(o)
		if o.requester ~= D.Me() then
			return "Only the requester can cancel an order."
		elseif o.status == S.DONE or o.status == S.CANCELLED then
			return "That order is already finished."
		end
	end, function(o)
		o.status = S.CANCELLED
	end)
end

-- Sync ----------------------------------------------------------------------------
-- When someone logs in they ask the guild for what changed since their last
-- sync ("S" <since>; 0 = everything). One member answers: each waits a random
-- moment, and the first to start announces it ("D") so the others stand down.
-- The answer is the orders ("R"), members' professions ("P") and what their
-- recipes make ("K") that changed after <since>, sent as bulk traffic so live
-- changes go first.

local pending = {} -- requester -> since, while we're waiting to answer them
local MARGIN = 600 -- ask from a bit before the last sync, in case clocks or a message lagged

-- full: ask for everything, not just what changed.
function D.RequestSync(full)
	local data = D.Data()
	if not data then
		return
	end
	local since = 0
	if not full and data.lastSync then
		since = math.max(0, data.lastSync - MARGIN)
	end
	D.Send("S", since)
end

local function answer(requester)
	local since = pending[requester]
	if not since then
		return
	end
	pending[requester] = nil
	D.Send("D", requester)
	for _, o in pairs(orders() or {}) do
		if (o.updated or o.created or 0) > since then
			send("R", o, true)
		end
	end
	local data = D.Data()
	for name in pairs(data and data.profs or {}) do
		D.SendProfessions(name, since)
	end
	for name in pairs(data and data.recipes or {}) do
		D.SendRecipes(name, since)
	end
end
D._answerSync = answer

D.Handle("S", function(f, sender)
	if not orders() then
		return
	end
	local since = tonumber(f[2]) or 0
	pending[sender] = math.min(pending[sender] or since, since)
	local wait = 1 + math.random() * 4
	if C_Timer then
		C_Timer.After(wait, function()
			answer(sender)
		end)
	end
end)

D.Handle("D", function(f)
	local requester = D.FullName(f[2]) or ""
	pending[requester] = nil
	-- Someone is answering our sync: next time we only need what changed after now.
	if requester == D.Me() then
		local data = D.Data()
		if data then
			data.lastSync = D.Now()
		end
	end
end)

function D.PruneOrders()
	local all = orders()
	if not all then
		return
	end
	local now = D.Now()
	for id, o in pairs(all) do
		local age = now - (o.updated or 0)
		if age > KEEP_ANY or ((o.status == S.DONE or o.status == S.CANCELLED) and age > KEEP_FINISHED) then
			all[id] = nil
		end
	end
end

-- Once we know we're in the guild (at login, or a moment later).
D.On("GUILD", function(member)
	if member and C_Timer then
		C_Timer.After(8, function()
			D.PruneOrders()
			D.RequestSync()
		end)
	end
end)

D.Command("sync", function()
	D.RequestSync(true)
	D.print("asked the guild for the latest orders and professions.")
end, "/pfg sync - fetch the latest orders and professions from the guild")
