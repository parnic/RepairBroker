local LibQTip = LibStub('LibQTip-1.0')
local LibDataBroker = LibStub('LibDataBroker-1.1')
if not LibDataBroker or not LibQTip then return end
local L = LibStub:GetLibrary( "AceLocale-3.0" ):GetLocale("RepairBroker" )
local name = L["RepairBroker"]

local tooltip = LibQTip:Acquire("RepairTooltip", 3, "LEFT", "CENTER", "RIGHT")

local Repair = {
	icon = "Interface\\Icons\\Trade_BlackSmithing",
	label = L["Dur"],
	text = "100%",
}

local headerColor = "|cFFFFFFFF";
local textColor = "|cFFAAAAAA";

local refreshTooltip = 0
local equippedCost = 0
local inventoryCost = 0
local inventoryLine = nil
local factionLine = { }

local GetInventorySlotInfo, GetContainerItemDurability, ipairs, print
 = GetInventorySlotInfo, GetContainerItemDurability, ipairs, print

local print = function(msg) print("|cFF5555AA"..name..": |cFFAAAAFF"..msg) end

-- Stores equipped item info
local slots = { }
do
	local slotNames = { "Head", "Shoulder", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "MainHand", "SecondaryHand", "Ranged" }
	for i,name in ipairs(slotNames) do
		slots[ i ] = {	
			GetInventorySlotInfo(name.."Slot"), -- slotId
			name, -- slotName, used for translation
			-1,    -- Durability
			0,    -- Cost
			2     -- Tooltip line
		}
	end
end

function Repair:OnLoad()
	Repair:CreateTooltipSkelet()
	if not RepairBrokerDB then
		RepairBrokerDB = {
			autoRepair = 1,     -- nil or 1
			useGuildBank = nil, -- nil or 1
		}
	end
	
	-- Cleanup
	Repair.CreateTooltipSkelet = nil
	Repair.OnLoad = nil
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
	if c == 0 then return "" end
	
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

local DurabilityText = function(num)
	if type(num) == "number" and num >= 0 then
		return DurabilityColor(num)..math.floor(num*100).."%"
	else
		return DurabilityColor(-1).."-"
	end
end

---------------------------------
-- Durability updates and repair
---------------------------------
function Repair:CreateTooltipSkelet()
	local line
	
	tooltip:AddHeader(headerColor..L["Equipped items"])
	for i,info in ipairs(slots) do
		-- Set the empty row
		info[5] = tooltip:AddLine(
			textColor..L[info[2]],   -- Slot
			"   ",                   -- Dur
			"       "                -- Cost
		)
	end
	
	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Inventory"])
	inventoryLine = tooltip:AddLine(
		textColor..L["Items in your bags"], -- Slot
		"..%",                              -- Dur
		L["Loading"]                        -- Cost
	)
	
	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Total cost"])

	for i=4, 8 do
		factionLine[i] = tooltip:AddLine(
			textColor.._G["FACTION_STANDING_LABEL"..i], -- Slot
			"   ",                                      -- Dur
			"       "                                   -- Cost
		)
	end
	
	tooltip:AddHeader(" ")
	tooltip:AddHeader(headerColor..L["Auto repair:"])
	tooltip:AddLine(textColor..L["Force update"], " ", L["LeftMouse"])
	tooltip:AddLine(textColor..L["Toggle auto-repair"], " ", L["RightMouse"])
	tooltip:AddLine(textColor..L["Toggle guild bank-repair"], " ", L["MiddleMouse"])
end

do
	local i = 1
	local cost = 0
	local dur, durPerc, max
	local minDur = 1
	local f = CreateFrame("Frame")

	local UpdateEquippedItemsPartial = function()
		local endLoop = GetTime() + .01
		
		while slots[i] do
			local info = slots[i]
		
			durPerc = -1 -- Default: no item equipted
			if GetInventoryItemLink("player", info[1]) then
				dur, max = GetInventoryItemDurability(info[1])
				if dur and max > 0 then
					durPerc = dur/max
					if durPerc < minDur then minDur = durPerc end
				end
			end
			-- Update %
			info[3] = durPerc
			-- Update cost
			info[4] = select(3, GameTooltip:SetInventoryItem("player", info[1])) or 0
			
			-- Add to total cost
			equippedCost = equippedCost + info[4]
		
			-- Make ready for the next round
			i = i + 1
		
			-- Stop loop
			if endLoop < GetTime() then
				GameTooltip:Hide()
				return
			end
		end
		GameTooltip:Hide()

		Repair.text = DurabilityText(minDur)
		Repair.RenderEquippedDurability()
		f:SetScript("OnUpdate", nil)
	end

	function Repair:UpdateEquippedDurability()
		-- Start smal
		equippedCost = 0;
		
		-- Reset vars
		i = 1
		cost = 0
		minDur = 1
		
		f:SetScript("OnUpdate", UpdateEquippedItemsPartial)
	end
