local LibTooltip = LibStub('LibTooltip-1.0')
local LibDataBroker = LibStub('LibDataBroker-1.1')
if not LibDataBroker then return end

local name = "RepairBroker"
local Repair = LibDataBroker:NewDataObject(name, {
	icon = "Interface\\Icons\\Trade_BlackSmithing",
	label = "Dur",
	text = "100%",
	}
)

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
			useBuildBank = nil, -- nil or 1
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
	if c > 10000 then
		local g = math.floor(c/10000)
		c = c - g*10000
		str = str.."|cFFFFD800"..g.." |TInterface\\MoneyFrame\\UI-GoldIcon.blp:0:0:0:0|t "
	end
	if c > 100 then
		local s = math.floor(c/100)
		c = c - s*100
		str = str.."|cFFC7C7C7"..s.." |TInterface\\MoneyFrame\\UI-SilverIcon.blp:0:0:0:0|t "
	end
	if c > 0 then
		str = str.."|cFFEEA55F"..c.." |TInterface\\MoneyFrame\\UI-CopperIcon.blp:0:0:0:0|t "
	end
	return str
end

---------------------------------
-- Durability updates and repair
---------------------------------
local UpdateDurability = function()
	local dur, max
	local minDur = 1
	for i,info in ipairs(slots) do
		if GetInventoryItemLink("player", info[1]) then
			dur, max = GetInventoryItemDurability(info[1])
			if not dur or max == 0 then
				info[3] = -1
			else
				info[3] = dur/max
				if info[3] < minDur then minDur = info[3] end
			end
		else
			info[3] = -1
		end
	end
	Repair.text = DurabilityColor(minDur)..math.floor(minDur*100).."%"
end

local AutoRepair = function()
	if not RepairBrokerDB.autoRepair then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then return end
	
	-- Use guildbank to repair
	if CanWithdrawGuildBankMoney() and RepairBrokerDB.useBuildBank and GetGuildBankMoney() >= cost then
		RepairAllItems(1)
	elseif GetMoney() >= cost then -- Repair the old fashion way
		RepairAllItems()
		print("Repaired for "..CopperToString(cost))
	else
		print("Unable to AutoRepair, you need "..CopperToString(cost - GetMoney()).." more.")
	end
end

local OnEvent = function(_, event, ...)
	if event ~= "MERCHANT_SHOW" then
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

function Repair:OnEnter()
	if tooltip then Repair:OnLeave() end
	UpdateDurability()
	tooltip = LibTooltip:Acquire("RepairTooltip", 3, "LEFT", "CENTER", "RIGHT")
	tooltip:AddHeader("Equipted items")
	local dur, totalCost, cost = 0, 0, nil
	local gray = "|cFFAAAAAA"
	for i,info in ipairs(slots) do
		dur = math.floor(info[3]*100)
		if dur >= 0 then
			dur = DurabilityColor(info[3])..dur
			dur = dur.."%"
		else
			dur = DurabilityColor(-1).."-  "
		end
		
		cost = select(3, GameTooltip:SetInventoryItem("player", info[1]))
		tooltip:AddLine(
			gray..info[2],	-- Slot
			dur,		-- Dur
			CopperToString(cost) -- Cost
		)
		if cost and cost > 0 then totalCost = totalCost + cost end
	end

	local cost, dur, maxDur = 0, 1, 1
	for bag = 0, 4 do
		for slot = 1, GetContainerNumSlots(bag) do
			-- Cost
			local _, repairCost = GameTooltip:SetBagItem(bag, slot)
			if repairCost then cost = cost + repairCost end
			
			-- Dur
			d, m = GetContainerItemDurability(bag, slot)
			if d and m then dur = dur + d; maxDur = maxDur + m end
		end
	end
	GameTooltip:Hide()
	local averageDur = dur/maxDur
	tooltip:AddHeader(" ")
	tooltip:AddHeader("Inventory")
	tooltip:AddLine(
		gray.."Items in your bags",  -- Slot
		DurabilityColor(averageDur)..math.floor(100*averageDur).."%", -- Dur
		CopperToString(cost) -- Cost
	)
	if cost and cost > 0 then totalCost = totalCost + cost end
	
	if totalCost > 0 then
		tooltip:AddHeader(" ")
		tooltip:AddHeader("Total cost")

		local m = 1
		for i=4, 8 do
			tooltip:AddLine(
				gray.._G["FACTION_STANDING_LABEL"..i],  -- Slot
				" ", -- Dur
				CopperToString(math.floor(totalCost*m+.5)) -- Cost
			)
			m = m - .05
		end
	end
	
	tooltip:SmartAnchorTo(self)
	tooltip:Show()
end

function Repair:OnLeave()
	if not tooltip then return end
	tooltip:Clear()
	LibTooltip:Release(tooltip)
	tooltip = nil
end