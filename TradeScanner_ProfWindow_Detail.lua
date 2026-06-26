-- TradeScanner_ProfWindow_Detail.lua
-- Colonne CENTRE : détail de la recette sélectionnée (icône, réactifs have/need) et
-- boutons Create / Create All. Crafting via TS:CraftRecipe (DoTradeSkill / DoCraft).

local TS = TradeScanner
local PW = TS.ProfWindow
local L  = TS.L

local REAG_H   = 18
local MAX_REAG = 8

-- ------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------

function PW:_BuildReagentRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(228, REAG_H)
    row:SetPoint("TOPLEFT", 10, -(i - 1) * REAG_H)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(REAG_H - 4, REAG_H - 4)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetWidth(140)
    row.nameFS = nameFS

    local cntFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cntFS:SetPoint("RIGHT", 0, 0)
    cntFS:SetJustifyH("RIGHT")
    row.cntFS = cntFS

    row:Hide()
    return row
end

function PW:_BuildDetail(col)
    local iconBig = col:CreateTexture(nil, "ARTWORK")
    iconBig:SetSize(34, 34)
    iconBig:SetPoint("TOPLEFT", 12, -10)
    iconBig:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    iconBig:Hide()
    self.detIcon = iconBig

    local nameFS = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("TOPLEFT", iconBig, "TOPRIGHT", 8, -2)
    nameFS:SetPoint("RIGHT", -10, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetText("|cFF888888" .. L["Select a recipe first."] .. "|r")
    self.detNameFS = nameFS

    local makesFS = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    makesFS:SetPoint("TOPLEFT", iconBig, "BOTTOMRIGHT", 8, -2)
    makesFS:SetTextColor(TS.UI.Skin.unpack(TS.UI.Skin.color.textMuted))
    self.detMakesFS = makesFS

    local reagHdr = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reagHdr:SetPoint("TOPLEFT", 12, -52)
    reagHdr:SetText("|cFFE8B84B" .. L["Reagents:"] .. "|r")
    self.detReagHdr = reagHdr

    local rContainer = CreateFrame("Frame", nil, col)
    rContainer:SetPoint("TOPLEFT", 0, -70)
    rContainer:SetPoint("RIGHT", col, "RIGHT", 0, 0)
    rContainer:SetHeight(MAX_REAG * REAG_H)
    self.detReagRows = {}
    for i = 1, MAX_REAG do self.detReagRows[i] = self:_BuildReagentRow(rContainer, i) end

    local createBtn = TS.UI.Skin.MakeGoldButton(col, 72, 22, "Create")
    createBtn:SetPoint("BOTTOMRIGHT", -10, 12)
    createBtn:SetScript("OnClick", function() PW:_CraftSelected(false) end)
    self.detCreateBtn = createBtn

    local allBtn = TS.UI.Skin.MakeGoldButton(col, 86, 22, "Create All")
    allBtn:SetPoint("BOTTOMRIGHT", createBtn, "BOTTOMLEFT", -6, 0)
    allBtn:SetScript("OnClick", function() PW:_CraftSelected(true) end)
    self.detAllBtn = allBtn

    local qtyBox = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
    qtyBox:SetSize(38, 18)
    qtyBox:SetPoint("RIGHT", allBtn, "LEFT", -12, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetText("1")
    qtyBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    self.detQtyBox = qtyBox

    local qtyLbl = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("RIGHT", qtyBox, "LEFT", -4, 0)
    qtyLbl:SetText(L["Qty"])
    self.detQtyLbl = qtyLbl
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------

function PW:_ClearDetail()
    self.detIcon:Hide()
    self.detNameFS:SetText("|cFF888888" .. L["Select a recipe first."] .. "|r")
    self.detMakesFS:SetText("")
    for _, r in ipairs(self.detReagRows) do r:Hide() end
    self:_SetCraftButtons(false, false)
end

function PW:_SetCraftButtons(canCreate, canAll)
    local function paint(btn, on)
        if not btn then return end
        btn._on = on
        btn.text:SetTextColor(on and 0.941 or 0.45, on and 0.776 or 0.45, on and 0.455 or 0.45)
    end
    paint(self.detCreateBtn, canCreate)
    paint(self.detAllBtn, canAll)
end

function PW:RefreshDetail()
    if not self.detNameFS then return end
    local e = self:GetSelectedRecipe()
    if not e then return self:_ClearDetail() end

    self.detIcon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.detIcon:Show()
    self.detNameFS:SetText(e.link or e.name or "?")

    if (e.numMade or 1) > 1 or (e.numMadeMax or 1) > (e.numMade or 1) then
        local mx = e.numMadeMax or e.numMade
        local made = (mx > e.numMade) and (e.numMade .. "-" .. mx) or tostring(e.numMade)
        self.detMakesFS:SetText(string.format("|cFF888888" .. L["Makes %s"] .. "|r", made))
    else
        self.detMakesFS:SetText("")
    end

    local reags = TS:GetRecipeReagents(e.index)
    for i, row in ipairs(self.detReagRows) do
        local rg = reags[i]
        if rg then
            row.icon:SetTexture(rg.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.nameFS:SetText(rg.name or "?")
            local enough = (rg.have or 0) >= (rg.need or 0)
            local cc = enough and "|cFF33DD33" or "|cFFFF5555"
            row.cntFS:SetText(string.format("%s%d|r|cFF888888/%d|r", cc, rg.have or 0, rg.need or 0))
            row:Show()
        else
            row:Hide()
        end
    end

    local avail   = e.numAvailable or 0
    local isCraft = TS:IsCraftOpen()
    self:_SetCraftButtons(avail > 0, (not isCraft) and avail > 1)
    self.detAllBtn:SetShown(not isCraft)
end

-- ------------------------------------------------------------------
-- Crafting
-- ------------------------------------------------------------------

function PW:_CraftSelected(all)
    local e = self:GetSelectedRecipe()
    if not e then return end
    local avail = e.numAvailable or 0
    if avail <= 0 then
        print("|cFF00CCFFGuild Economy|r " .. L["Not enough reagents."])
        return
    end
    local qty
    if all then
        if TS:IsCraftOpen() then return end
        qty = avail
    else
        qty = tonumber(self.detQtyBox:GetText()) or 1
        if qty < 1 then qty = 1 end
        if qty > avail then qty = avail end
    end
    TS:CraftRecipe(e.index, qty)
end
