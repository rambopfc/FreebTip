local _, ns = ...

local mediapath = "Interface\\AddOns\\FreebTip\\media\\"
local cfg = {
	font = mediapath.."expressway.ttf",
	fontsize = 12, -- I'd suggest adjusting the scale instead of the fontsize
	outline = "OUTLINE",
	tex = mediapath.."texture",

	scale = 1.1,
	-- can use /freebtip or uncomment this to override SavedVars
	--point = { "BOTTOMRIGHT", -25, 200 },
	cursor = false,

	hideTitles = true,
	hideRealm = false,
	hideFaction = true,
	hidePvP = true,

	backdrop = {
		bgFile = "Interface\\Buttons\\WHITE8x8",
		-- original look
		--[[edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },]]

		-- glow border
		edgeFile = mediapath.."glowTex",
		tile = false,
		tileSize = 16,
		edgeSize = 4,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
	-- original
	--bgcolor = { r=0.05, g=0.05, b=0.05, t=0.9 }, -- background
	--bdrcolor = { r=0.3, g=0.3, b=0.3 }, -- border
	--
	-- glow border
	bgcolor = { r=0.06, g=0.06, b=0.06, t=1 }, -- background
	bdrcolor = { r=0.04, g=0.04, b=0.04 }, -- border

	gcolor = { r=1, g=0.1, b=0.8 }, -- guild

	you = "<You>",
	boss = "??",

	colorborderClass = false,
	colorborderItem = true,

	combathide = false,     -- world objects
	combathideALL = false,  -- everything

	multiTip = true, -- show more than one linked item tooltip

	hideHealthbar = false,

	powerbar = true, -- enable power bars
	powerManaOnly = true, -- only show mana users

	showRank = true, -- show guild rank

	showTalents = true,
	tcacheTime = 900, -- talent cache time in seconds (default 15 mins)
}
ns.cfg = cfg
local style

local GetTime = GetTime
local tonumber = tonumber
local select = select
local _G = _G
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local PVP = PVP
local FACTION_ALLIANCE = FACTION_ALLIANCE
local FACTION_HORDE = FACTION_HORDE
local LEVEL = LEVEL
local CHAT_FLAG_AFK =CHAT_FLAG_AFK
local CHAT_FLAG_DND = CHAT_FLAG_DND
local ICON_LIST = ICON_LIST
local targettext = TARGET..":"
local DEAD = DEAD
local RAID_CLASS_COLORS = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

local talentcache = {}
local talenttext = TALENTS..":"
local talentcolor = {r=1,g=1,b=1}

local colors = {power = {}}
for power, color in next, PowerBarColor do
	if(type(power) == 'string') then
		colors.power[power] = {color.r, color.g, color.b}
	end
end

colors.power['MANA'] = {.31,.45,.63}
colors.power['RAGE'] = {.69,.31,.31}

local classification = {
	elite = "+",
	rare = " R",
	rareelite = " R+",
}

local numberize = function(val)
	if (val >= 1e6) then
		return ("%dm"):format(val / 1e6)
	elseif (val >= 1e3) then
		return ("%dk"):format(val / 1e3)
	else
		return ("%d"):format(val)
	end
end

local find = string.find
local format = string.format
local hex = function(color)
	return format('|cff%02x%02x%02x', color.r * 255, color.g * 255, color.b * 255)
end

local nilcolor = { r=1, g=1, b=1 }
local tapped = { r=.6, g=.6, b=.6}
local function unitColor(unit)
	if not unit then unit = "mouseover" end
	local color
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		color = RAID_CLASS_COLORS[class]
	elseif(UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit)) then
		color = tapped
	else
		local reaction = UnitReaction(unit, "player")
		if reaction then
			color = FACTION_BAR_COLORS[reaction]
		end
	end
	return (color or nilcolor)
end

local function GameTooltip_UnitColor(unit)
	local color = unitColor(unit)
	if color then return color.r, color.g, color.b end
end

local function getTarget(unit)
	if UnitIsUnit(unit, "player") then
		return ("|cffff0000%s|r"):format(cfg.you)
	else
		return UnitName(unit)
	end
end

