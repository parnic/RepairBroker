local LibQTip = LibStub('LibQTip-1.0')
local LibDataBroker = LibStub('LibDataBroker-1.1')
if not LibDataBroker then return end
local L = LibStub:GetLibrary( "AceLocale-3.0" ):GetLocale("RepairBroker" )
local name = L["RepairBroker"]
local Repair = LibDataBroker:NewDataObject(name, {
	icon = "Interface\\Icons\\Trade_BlackSmithing",
	label = L["Dur"],
	text = "100%",
	}
)

local equiptedCost = 0
local inventoryCost = 0
local tooltipRefresh = true
local print = function(msg) print("|cFF5555AA"..name..": |cFFAAAAFF"..msg) end

local slots = { }
do
	local slotNames = { "HeadSlot", "ShoulderSlot", "ChestSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
	for i,name in ipairs(slotNames) do
		slots[ i ] = { GetInventorySlotInfo(name), string.sub(name, 1, string.len(name)-4), 1 }
	end
	slotNames = nil -- dispose
end

local OnLoad = function()
	if not RepairBrokerDB then
		RepairBrokerDB = {
			autoRepair = 1,     -- nil or 1
			useGuildBank = nil, -- nil or 1
		}
	end
end

---------------------------------
-- Support functions
---------------------------------
local DurabilityColor = function(perc)
	if not perc or perc < 0 then return "|cFF555555" end
	if perc == 1 then
		return "|cFF005500" -- Dark green
	elseif perc >= .9 then
		return "|cFF00AA00" -- Green
	elseif perc > .5 then
		return "|cFFFFFF00" -- Yellow
	elseif perc > .2 then
		return "|cFFFF9900" -- Orange
	else
		return "|cFFFF0000" -- Red
	end
end

local CopperToString = function(c)
	local str = ""
	if not c or c < 0 then return str end
	if c >= 10000 then
		local g = math.floor(c/10000)
		c = c - g*10000
		str = str.."|cFFFFD800"..g.." |TInterface\\MoneyFrame\\UI-GoldIcon.blp:0:0:0:0|t "
	end
	if c >= 100 then
		local s = math.floor(c/100)
		c = c - s*100
		str = str.."|cFFC7C7C7"..s.." |TInterface\\MoneyFrame\\UI-SilverIcon.blp:0:0:0:0|t "
	end
	if c >= 0 then
		str = str.."|cFFEEA55F"..c.." |TInterface\\MoneyFrame\\UI-CopperIcon.blp:0:0:0:0|t "
	end
	return str
end

---------------------------------
-- Durability updates and repair
---------------------------------
local UpdateDurability = function()
	local dur, durPerc, max
	local minDur = 1
	local anyChanges = false
	for i,info in ipairs(slots) do
		durPerc = -1
		if GetInventoryItemLink("player", info[1]) then
			dur, max = GetInventoryItemDurability(info[1])
			if dur and max > 0 then
				durPerc = dur/max
				if durPerc < minDur then minDur = durPerc end
			end
		end
		if info[3] ~= durPerc then anyChanges = true end
		info[3] = durPerc
	end
	Repair.text = DurabilityColor(minDur)..math.floor(minDur*100).."%"
	return anyChanges
end

local AutoRepair = function()
	if not RepairBrokerDB.autoRepair then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then return end
	
	-- Use guildbank to repair
	if CanWithdrawGuildBankMoney() and RepairBrokerDB.useGuildBank and GetGuildBankMoney() >= cost then
		RepairAllItems(1)
		print(L["Repaired for "]..CopperToString(cost)..L[" (Guild bank)"])
	elseif GetMoney() >= cost then -- Repair the old fashion way
		RepairAllItems()
		print(L["Repaired for "]..CopperToString(cost))
	else
		print(L["Unable to AutoRepair, you need "]..CopperToString(cost - GetMoney()))
	end
end

local OnEvent = function(_, event, ...)
	if event ~= "MERCHANT_SHOW" then
		tooltipRefresh = true
		UpdateDurability()
	else
		AutoRepair()
	end
end

local event = CreateFrame("Frame")
event:RegisterEvent("ADDON_LOADED")
event:SetScript("OnEvent", function(_, _, addon)
	if addon ~= name then return end
	OnLoad()
	event:SetScript("OnEvent", OnEvent)
	event:UnregisterEvent("ADDON_LOADED")
	event:RegisterEvent("PLAYER_DEAD")
	event:RegisterEvent("PLAYER_UNGHOST")
	event:RegisterEvent("PLAYER_REGEN_ENABLED")
	event:RegisterEvent("UPDATE_INVENTORY_ALERTS")
	event:RegisterEvent("MERCHANT_SHOW")
	event:RegisterEvent("MERCHANT_CLOSED")
end)

---------------------------------
-- TOOLTIP
---------------------------------
local tooltip = nil
local TEXT_COLOR = "|cFFAAAAAA"

local TooltipSavedVars = function()
	tooltip:AddHeader(" ")
	tooltip:AddHeader(L["Auto repair:"])
	tooltip:AddLine(TEXT_COLOR..L["Force update"], " ", L["LeftMouse"])
	tooltip:AddLine(TEXT_COLOR..L["Toggle auto-repair"], " ", L["RightMouse"])
	tooltip:AddLine(TEXT_COLOR..L["Toggle guild bank-repair"], " ", L["MiddleMouse"])
end

local TooltipEquiptedItems = function()
	local dur, totalCost, cost = 0, 0, nil
	
	tooltip:AddHeader(L["Equipted items"])
	
	for i,info in ipairs(slots) do
		-- Durability in %
		dur = math.floor(info[3]*100)
		
		-- Add some color
		if dur >= 0 then
			dur = DurabilityColor(info[3])..dur
			dur = dur.."%"
		else
			dur = DurabilityColor(-1).."-  "
		end
		
		-- Find the repair cost
		cost = select(3, GameTooltip:SetInventoryItem("player", info[1]))
		
		-- Set row in the tooltip
		tooltip:AddLine(
			TEXT_COLOR..info[2], -- Slot
			dur,		         -- Dur
			CopperToString(cost) -- Cost
		)
		
		-- Add to total cost
		if cost and cost > 0 then totalCost = totalCost + cost end
	end
	return totalCost
end


--[[
	Initial code, needs refactoring
--]]
local UpdateInventoryCost, TooltipBagItems
do
	local gSlot, gBag = 0, 0
	local cost, dur, maxDur = 0, 1, 1
	local f = CreateFrame("Frame")
	local updateRunning = false
	local nextUpdateInventory = 0

	local UpdatePartialInventoryCost = function()
		--print("Space: " .. (gSlot or 0) .. " - " .. (gBag or 1))
		local endLoop = GetTime() + .01
		for bag = gBag or 0, 4 do
			gBag = bag
			--print("slot: " .. gSlot)
			for slot = gSlot or 1, GetContainerNumSlots(bag) do
				gSlot = slot
				--print(bag .. " / " .. slot)
				if endLoop < GetTime() then return end -- Stop loop
				-- Cost
				local _, repairCost = GameTooltip:SetBagItem(bag, slot)
				if repairCost then cost = cost + repairCost end
				
				-- Dur
				d, m = GetContainerItemDurability(bag, slot)
				if d and m then dur = dur + d; maxDur = maxDur + m end
			end
		end
		--print("END");
		updateRunning = false
		f:SetScript("OnUpdate", nil)
		Repair:OnEnter(1, 1)
	end
	
	TooltipBagItems = function()
		local averageDur = dur/maxDur
	
		GameTooltip:Hide()
		-- Some space and the actual text
		tooltip:AddHeader(" ")
		tooltip:AddHeader("Inventory")
		if not updateRunning then
			tooltip:AddLine(
				TEXT_COLOR..L["Items in your bags"],                          -- Slot
				DurabilityColor(averageDur)..math.floor(100*averageDur).."%", -- Dur
				CopperToString(cost)                                          -- Cost
			)
		else
			tooltip:AddLine(
				TEXT_COLOR..L["Items in your bags"],                          -- Slot
				"..%",                                                        -- Dur
				L["Loading"]                                                  -- Cost
			)
		end
	end
	
	UpdateInventoryCost = function()
		if updateRunning or nextUpdateInventory > GetTime() then return end
		nextUpdateInventory = GetTime() + 2 -- Max update every 2 sec
		updateRunning = true;
		--print("RESET")
		gSlot, gBag = 0, 0
		cost, dur, maxDur = 0, 1, 1
		
		local nextTime = GetTime()
		f:SetScript("OnUpdate", UpdatePartialInventoryCost)
	end
end

local TooltipRepairCost = function(cost)
	if cost > 0 then
		tooltip:AddHeader(" ")
		tooltip:AddHeader(L["Total cost"])

		local m = 1
		for i=4, 8 do
			tooltip:AddLine(
				TEXT_COLOR.._G["FACTION_STANDING_LABEL"..i], -- Slot
				" ",                                         -- Dur
				CopperToString(math.floor(cost*m+.5))        -- Cost
			)
			m = m - .05
		end
	end
end

function Repair:OnEnter(forceUpdate)
	print("ENTER")
	local durUpdate = UpdateDurability() or tooltipRefresh
	
	if tooltip then
		-- Allways update on force
		if forceUpdate or durUpdate then
			tooltip:Clear()
		else
			tooltip:Show()
			tooltip:SmartAnchorTo(self)
			return
		end
	else
		-- Generate tooltip
		tooltip = LibQTip:Acquire("RepairTooltip", 3, "LEFT", "CENTER", "RIGHT")
	end
	
	-- Equipment dur/cost
	if not callback then equiptedCost = TooltipEquiptedItems() end
	
	-- Inventory dur/cost
	if not callback then UpdateInventoryCost() end
	TooltipBagItems()
	
	-- Total repair costs
	TooltipRepairCost(equiptedCost + inventoryCost)
	
	-- Mouse actions
	if not InCombatLockdown() then TooltipSavedVars() end

	tooltip:Show()
	tooltipRefresh = InCombatLockdown() -- Re-draw if we were in combat
	if not forceUpdate then tooltip:SmartAnchorTo(self) end
end

function Repair:OnLeave()
	if not tooltip then return end
	tooltip:Hide()
end

function Repair:OnClick(button)
	if button == "RightButton" then
		RepairBrokerDB.autoRepair = not RepairBrokerDB.autoRepair
		print(L["Auto-repair "]..(RepairBrokerDB.autoRepair and "|cFF00FF00"..L["Enabled"] or "|cFFFF0000"..L["Disabled"]))
	elseif button == "MiddleButton" then
		RepairBrokerDB.useGuildBank = not RepairBrokerDB.useGuildBank
		print(L["Guild bank-repair "]..(RepairBrokerDB.useGuildBank and "|cFF00FF00"..L["Enabled"] or "|cFFFF0000"..L["Disabled"]))
	else
		print("|cFF00FF00"..L["Force durability check."])
		Repair:OnEnter(true)
	end
	tooltip:Show()
end
