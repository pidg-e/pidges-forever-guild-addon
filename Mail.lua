-- Pidge's Forever Guild: mailing a finished crafting order. At a mailbox, the
-- crafter's mail button on the order fills in the Send Mail tab: the
-- requester, a subject, the crafted items from their bags (split to the exact
-- amount), and a C.O.D. equal to the order's tip. The crafter checks it and
-- presses Send themselves; once that mail has gone, the order is marked done.

local ADDON, ns = ...
local D = ns.D

local S = D.STATUS
local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12

-- The crafter of an order in progress (or just finished) can mail it.
function D.CanMailOrder(o)
	return o.crafter == D.Me() and o.requester ~= D.Me() and (o.status == S.ACCEPTED or o.status == S.DONE)
end

local C = C_Container or {}
local numSlots = C.GetContainerNumSlots or GetContainerNumSlots
local pickup = C.PickupContainerItem or PickupContainerItem
local split = C.SplitContainerItem or SplitContainerItem

local function slotInfo(bag, slot)
	if C.GetContainerItemInfo then
		local info = C.GetContainerItemInfo(bag, slot)
		if info then
			return info.itemID, info.stackCount, info.isLocked
		end
		return nil
	end
	local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
	return id, count, locked
end

-- Where the bags hold this item: { { bag, slot, count }, ... }, biggest first.
local function findInBags(itemID)
	local found = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (numSlots and numSlots(bag)) or 0 do
			local id, count, locked = slotInfo(bag, slot)
			if id == itemID and not locked then
				found[#found + 1] = { bag = bag, slot = slot, count = count or 1 }
			end
		end
	end
	table.sort(found, function(a, b)
		return a.count > b.count
	end)
	return found
end
D._findInBags = findInBags

-- The name to mail: "First Last", never the realm (everyone is on one realm).
-- An order placed before the addon learned its owner's surname only holds the
-- first name, so the roster fills in the rest.
function D.MailName(name)
	local short = (name or ""):match("^[^%-]+") or ""
	short = short:gsub("^%s+", ""):gsub("%s+$", "")
	if short == "" or short:find(" ", 1, true) or not (GetNumGuildMembers and GetGuildRosterInfo) then
		return short
	end
	local lower = short:lower()
	for i = 1, (GetNumGuildMembers()) or 0 do
		local n = GetGuildRosterInfo(i)
		local rosterShort = n and n:match("^[^%-]+")
		if rosterShort and (rosterShort:match("^%S+") or ""):lower() == lower and rosterShort:find(" ", 1, true) then
			return rosterShort
		end
	end
	return short
end

-- The order whose mail we filled in, until it is sent (then it's done).
local pending -- { id =, name = }

local function freeAttachment()
	for i = 1, MAX_ATTACH do
		if not (HasSendMailItem and HasSendMailItem(i)) then
			return i
		end
	end
end

-- An empty slot in a normal bag (not a profession bag): bag, slot.
local function emptyBagSlot()
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local free, family = 0, 0
		if C.GetContainerNumFreeSlots then
			free, family = C.GetContainerNumFreeSlots(bag)
		elseif GetContainerNumFreeSlots then
			free, family = GetContainerNumFreeSlots(bag)
		end
		if (family or 0) == 0 then
			for slot = 1, (numSlots and numSlots(bag)) or 0 do
				if not slotInfo(bag, slot) then
					return bag, slot
				end
			end
		end
	end
end

local function setCOD(copper)
	if SendMailRadioButton_OnClick then
		SendMailRadioButton_OnClick(2)
	elseif SendMailCODButton then
		SendMailCODButton:SetChecked(true)
		if SendMailSendMoneyButton then
			SendMailSendMoneyButton:SetChecked(false)
		end
	end
	if MoneyInputFrame_SetCopper and SendMailMoney then
		MoneyInputFrame_SetCopper(SendMailMoney, copper)
	end
end

-- Fill in the Send Mail tab for this order. Returns true, or false and why.
function D.MailOrder(o)
	if not (MailFrame and MailFrame:IsShown()) then
		return false, "Open a mailbox first, then click the mail button again."
	end
	if InCombatLockdown and InCombatLockdown() then
		return false, "Not in combat."
	end
	if MailFrameTab_OnClick then
		MailFrameTab_OnClick(nil, 2)
	end
	pending = nil
	local recipient = D.MailName(o.requester)
	if SendMailNameEditBox then
		SendMailNameEditBox:SetText(recipient)
	end
	if SendMailSubjectEditBox then
		local item = o.itemName ~= "" and o.itemName or "your order"
		SendMailSubjectEditBox:SetText(("Crafting order: %s%s"):format(item, o.qty > 1 and (" x" .. o.qty) or ""))
	end

	-- The items, exactly o.qty of them. Stacks that fit go in whole. The game
	-- attaches a whole bag slot even when the cursor holds part of it, so the
	-- remainder is split into an empty bag slot first and attached from there
	-- once it has landed.
	local need, attached = o.qty or 1, 0
	local splitFrom, splitCount
	if o.itemID and o.itemID > 0 then
		for _, s in ipairs(findInBags(o.itemID)) do
			if need <= 0 then
				break
			end
			if s.count <= need then
				local slot = freeAttachment()
				if not slot then
					break
				end
				if ClearCursor then
					ClearCursor()
				end
				pickup(s.bag, s.slot)
				ClickSendMailItemButton(slot)
				attached = attached + 1
				need = need - s.count
			elseif not splitFrom then
				splitFrom, splitCount = s, need
				need = 0
			end
		end
	end

	local function finish(missing)
		if attached > 0 and (o.tip or 0) > 0 then
			setCOD(o.tip)
		end
		if SendMailFrame_Update then
			SendMailFrame_Update()
		end
		if attached == 0 then
			return false, "You don't have the crafted item in your bags. The recipient and subject are filled in."
		elseif missing and missing > 0 then
			return false, ("Attached what you have; %d more still to go."):format(missing)
		end
		if o.status == S.ACCEPTED then
			pending = { id = o.id, name = recipient }
		end
		D.print("mail filled in" .. ((o.tip or 0) > 0 and ", with a C.O.D. for the tip" or "") .. ". Check it and press Send; the order is marked done once it's sent.")
		return true
	end

	if not splitFrom then
		return finish(need)
	end
	local slot = freeAttachment()
	local bag, empty = emptyBagSlot()
	if not slot then
		return finish(splitCount)
	elseif not bag then
		finish(splitCount)
		return false, ("Free up one bag slot so I can split off the last %d, then click the mail button again."):format(splitCount)
	end
	if ClearCursor then
		ClearCursor()
	end
	split(splitFrom.bag, splitFrom.slot, splitCount)
	pickup(bag, empty)
	-- Wait for the split stack to land, then attach it.
	local tries = 0
	local function attachSplit()
		tries = tries + 1
		local id, count, locked = slotInfo(bag, empty)
		if id == o.itemID and count == splitCount and not locked and MailFrame:IsShown() then
			if ClearCursor then
				ClearCursor()
			end
			pickup(bag, empty)
			ClickSendMailItemButton(freeAttachment() or slot)
			attached = attached + 1
			local ok, err = finish(0)
			if not ok and err then
				D.print(err)
			end
		elseif tries < 30 and C_Timer then
			C_Timer.After(0.1, attachSplit)
		else
			if ClearCursor then
				ClearCursor()
			end
			finish(splitCount)
			D.print(("Couldn't split off the last %d; add %s yourself."):format(splitCount, splitCount == 1 and "it" or "them"))
		end
	end
	if C_Timer then
		C_Timer.After(0.1, attachSplit)
	else
		attachSplit()
	end
	return true
end

-- Sending -------------------------------------------------------------------------
-- SendMail tells us who the mail is for; MAIL_SEND_SUCCESS that it went.

local sending -- the pending order, while its mail is on its way

local function onSendMail(recipient)
	sending = nil
	if pending and type(recipient) == "string" and D.SameName(D.MailName(recipient), pending.name) then
		sending = pending
	end
end
D._onSendMail = onSendMail

local function onMailEvent(event)
	if event == "MAIL_SEND_SUCCESS" then
		local done = sending
		sending = nil
		if done then
			pending = nil
			local o = D.GetOrder(done.id)
			if o and o.status == S.ACCEPTED and o.crafter == D.Me() then
				D.CompleteOrder(done.id)
				D.print(("mail sent; %s's order is marked done."):format(D.Short(o.requester)))
			end
		end
	elseif event == "MAIL_FAILED" then
		sending = nil
	elseif event == "MAIL_CLOSED" then
		sending, pending = nil, nil
	end
end
D._onMailEvent = onMailEvent

if hooksecurefunc and SendMail then
	hooksecurefunc("SendMail", function(recipient)
		pcall(onSendMail, recipient)
	end)
end
if CreateFrame then
	local ev = CreateFrame("Frame")
	D.RegisterEvents(ev, "MAIL_SEND_SUCCESS", "MAIL_FAILED", "MAIL_CLOSED")
	ev:SetScript("OnEvent", function(_, event)
		onMailEvent(event)
	end)
end