local function formatLines()
	for i=1, GameTooltip:NumLines() do
		local tiptext = _G["GameTooltipTextLeft"..i]
		
		tiptext:ClearAllPoints()
		if i==1 then
			tiptext:SetPoint("TOPLEFT", GameTooltip, "TOPLEFT", 10, -10)
		else
			tiptext:SetPoint("TOPLEFT", _G["GameTooltipTextLeft"..i-1], "BOTTOMLEFT", 0, -2)
		end
	end
end

local function UpdatePower()
	return function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < .25 then return end

		local unit = self.unit
		if(unit) then
			local min, max = UnitPower(unit), UnitPowerMax(unit)
			if(max ~= 0) then
				self:SetValue(min)

				local pp = numberize(min).." / "..numberize(max)
				self.text:SetText(pp)
			end
		end

		self.elapsed = 0
	end
end

local function HidePower(powerbar)
	if powerbar then
		powerbar:Hide()

		if powerbar.text then
			powerbar.text:SetText(nil)
		end
	end
end

local function ShowPowerBar(self, unit, statusbar)
	local powerbar = _G[self:GetName().."FreebTipPowerBar"]
	if not unit then return HidePower(powerbar) end

	local min, max = UnitPower(unit), UnitPowerMax(unit)
	local ptype, ptoken = UnitPowerType(unit)

	if(max == 0 or (cfg.powerManaOnly and ptoken ~= 'MANA')) then
		return HidePower(powerbar)
	else
		self:AddLine(" ")
	end

	if(not powerbar) then
		powerbar = CreateFrame("StatusBar", self:GetName().."FreebTipPowerBar", statusbar)
		powerbar:SetHeight(statusbar:GetHeight())
		powerbar:SetWidth(0)
		powerbar:SetStatusBarTexture(cfg.tex, "OVERLAY")
		powerbar.elapsed = 0
		powerbar:SetScript("OnUpdate", UpdatePower())

		local bg = powerbar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(powerbar)
		bg:SetTexture(cfg.tex)
		bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
	end
	powerbar.unit = unit

	powerbar:SetMinMaxValues(0, max)
	powerbar:SetValue(min)

	local pcolor = colors.power[ptoken]
	if(pcolor) then
		powerbar:SetStatusBarColor(pcolor[1], pcolor[2], pcolor[3])
	end

	powerbar:ClearAllPoints()
	powerbar:SetPoint("LEFT", statusbar, "LEFT", 0, -(statusbar:GetHeight()) - 5)
	powerbar:SetPoint("RIGHT", self, "RIGHT", -10, 0)

	powerbar:Show()

	if(not powerbar.text) then
		powerbar.text = powerbar:CreateFontString(nil, "OVERLAY")
		powerbar.text:SetPoint("CENTER", powerbar)
		powerbar.text:SetFont(cfg.font, 12, cfg.outline)
		powerbar.text:Show()
	end

	local pp = numberize(min).." / "..numberize(max)
	powerbar.text:SetText(pp)
end

local talentGUID
local talentevent = CreateFrame"Frame"

local function updateTalents(spec)
	for i=3, GameTooltip:NumLines() do
		local tiptext = _G["GameTooltipTextRight"..i]
		local linetext = tiptext:GetText()

		if linetext and (linetext == "...") then
			tiptext:SetText(spec)
			GameTooltip:Show()
			formatLines()
			break
		end
	end
end

