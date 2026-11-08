-- Pidge's Forever Guild: mailing a finished crafting order. At a mailbox, the
-- crafter's mail button on the order fills in the Send Mail tab: the
-- requester, a subject, the crafted items from their bags (split to the exact
-- amount), and a C.O.D. equal to the order's tip. The crafter checks it and
-- presses Send themselves.

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

local function freeAttachment()
	for i = 1, MAX_ATTACH do
		if not (HasSendMailItem and HasSendMailItem(i)) then
			return i
		end
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
	if SendMailNameEditBox then
		SendMailNameEditBox:SetText(D.Short(o.requester))
	end
	if SendMailSubjectEditBox then
		local item = o.itemName ~= "" and o.itemName or "your order"
		SendMailSubjectEditBox:SetText(("Crafting order: %s%s"):format(item, o.qty > 1 and (" x" .. o.qty) or ""))
	end

	-- The items: whole stacks while they fit, then split the last one.
	local need, attached, missing = o.qty or 1, 0, nil
	if o.itemID and o.itemID > 0 then
		for _, s in ipairs(findInBags(o.itemID)) do
			if need <= 0 then
				break
			end
			local slot = freeAttachment()
			if not slot then
				break
			end
			if ClearCursor then
				ClearCursor()
			end
			if s.count <= need then
				pickup(s.bag, s.slot)
				need = need - s.count
			else
				split(s.bag, s.slot, need)
				need = 0
			end
			ClickSendMailItemButton(slot)
			attached = attached + 1
		end
		if need > 0 then
			missing = need
		end
	end

	-- C.O.D. for the tip (C.O.D. needs at least one item attached).
	if (o.tip or 0) > 0 and attached > 0 then
		if SendMailRadioButton_OnClick then
			SendMailRadioButton_OnClick(2)
		elseif SendMailCODButton then
			SendMailCODButton:SetChecked(true)
			if SendMailSendMoneyButton then
				SendMailSendMoneyButton:SetChecked(false)
			end
		end
		if MoneyInputFrame_SetCopper and SendMailMoney then
			MoneyInputFrame_SetCopper(SendMailMoney, o.tip)
		end
	end
	if SendMailFrame_Update then
		SendMailFrame_Update()
	end

	if attached == 0 then
		return false, "You don't have the crafted item in your bags. The recipient and subject are filled in."
	elseif missing then
		return false, ("Attached what you have; %d more still to go."):format(missing)
	end
	D.print("mail filled in" .. ((o.tip or 0) > 0 and ", with a C.O.D. for the tip" or "") .. ". Check it and press Send.")
	return true
end