end

function Repair:RenderEquippedDurability()
	for i,info in ipairs(slots) do
		tooltip:SetCell(info[5], 2, DurabilityText(info[3]))
		tooltip:SetCell(info[5], 3, CopperToString(info[4]))
	end
end

function Repair:RenderTotalCost()
	local m = 1
	local cost = equippedCost + inventoryCost
	for i=4, 8 do
		tooltip:SetCell(factionLine[i], 3, CopperToString(math.floor(cost*m+.5)))
		m = m - .05
	end
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

do -- Hide from the world
	local OnEvent
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function(_, _, addon)
		if addon ~= name then return end
		Repair.OnLoad()
		f:SetScript("OnEvent", OnEvent)
		f:UnregisterEvent("ADDON_LOADED")
		f:RegisterEvent("PLAYER_DEAD")
		f:RegisterEvent("PLAYER_UNGHOST")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("UPDATE_INVENTORY_ALERTS")
		f:RegisterEvent("MERCHANT_SHOW")
		f:RegisterEvent("MERCHANT_CLOSED")
	end)
	
	OnEvent = function(_, event, ...)
		if event ~= "MERCHANT_SHOW" then
			Repair.UpdateEquippedDurability()
			refreshTooltip = 0
		else
			AutoRepair()
			local updateDurTime = GetTime() + 1
			f:SetScript("OnUpdate", function()
				if updateDurTime < GetTime() then
					-- Update dur
					refreshTooltip = 0
					Repair.UpdateEquippedDurability()
					f:SetScript("OnUpdate", nil)
				end
			end)
		end
	end
end

---------------------------------
-- TOOLTIP
---------------------------------
local anchorTo
Repair.OnTooltipShowInternal = function(GameTooltip)
	if refreshTooltip + 20 > GetTime() then return end

	-- Anchor
	--print("Anchor to: "..(anchorTo:GetName() or "nil.."))
	tooltip:SmartAnchorTo(anchorTo) -- ReAnchor
	
	-- Update information
	Repair.UpdateEquippedDurability()
	Repair.RenderEquippedDurability()
	Repair.UpdateInventoryCost()
	Repair.RenderTotalCost()
	
	refreshTooltip = GetTime()
end
--
function Repair:OnEnter()
	anchorTo = self
	tooltip:Show()
	Repair.OnTooltipShowInternal()
end

function Repair:OnLeave()
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
		refreshTooltip = 0
		Repair.OnEnter(anchorTo)
	end
end

--[[
	Initial code, needs refactoring
	Spreads load over time when scanning inventory
--]]
do
	local gSlot, gBag = 1, 0
	local cost, dur, maxDur = 0, 1, 1
	local f = CreateFrame("Frame")
	local updateRunning = false
	local nextUpdateInventory = 0

	local UpdatePartialInventoryCost = function()
		local endLoop = GetTime() + .01
		
		while gBag < 5 do
		
			-- Cost
			local _, repairCost = GameTooltip:SetBagItem(gBag, gSlot)
			if repairCost then cost = cost + repairCost end
			
			-- Dur
			d, m = GetContainerItemDurability(gBag, gSlot)
			if d and m then dur = dur + d; maxDur = maxDur + m end
		
			-- Make ready for the next round
			gSlot = gSlot + 1
			if gSlot > GetContainerNumSlots(gBag) then
				gBag = gBag + 1
				gSlot = 1
			end
		
			-- Stop loop
			if endLoop < GetTime() then
				GameTooltip:Hide()
				return
			end
		end
		GameTooltip:Hide()
		
		inventoryCost = cost
		
		tooltip:SetCell(inventoryLine, 2, DurabilityText(dur/maxDur))
		tooltip:SetCell(inventoryLine, 3, CopperToString(cost))
		Repair.RenderTotalCost()
		
		updateRunning = false
		f:SetScript("OnUpdate", nil)
	end

	function Repair:UpdateInventoryCost()
		if updateRunning or nextUpdateInventory > GetTime() then return end
		nextUpdateInventory = GetTime() + 2 -- Max update every 2 sec
		updateRunning = true;
		
		-- Start smal
		inventoryCost = 0;
		
		tooltip:SetCell(inventoryLine, 2, "..%")
		tooltip:SetCell(inventoryLine, 3, L["Loading"])
		gSlot, gBag = 1, 0
		cost, dur, maxDur = 0, 1, 1
		
		local nextTime = GetTime()
		f:SetScript("OnUpdate", UpdatePartialInventoryCost)
	end
end

-- Everything is done, register
Repair = LibDataBroker:NewDataObject(name, Repair)