local function ShowTalents(self, unit)
	local canInspect = CanInspect(unit)
	if(not canInspect) then return end

	local uGUID = UnitGUID(unit)

	if((not self.freebTalentSet and talentcache[uGUID])) then
		-- look for an empty line..
		local talentSet = false
		for i=3, self:NumLines() do
			local tiptext = _G["GameTooltipTextLeft"..i]

			local blankline = tiptext:GetText() == " " and true
			if(blankline or not tiptext:IsShown()) then
				tiptext:SetText(talenttext)
				tiptext:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
				tiptext:Show()

				local tipRtext = _G["GameTooltipTextRight"..i]
				tipRtext:SetText("...")
				tipRtext:SetTextColor(talentcolor.r, talentcolor.g, talentcolor.b)
				tipRtext:Show()

				if blankline then
					self:AddLine(" ")
				end
				talentSet = true
				break
			end
		end
		if not talentSet then
			self:AddDoubleLine(talenttext, ("..."), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
			talentcolor.r, talentcolor.g, talentcolor.b)
		end
		
		self.freebTalentSet = true
	end

	if talentcache[uGUID] then
		-- check to see how old the talentcache is
		if(GetTime() - talentcache[uGUID].time) > cfg.tcacheTime then
			talentcache[uGUID] = nil

			return ShowTalents(self, unit)
		end

		local talname = talentcache[uGUID].talent
		updateTalents(talname)
	else
		if(not canInspect) or (InspectFrame and InspectFrame:IsShown()) then return end
		talentGUID = uGUID
		talentevent:RegisterEvent"INSPECT_READY"

		NotifyInspect(unit)
	end
end

talentevent:SetScript("OnEvent", function(self, event, arg1)
	if event == "INSPECT_READY" then
		local activeSpec = GetInspectSpecialization("mouseover")
		local name = activeSpec and select(2, GetSpecializationInfoByID(activeSpec))

		if name then
			talentcache[arg1] = {talent = name,time = GetTime()}
			ShowTalents(GameTooltip, "mouseover")

			if InspectFrame and (not InspectFrame:IsShown()) then
				ClearInspectPlayer()
			end
		end
	end
end)

GameTooltip:HookScript("OnTooltipCleared", function(self)
	self.freebTalentSet = false
end)

