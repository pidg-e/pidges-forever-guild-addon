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
	-- Officers and up may remove anyone's unfinished order.
	if new.status == S.CANCELLED and (old.status == S.OPEN or old.status == S.ACCEPTED) and D.IsOfficer(sender) then
		return true
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
	if new.requester == me and by ~= me and new.status == S.CANCELLED and old and old.status ~= S.CANCELLED then
		D.print(("%s removed your order for %s."):format(D.Short(by), item))
	elseif new.requester == me and by ~= me then
		if new.status == S.ACCEPTED and (not old or old.status ~= S.ACCEPTED) then
			D.print(("%s accepted your order for %s."):format(D.Short(new.crafter), item))
		elseif new.status == S.DONE and (not old or old.status ~= S.DONE) then
			D.print(("%s finished your order for %s."):format(D.Short(by), item))
		elseif new.status == S.OPEN and old and old.status == S.ACCEPTED then
			D.print(("%s gave your order for %s back; it's open again."):format(D.Short(by), item))
		end
	elseif old and old.crafter == me and by ~= me and new.status == S.CANCELLED then
		if by == new.requester then
			D.print(("%s cancelled their order for %s."):format(D.Short(by), item))
		else
			D.print(("%s removed %s's order for %s that you were crafting."):format(D.Short(by), D.Short(new.requester), item))
		end
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
		id = ("%s:%d:%d"):format(me, now, math.random(100000, 999999)),
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
		if o.requester ~= D.Me() and not D.IsOfficer() then
			return "Only the requester or an officer can cancel an order."
		elseif o.status == S.DONE or o.status == S.CANCELLED then
			return "That order is already finished."
		end
	end, function(o)
		o.status = S.CANCELLED
	end)
end

-- Sync ----------------------------------------------------------------------------
-- Modelled on how CraftBoard keeps its board in step: compare a short
-- fingerprint first, and only send what's actually different.
--
-- * Every member's addon says "HD <count:hash>" (a fingerprint of every order
--   it holds and its revision) a little after login and every ~10 minutes.
--   Anyone whose own fingerprint differs knows the boards have drifted apart.
-- * Then one of them asks for a sync: "S" with a list of every order it holds
--   and its revision ("M" lines), in one compressed message.
-- * One member answers (each waits a random moment, and the first to start
--   announces it with "D" so the others stand down). The answer is one
--   compressed batch: the orders the asker is missing or has older copies of
--   ("R"), members' professions ("P") and recipes ("K") changed since the
--   asker's last sync, and "W" for the orders the asker has newer copies of.
-- * The asker sends those "W" orders back to the whole guild, so both sides
--   (and everyone listening) end up the same.

local pending = {} -- requester -> { since =, have = { [id] = rev } }, while we're waiting to answer them
local manifests = {} -- sender -> { [id] = rev }, the "M" lines of a sync request being read
local MARGIN = 600 -- profession/recipe catch-up starts a bit before the last sync, in case clocks or a message lagged
local DIGEST_EVERY = 600
local DIGEST_JITTER = 120
local RESYNC_GAP = 300 -- we ask for a sync because of a fingerprint at most this often
local lastSyncAsk = 0
local lastSyncSeen = 0
local resyncPending = false

-- "count:hash" over every order's id and revision.
function D.OrdersDigest()
	local keys = {}
	for id, o in pairs(orders() or {}) do
		keys[#keys + 1] = id .. "=" .. (o.rev or 0) .. (o.crafter or "")
	end
	table.sort(keys)
	local h = 5381
	for _, k in ipairs(keys) do
		for i = 1, #k do
			h = (h * 33 + k:byte(i)) % 4294967291
		end
	end
	return ("%d:%x"):format(#keys, h)
end

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
	lastSyncAsk = D.Now()
	local lines = {}
	if not full then
		for id, o in pairs(orders() or {}) do
			lines[#lines + 1] = D.Pack("M", id, o.rev or 0)
		end
	end
	lines[#lines + 1] = D.Pack("S", since, full and "full" or "list")
	D.SendTogether(lines)
end

D.Handle("M", function(f, sender)
	if f[2] and f[2] ~= "" then
		manifests[sender] = manifests[sender] or {}
		manifests[sender][f[2]] = tonumber(f[3]) or 0
	end
end)

local function answer(requester)
	local req = pending[requester]
	if not req then
		return
	end
	pending[requester] = nil
	local since, have = req.since, req.have
	D.Send("D", requester)
	local mine = orders() or {}
	for id, o in pairs(mine) do
		local theirs = have and have[id]
		if not have or not theirs or theirs < (o.rev or 0) then
			send("R", o, true)
		end
	end
	if have then
		for id, rev in pairs(have) do
			local o = mine[id]
			if not o or (o.rev or 0) < rev then
				D.SendBulk("W", requester, id)
			end
		end
	end
	local data = D.Data()
	for name in pairs(data and data.profs or {}) do
		D.SendProfessions(name, since)
	end
	for name in pairs(data and data.recipes or {}) do
		D.SendRecipes(name, since)
	end
	D.FlushBulk()
end
D._answerSync = answer

D.Handle("S", function(f, sender)
	lastSyncSeen = D.Now()
	local have = manifests[sender]
	manifests[sender] = nil
	if not orders() then
		return
	end
	local since = tonumber(f[2]) or 0
	if f[3] ~= "list" then
		have = nil -- an older client, or /pfg sync: send everything
	elseif not have then
		have = {} -- they have no orders at all
	end
	local old = pending[sender]
	pending[sender] = { since = math.min(old and old.since or since, since), have = have }
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

-- W requester id: the requester has a newer copy of this order than the one
-- answering; if that's us, share ours with everyone.
local pushed = {}
D.Handle("W", function(f)
	if D.FullName(f[2]) ~= D.Me() or not f[3] then
		return
	end
	local o = D.GetOrder(f[3])
	if o and not pushed[f[3]] then
		pushed[f[3]] = true
		send("R", o, true)
		if C_Timer then
			C_Timer.After(5, function()
				pushed[f[3]] = nil
			end)
		end
	end
end)

-- Fingerprints ----------------------------------------------------------------------

function D.SendDigest()
	if orders() then
		D.SendBulk("HD", D.OrdersDigest())
	end
end

D.Handle("HD", function(f)
	if not orders() or not f[2] or f[2] == D.OrdersDigest() then
		return
	end
	local now = D.Now()
	if resyncPending or now - lastSyncAsk < RESYNC_GAP then
		return
	end
	-- Wait a moment: if someone else asks for a sync first, that settles it.
	resyncPending = true
	local asked = lastSyncSeen
	if C_Timer then
		C_Timer.After(2 + math.random() * 8, function()
			resyncPending = false
			if lastSyncSeen == asked and f[2] ~= D.OrdersDigest() then
				D.RequestSync()
			end
		end)
	end
end)

local function digestLoop()
	D.SendDigest()
	if C_Timer then
		C_Timer.After(DIGEST_EVERY + math.random() * DIGEST_JITTER, digestLoop)
	end
end

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
		if not D._digestLoop then
			D._digestLoop = true
			C_Timer.After(40 + math.random() * 20, digestLoop)
		end
	end
end)

D.Command("sync", function()
	D.RequestSync(true)
	D.print("asked the guild for the latest orders and professions.")
end, "/pfg sync - fetch the latest orders and professions from the guild")
