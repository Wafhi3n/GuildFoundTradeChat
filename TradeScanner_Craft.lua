-- TradeScanner_Craft.lua
-- Profession window scanning (TradeSkill + Craft APIs) and craft status refresh.

local TS = TradeScanner

function TS:RecordCraftedItem(itemID, itemName, canonicalProf)
    self.craftedItems[itemID] = canonicalProf
    if itemName then
        self.craftedNames[itemName:lower()] = { itemID = itemID, profession = canonicalProf }
    end
end

function TS:IsCraftOpen()
    return CraftFrame and CraftFrame:IsShown()
end

-- Returns itemID, link of the currently selected recipe (works for both APIs).
function TS:GetSelectedRecipe()
    if self:IsCraftOpen() then
        local idx = GetCraftSelectionIndex and GetCraftSelectionIndex()
        if idx and idx > 0 and GetCraftItemLink then
            local link = GetCraftItemLink(idx)
            if link then return tonumber(link:match("|Hitem:(%d+)")), link end
        end
        return nil
    end
    local idx = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
    if not idx or idx < 1 then return nil end
    local link = GetTradeSkillItemLink and GetTradeSkillItemLink(idx)
    if not link then return nil end
    return tonumber(link:match("|Hitem:(%d+)")), link
end

-- Unified reader for the open profession window.
-- In Classic Era, Enchanting/Beast Training use the CRAFT API (not TradeSkill).
-- Returns localizedName, isCraft.
function TS:GetOpenProfessionInfo()
    if CraftFrame and CraftFrame:IsShown() then
        local name = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
                  or (GetCraftName and GetCraftName())
        if name and name ~= "" and name ~= "UNKNOWN" then return name, true end
    end
    if GetTradeSkillLine then
        local name = GetTradeSkillLine()
        if name and name ~= "" and name ~= "UNKNOWN" then return name, false end
    end
    return nil, nil
end

local TRADESKILL_API = {
    getNum      = function() return (GetNumTradeSkills and GetNumTradeSkills()) or 0 end,
    getInfo     = function(i) return GetTradeSkillInfo(i) end,
    getLink     = function(i) return GetTradeSkillItemLink(i) end,
    getSkillName= function() return GetTradeSkillLine and GetTradeSkillLine() end,
    isHeader    = function(t) return t == "header" or t == "subheader" end,
}
local CRAFT_API = {
    getNum      = function() return (GetNumCrafts and GetNumCrafts()) or 0 end,
    getInfo     = function(i) return GetCraftInfo(i) end,
    getLink     = function(i) return GetCraftItemLink and GetCraftItemLink(i) end,
    getSkillName= function() return (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
                                  or (GetCraftName and GetCraftName()) end,
    isHeader    = function(t) return t == "header" end,
}

-- Shared scan loop parameterised by API table (TRADESKILL_API or CRAFT_API).
-- Returns count, canonical (0, nil if profession unavailable or UNKNOWN).
function TS:ScanRecipes(api)
    local skillName = api.getSkillName()
    if not skillName or skillName == "" or skillName == "UNKNOWN" then return 0, nil end
    local canonical = self:ResolveProfession(skillName)
    local num, count = api.getNum(), 0
    for i = 1, num do
        local name, skillType
        if api == TRADESKILL_API then
            name, skillType = api.getInfo(i)
        else
            name, _, skillType = api.getInfo(i)
        end
        if name and not api.isHeader(skillType) then
            local link = api.getLink(i)
            if link then
                local itemID = tonumber(link:match("|Hitem:(%d+)"))
                if itemID then
                    self:RecordCraftedItem(itemID, link:match("|h%[(.-)%]|h"), canonical)
                    count = count + 1
                end
            end
        end
    end
    return count, canonical
end

-- Scans the open profession window regardless of API. Calls RefreshCraftStatus once.
function TS:ScanOpenProfession()
    local _, isCraft = self:GetOpenProfessionInfo()
    local count, canonical = self:ScanRecipes(isCraft and CRAFT_API or TRADESKILL_API)
    if count > 0 then self:RefreshCraftStatus() end
    return count, canonical
end

function TS:RefreshCraftStatus()
    for _, offer in ipairs(self.db.offers) do
        if offer.itemID then
            local cat, prof = self:GetProducible(offer.itemID)
            offer.canCraft     = cat ~= nil
            offer.sellCategory = cat
            offer.profession   = prof
        end
    end
    if self.UI then self.UI:Refresh() end
    if self.ProfPanel and self.ProfPanel.Refresh then self.ProfPanel:Refresh() end
end

function TS:GetCraftedProfessions()
    local profs = {}
    for _, profName in pairs(self.craftedItems) do
        profs[profName] = (profs[profName] or 0) + 1
    end
    return profs
end
