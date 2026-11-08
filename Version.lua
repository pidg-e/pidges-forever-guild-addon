-- Pidge's Forever Guild: the addon's version. It shows next to "Info" on the
-- guild panel's Info tab, and guildmates' addons tell each other theirs ("V"),
-- so anyone on an older version gets a note in chat to update.

local ADDON, ns = ...
local D = ns.D

D.newestVersion = D.VERSION
local warned = false
local lastReply = 0

D.Handle("V", function(f, sender)
	local v = f[2]
	if not v or v == "" then
		return
	end
	local c = D.CompareVersions(v, D.VERSION)
	if c > 0 then
		if D.CompareVersions(v, D.newestVersion) > 0 then
			D.newestVersion = v
			D.Fire("VERSION", v)
		end
		if not warned then
			warned = true
			D.print(("a newer version (%s) is out; you have %s. Please update. %s has it, and it's at /pfg github."):format(v, D.VERSION, D.Short(sender)))
		end
	elseif c < 0 and D.Now() - lastReply > 60 then
		-- They're behind: tell the guild ours so they get the note.
		lastReply = D.Now()
		D.Send("V", D.VERSION)
	end
end)

D.On("GUILD", function(member)
	if member and C_Timer then
		C_Timer.After(12, function()
			if D.InGuild() then
				D.Send("V", D.VERSION)
			end
		end)
	end
end)

-- The Info tab label --------------------------------------------------------------

local label

local function update()
	if not label then
		return
	end
	local text = "|cff999999v" .. D.VERSION .. "|r"
	if D.CompareVersions(D.newestVersion, D.VERSION) > 0 then
		text = text .. " |cffff8000(v" .. D.newestVersion .. " available)|r"
	end
	label:SetText(text)
	label:SetShown(D.InGuild())
end

D.OnGuildPanel(function()
	local info = CommunitiesFrame and CommunitiesFrame.GuildDetailsFrame and CommunitiesFrame.GuildDetailsFrame.Info
	if not info or label then
		return
	end
	label = info:CreateFontString("PFGVersionText", "OVERLAY", "GameFontHighlightSmall")
	if info.TitleText then
		label:SetPoint("LEFT", info.TitleText, "RIGHT", 8, 0)
	else
		label:SetPoint("TOPLEFT", info, "TOPLEFT", 60, 20)
	end
	D._versionLabel = label
	update()
	info:HookScript("OnShow", update)
end)

D.On("GUILD", update)
D.On("VERSION", update)

D.Command({ "version", "v" }, function()
	D.print("version " .. D.VERSION .. (D.CompareVersions(D.newestVersion, D.VERSION) > 0 and (" (" .. D.newestVersion .. " is out)") or ""))
end, "/pfg version - which version you have")
