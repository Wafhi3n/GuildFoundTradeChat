-- TradeScanner_ProfWindow_Recipes.lua
-- Colonne GAUCHE : liste de recettes virtualisée (scroll), recherche, couleur par
-- difficulté, sélection, badge "demandé" (rempli par _Wants via wantedMap).

local TS = TradeScanner
local PW = TS.ProfWindow
local L  = TS.L

local ROW_H   = 16
local VISIBLE = 23

-- ------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------

function PW:_BuildRecipeRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(196, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    sel:SetColorTexture(0.91, 0.72, 0.29, 0.22)
    sel:Hide()
    row.sel = sel

    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_H - 2, ROW_H - 2)
    icon:SetPoint("LEFT", 1, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameFS:SetPoint("RIGHT", -2, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("RIGHT", -2, 0)
    badge:Hide()
    row.badge = badge

    row:SetScript("OnClick", function(r)
        if r.entry and not r.entry.isHeader then PW:SelectRecipe(r.entry.index) end
    end)
    row:SetScript("OnEnter", function(r) PW:_RecipeTooltip(r) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:Hide()
    return row
end

function PW:_BuildRecipes(col)
    local hdr = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 8, -6)
    hdr:SetText("|cFFE8B84BRecipes|r")

    local search = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
    search:SetSize(120, 16)
    search:SetPoint("TOPRIGHT", -10, -6)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(b)
        PW.recipeSearch = (b:GetText() or ""):lower()
        PW:RefreshRecipes()
    end)
    search:SetScript("OnEscapePressed", function(b) b:SetText(""); b:ClearFocus() end)
    self.recipeSearchBox = search

    local scroll = CreateFrame("ScrollFrame", "TradeScannerProfWinRecScroll", col, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -26)
    scroll:SetPoint("BOTTOMRIGHT", -24, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(196, VISIBLE * ROW_H)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() PW:RenderRecipes() end)
    self.recScroll  = scroll
    self.recContent = content

    self.recRows = {}
    for i = 1, VISIBLE do self.recRows[i] = self:_BuildRecipeRow(content, i) end
end

-- ------------------------------------------------------------------
-- Tooltip
-- ------------------------------------------------------------------

function PW:_RecipeTooltip(row)
    local e = row.entry
    if not e or e.isHeader then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local ok = false
    if e.link then
        ok = pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
    elseif TS:IsCraftOpen() then
        ok = pcall(GameTooltip.SetCraftSpell, GameTooltip, e.index)
    else
        ok = pcall(GameTooltip.SetTradeSkillItem, GameTooltip, e.index)
    end
    if not ok then GameTooltip:SetText(e.name or "?", 1, 1, 1) end
    GameTooltip:Show()
end

-- ------------------------------------------------------------------
-- Liste d'affichage + rendu virtuel
-- ------------------------------------------------------------------

function PW:_RecipeDisplayList()
    local raw    = self.recipes or {}
    local search = self.recipeSearch
    if not search or search == "" then return raw end
    local list = {}
    for _, r in ipairs(raw) do
        if not r.isHeader and r.name and r.name:lower():find(search, 1, true) then
            list[#list + 1] = r
        end
    end
    return list
end

function PW:RefreshRecipes()
    if not self.recScroll then return end
    self.wantedMap = self._ComputeWantedMap and self:_ComputeWantedMap() or nil
    self.recDisplay = self:_RecipeDisplayList()
    local n = #self.recDisplay
    if self.recContent then
        self.recContent:SetHeight(math.max(n * ROW_H, VISIBLE * ROW_H))
    end
    self:RenderRecipes()
end

function PW:RenderRecipes()
    local list = self.recDisplay or {}
    local off  = self.recScroll and math.floor(self.recScroll:GetVerticalScroll() / ROW_H) or 0
    for i = 1, #self.recRows do
        local row     = self.recRows[i]
        local listIdx = off + i
        local e       = list[listIdx]
        if e then
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(listIdx - 1) * ROW_H)
            row:SetPoint("RIGHT", self.recContent, "RIGHT", -2, 0)
            self:_FillRecipeRow(row, e)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

function PW:_FillRecipeRow(row, e)
    if e.isHeader then
        row.icon:Hide()
        row.badge:Hide()
        row.sel:Hide()
        row.nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.nameFS:SetText("|cFFE8B84B" .. (e.name or "") .. "|r")
        return
    end
    row.icon:Show()
    row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.nameFS:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)

    local r, g, b = TS:GetDifficultyColor(e.difficulty)
    local label = e.name or "?"
    if (e.numAvailable or 0) > 0 then
        label = string.format("%s |cFF888888[%d]|r", label, e.numAvailable)
    end
    row.nameFS:SetText(label)
    row.nameFS:SetTextColor(r, g, b)

    row.sel:SetShown(self.selectedIndex == e.index)

    local w = self.wantedMap and e.itemID and self.wantedMap[e.itemID]
    if w and w.count and w.count > 0 then
        row.badge:SetText(string.format("|cFFFFCC00x%d|r", w.count))
        row.badge:Show()
    else
        row.badge:Hide()
    end
end

-- ------------------------------------------------------------------
-- Sélection
-- ------------------------------------------------------------------

function PW:SelectRecipe(index)
    self.selectedIndex = index
    self:RenderRecipes()
    if self.RefreshDetail then self:RefreshDetail() end
end

function PW:GetSelectedRecipe()
    if not self.selectedIndex or not self.recipes then return nil end
    for _, r in ipairs(self.recipes) do
        if r.index == self.selectedIndex and not r.isHeader then return r end
    end
    return nil
end