GameTooltip:HookScript("OnTooltipSetUnit", function(self)
	if cfg.combathide and InCombatLockdown() then
		return self:Hide()
	end

	-- Hide stuff
	for i=3, self:NumLines() do
		local tiptext = _G["GameTooltipTextLeft"..i]
		local linetext = tiptext:GetText()

		if cfg.hidePvP and linetext:find(PVP) then
			tiptext:SetText(nil)
			tiptext:Hide()
		elseif linetext:find(FACTION_ALLIANCE) then
			if cfg.hideFaction then
				tiptext:SetText(nil)
				tiptext:Hide()
			else
				tiptext:SetText("|cff7788FF"..linetext.."|r")
			end
		elseif linetext:find(FACTION_HORDE) then
			if cfg.hideFaction then
				tiptext:SetText(nil)
				tiptext:Hide()
			else
				tiptext:SetText("|cffFF4444"..linetext.."|r")
			end
		end
	end

	local unit = select(2, self:GetUnit()) or GetMouseFocus().unit
	if unit then
		local isPlayer = UnitIsPlayer(unit)
		local unitGuild, unitRank = GetGuildInfo(unit)
		if isPlayer then
			if cfg.hideTitles and cfg.hideRealm then
				local unitName = GetUnitName(unit)
				if unitName then GameTooltipTextLeft1:SetText(unitName) end
			elseif cfg.hideTitles then
				local unitName = GetUnitName(unit, true)
				if unitName then GameTooltipTextLeft1:SetText(unitName) end
			elseif cfg.hideRealm then
				local _, realm = UnitName(unit)
				if realm then
					local text = GameTooltipTextLeft1:GetText()
					text = text:gsub("- "..realm, "")
					if text then GameTooltipTextLeft1:SetText(text) end
				end
			end

			self:AppendText((" |cff00cc00%s|r"):format(UnitIsAFK(unit) and CHAT_FLAG_AFK or
			UnitIsDND(unit) and CHAT_FLAG_DND or
			not UnitIsConnected(unit) and "<DC>" or ""))

			local text2 = GameTooltipTextLeft2:GetText()
			if unitGuild and text2 and text2:find("^"..unitGuild) then
				GameTooltipTextLeft2:SetTextColor(cfg.gcolor.r, cfg.gcolor.g, cfg.gcolor.b)
				if cfg.showRank and unitRank then
					GameTooltipTextLeft2:SetText(("%s (|cff00FCCC%s|r)"):format(unitGuild, unitRank))
				end
			end

			if cfg.colorborderClass then
				self:SetBackdropBorderColor(GameTooltip_UnitColor(unit))
			end
		end

		local ricon = GetRaidTargetIndex(unit)
		if ricon then
			local text = GameTooltipTextLeft1:GetText()
			GameTooltipTextLeft1:SetText(("%s %s"):format(ICON_LIST[ricon]..cfg.fontsize.."|t", text))
		end

		local color = unitColor(unit)
		local line1 = GameTooltipTextLeft1:GetText()
		GameTooltipTextLeft1:SetFormattedText("%s", hex(color)..line1)
		GameTooltipTextLeft1:SetTextColor(GameTooltip_UnitColor(unit))

		local alive = not UnitIsDeadOrGhost(unit)
		local level = UnitLevel(unit)

		if level then
			local unitClass = isPlayer and hex(color)..UnitClass(unit).."|r" or ""
			local creature = not isPlayer and UnitCreatureType(unit) or ""
			local diff = GetQuestDifficultyColor(level)

			if level == -1 then
				level = "|cffff0000"..cfg.boss
			end

			local classify = UnitClassification(unit)
			local textLevel = ("%s%s%s|r"):format(hex(diff), tostring(level), classification[classify] or "")

			for i=(unitGuild and 3 or 2), self:NumLines() do
				local tiptext = _G["GameTooltipTextLeft"..i]
				if tiptext:GetText():find(LEVEL) then
					if alive then
						tiptext:SetFormattedText(("%s %s%s %s"), textLevel, creature, UnitRace(unit) or "", unitClass)
					else
						tiptext:SetFormattedText(("%s %s"), textLevel, "|cffCCCCCC"..DEAD.."|r")
					end

					break
				end
			end
		end

		if UnitExists(unit.."target") then
			local tarRicon = GetRaidTargetIndex(unit.."target")
			local tar = ("%s%s"):format((tarRicon and ICON_LIST[tarRicon].."10|t") or "", getTarget(unit.."target"))

			local tarSet = false
			for i=3, self:NumLines() do
				local tiptext = _G["GameTooltipTextLeft"..i]

				if(not tiptext:IsShown()) then
					tiptext:SetText(targettext)
					tiptext:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
					tiptext:Show()

					local tipRtext = _G["GameTooltipTextRight"..i]
					tipRtext:SetText(tar)
					tipRtext:SetTextColor(GameTooltip_UnitColor(unit.."target"))
					tipRtext:Show()

					tarSet = true
					break
				end
			end
			if not tarSet then
				self:AddDoubleLine(targettext, tar, nil, nil, nil, GameTooltip_UnitColor(unit.."target"))
			end
		end

		level = tonumber(level)
		if cfg.showTalents and isPlayer and (level and level > 9) then
			ShowTalents(self, unit)
		end

		if not alive or cfg.hideHealthbar then
			GameTooltipStatusBar:Hide()
		else
			GameTooltipStatusBar:SetStatusBarColor(color.r, color.g, color.b)
		end
	else
		GameTooltipStatusBar:SetStatusBarColor(0, .9, 0)
	end

	if GameTooltipStatusBar:IsShown() then
		if cfg.powerbar then
			ShowPowerBar(self, unit, GameTooltipStatusBar)
		end

		self:AddLine(" ")
		GameTooltipStatusBar:ClearAllPoints()

		local gsbHeight = GameTooltipStatusBar:GetHeight()
		if GameTooltipFreebTipPowerBar and GameTooltipFreebTipPowerBar:IsShown() then
			GameTooltipStatusBar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 10, (gsbHeight*2)+8)
			GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", self, -10, 0)
		else
			GameTooltipStatusBar:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 10, gsbHeight+3)
			GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", self, -10, 0)
		end
	end

	self:Show()
	formatLines()
end)

GameTooltipStatusBar:SetStatusBarTexture(cfg.tex)
local bg = GameTooltipStatusBar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(GameTooltipStatusBar)
bg:SetTexture(cfg.tex)
bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)

