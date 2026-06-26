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
    -- Lecture enrichie (fenêtre custom ProfWindow) : difficulté/dispo + icône + réactifs.
    norm        = function(i) local n, t, avail = GetTradeSkillInfo(i); return n, t, avail end,
    getIcon     = function(i) return GetTradeSkillIcon and GetTradeSkillIcon(i) end,
    getNumMade  = function(i) return GetTradeSkillNumMade and GetTradeSkillNumMade(i) end,
    getNumReag  = function(i) return (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0 end,
    getReagInfo = function(i, j) return GetTradeSkillReagentInfo(i, j) end,
    getReagLink = function(i, j) return GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j) end,
    -- DoTradeSkill(index, repeat) : la quantité est honorée nativement.
    craft       = function(i, n) if DoTradeSkill then DoTradeSkill(i, n or 1) end end,
}
local CRAFT_API = {
    getNum      = function() return (GetNumCrafts and GetNumCrafts()) or 0 end,
    getInfo     = function(i) return GetCraftInfo(i) end,
    getLink     = function(i) return GetCraftItemLink and GetCraftItemLink(i) end,
    getSkillName= function() return (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
                                  or (GetCraftName and GetCraftName()) end,
    isHeader    = function(t) return t == "header" end,
    -- GetCraftInfo : nom, sous-texte, type, dispo (ordre différent de TradeSkill).
    norm        = function(i) local n, _, t, avail = GetCraftInfo(i); return n, t, avail end,
    getIcon     = function(i) return GetCraftIcon and GetCraftIcon(i) end,
    getNumMade  = function() return 1, 1 end,  -- un craft produit 1 (pas de NumMade côté Craft)
    getNumReag  = function(i) return (GetCraftNumReagents and GetCraftNumReagents(i)) or 0 end,
    getReagInfo = function(i, j) return GetCraftReagentInfo(i, j) end,
    getReagLink = function(i, j) return GetCraftReagentItemLink and GetCraftReagentItemLink(i, j) end,
    -- DoCraft n'a pas de répétition : 1 par clic (cf. limite enchant).
    craft       = function(i) if DoCraft then DoCraft(i) end end,
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

-- ============================================================
-- LECTURE ENRICHIE POUR LA FENÊTRE CUSTOM (ProfWindow)
-- Marche tant que la SESSION de métier est ouverte, même si la frame Blizzard est
-- masquée (alpha 0) : l'API serveur reste lisible.
-- ============================================================

-- Repli de couleurs si les tables globales Blizzard sont absentes.
local DIFF_COLOR = {
    optimal = { r = 1.00, g = 0.50, b = 0.25 },
    medium  = { r = 1.00, g = 1.00, b = 0.00 },
    easy    = { r = 0.25, g = 0.75, b = 0.25 },
    trivial = { r = 0.50, g = 0.50, b = 0.50 },
}

-- Couleur (r,g,b) d'une difficulté ("optimal"/"medium"/"easy"/"trivial").
function TS:GetDifficultyColor(difficulty)
    local c = (_G.TradeSkillTypeColor and _G.TradeSkillTypeColor[difficulty])
           or (_G.CraftTypeColor and _G.CraftTypeColor[difficulty])
           or DIFF_COLOR[difficulty]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

-- Table d'API du métier ACTUELLEMENT ouvert (ou nil). Réutilise la détection
-- Craft/TradeSkill de GetOpenProfessionInfo.
function TS:GetActiveProfAPI()
    local name, isCraft = self:GetOpenProfessionInfo()
    if not name then return nil end
    return (isCraft and CRAFT_API or TRADESKILL_API), isCraft
end

-- Rang du métier ouvert : skill courant, max. nil si indisponible (l'API Craft n'expose
-- pas de rang → en-tête sans "x/y").
function TS:GetOpenProfessionRank()
    if self:IsCraftOpen() then return nil end
    if GetTradeSkillLine then
        local _, rank, maxRank = GetTradeSkillLine()
        return rank, maxRank
    end
    return nil
end

-- Lit toute la liste de recettes (headers inclus, marqués isHeader=true). nil si fermé.
function TS:ReadOpenRecipes()
    local api = self:GetActiveProfAPI()
    if not api then return nil end
    local out, num = {}, api.getNum()
    for i = 1, num do
        local name, skillType, numAvailable = api.norm(i)
        if name then
            if api.isHeader(skillType) then
                out[#out + 1] = { index = i, name = name, isHeader = true }
            else
                local link    = api.getLink(i)
                local itemID  = link and tonumber(link:match("|Hitem:(%d+)")) or nil
                local mn, mx  = api.getNumMade(i)
                out[#out + 1] = {
                    index = i, name = name, link = link, itemID = itemID,
                    icon = api.getIcon(i), difficulty = skillType,
                    numAvailable = numAvailable or 0,
                    numMade = mn or 1, numMadeMax = mx or mn or 1,
                }
            end
        end
    end
    return out
end

-- Réactifs d'une recette : { name, texture, need, have, link }[].
function TS:GetRecipeReagents(index)
    local api = self:GetActiveProfAPI()
    if not api or not index then return {} end
    local out, n = {}, api.getNumReag(index)
    for j = 1, n do
        local rName, texture, need, have = api.getReagInfo(index, j)
        out[#out + 1] = {
            name = rName, texture = texture,
            need = need or 0, have = have or 0,
            link = api.getReagLink(index, j),
        }
    end
    return out
end

-- Déclenche le craft (DoTradeSkill répété, ou DoCraft simple). count borné par l'appelant.
function TS:CraftRecipe(index, count)
    local api = self:GetActiveProfAPI()
    if not api or not index then return end
    api.craft(index, count or 1)
end