GameTooltipStatusBar:SetScript("OnValueChanged", function(self, value)
	if not value then
		return
	end
	local min, max = self:GetMinMaxValues()
	if (value < min) or (value > max) then
		return
	end
	local _, unit = GameTooltip:GetUnit()
	if unit then
		min, max = UnitHealth(unit), UnitHealthMax(unit)
		if not self.text then
			self.text = self:CreateFontString(nil, "OVERLAY")
			self.text:SetPoint("CENTER", GameTooltipStatusBar)
			self.text:SetFont(cfg.font, 12, cfg.outline)
		end
		self.text:Show()
		local hp = numberize(min).." / "..numberize(max)
		self.text:SetText(hp)
	end
end)

local function setBakdrop(frame)
	frame:SetBackdrop(cfg.backdrop)
	frame:SetScale(cfg.scale)

	frame.freebBak = true
end

function style(frame)
	if not frame.freebBak then
		setBakdrop(frame)
	end

	frame:SetBackdropColor(cfg.bgcolor.r, cfg.bgcolor.g, cfg.bgcolor.b, cfg.bgcolor.t)
	frame:SetBackdropBorderColor(cfg.bdrcolor.r, cfg.bdrcolor.g, cfg.bdrcolor.b)

	if cfg.colorborderItem and frame.GetItem then
		local _, item = frame:GetItem()
		if item then
			--print(item)
			local quality = select(3, GetItemInfo(item))
			if(quality) then
				local r, g, b = GetItemQualityColor(quality)
				frame:SetBackdropBorderColor(r, g, b)
			end
		else
			frame:SetBackdropBorderColor(cfg.bdrcolor.r, cfg.bdrcolor.g, cfg.bdrcolor.b)
		end
	end

	local frameName = frame:GetName()
	if frameName ~= "GameTooltip" and frame.NumLines then
		for index=1, frame:NumLines() do
			if index==1 then
				_G[frameName..'TextLeft'..index]:SetFont(cfg.font, cfg.fontsize+2, cfg.outline)
			else
				_G[frameName..'TextLeft'..index]:SetFont(cfg.font, cfg.fontsize, cfg.outline)
			end
			_G[frameName..'TextRight'..index]:SetFont(cfg.font, cfg.fontsize, cfg.outline)
		end
	end

	if _G[frameName.."MoneyFrame1"] then
		_G[frameName.."MoneyFrame1PrefixText"]:SetFontObject(GameTooltipText)
		_G[frameName.."MoneyFrame1SuffixText"]:SetFontObject(GameTooltipText)
		_G[frameName.."MoneyFrame1GoldButtonText"]:SetFontObject(GameTooltipText)
		_G[frameName.."MoneyFrame1SilverButtonText"]:SetFontObject(GameTooltipText)
		_G[frameName.."MoneyFrame1CopperButtonText"]:SetFontObject(GameTooltipText)
	end
end

ns.style = style

local tooltips = {
	GameTooltip,
	ItemRefTooltip,
	ShoppingTooltip1,
	ShoppingTooltip2,
	ShoppingTooltip3,
	AutoCompleteBox,
	FriendsTooltip,
	WorldMapTooltip,
	DropDownList1MenuBackdrop,
	DropDownList2MenuBackdrop,
	DropDownList3MenuBackdrop,
}

for i, frame in ipairs(tooltips) do
	if frame then
		hooksecurefunc(frame, "Show", function(self)
			if(cfg.combathideALL and InCombatLockdown()) then
				return self:Hide()
			end

			style(self)
		end)
	end
end

--[[
-- Just a tool to get spell ids..
hooksecurefunc(GameTooltip, "SetUnitAura", function(self,...)
local id = select(11,UnitAura(...))
if id then
--print(id)
GameTooltip:AddLine("ID: "..id)
GameTooltip:Show()
end
end)]]

local f = CreateFrame"Frame"
f:RegisterEvent"PLAYER_LOGIN"
f:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then

		GameTooltipHeaderText:SetFont(cfg.font, cfg.fontsize+2, cfg.outline)
		GameTooltipText:SetFont(cfg.font, cfg.fontsize, cfg.outline)
		GameTooltipTextSmall:SetFont(cfg.font, cfg.fontsize-2, cfg.outline)
		GameTooltip:HookScript("OnShow", function(self) self:Show() end)

		f:UnregisterEvent"PLAYER_LOGIN"
	end
end)
