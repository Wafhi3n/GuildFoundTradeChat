-- TradeScanner_OrderPanel_Rows.lua
-- Constructeurs de lignes pour OrderPanel (catalogue et commandes).
-- Chargé après TradeScanner_OrderPanel.lua.

local TS  = TradeScanner
local OP  = TS.OrderPanel
local L   = TS.L
local ROW_H = 16

-- ------------------------------------------------------------------
-- Lignes catalogue
-- ------------------------------------------------------------------
function OP:BuildCatRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(280, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    local hi = row:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints(); hi:SetColorTexture(0.3, 0.5, 0.9, 0.25)
    local sel = row:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints(); sel:SetColorTexture(0.9, 0.8, 0.2, 0.2); sel:Hide()
    row.sel = sel
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 4, 0); fs:SetWidth(270); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    row.fs = fs
    row:SetScript("OnClick", function(r) if r.entry then OP:SelectEntry(r.entry) end end)
    row:SetScript("OnEnter", function(r)
        local e = r.entry
        if not e then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if e.itemID then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.itemID)
        elseif e.enchantID then
            GameTooltip:SetText(e.name or "?", 1, 1, 1)
            GameTooltip:AddLine("|cFF888888" .. L["Enchantment (service)"] .. "|r")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:Hide()
    return row
end

-- ------------------------------------------------------------------
-- Lignes commandes
-- ------------------------------------------------------------------
function OP:BuildOrdRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(260, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", 2, 0); fs:SetWidth(190); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    row.fs = fs
    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetSize(56, 14); btn:SetPoint("RIGHT", 0, 0)
    row.btn = btn
    row:Hide()
    return row
end

-- ------------------------------------------------------------------
-- Liste affichée de l'onglet Orders (headers + commandes + demandes chat)
-- ------------------------------------------------------------------
function OP:BuildOrderList(prof, me)
    local rows = {}
    local mine = TS.Guild:GetMyOrders()
    if #mine > 0 then
        rows[#rows + 1] = { header = "|cFF66CCFF" .. L["— My orders —"] .. "|r" }
        for _, o in ipairs(mine) do rows[#rows + 1] = { order = o, mine = true } end
    end
    local open = TS.Guild:GetOpenOrders(prof)
    rows[#rows + 1] = { header = "|cFFFFCC00" .. string.format(L["— Open (%s) —"], prof or "?") .. "|r" }
    for _, o in ipairs(open) do
        if o.buyer ~= me then rows[#rows + 1] = { order = o } end
    end
    -- WTB du chat dont l'item est craftable dans ce métier (demandes informelles)
    local reqs = TS:GetCraftableWantsFor(prof)
    if #reqs > 0 then
        rows[#rows + 1] = { header = "|cFF88FF88" ..
            string.format(L["— Chat requests (%s) —"], prof or "?") .. "|r" }
        for _, o in ipairs(reqs) do rows[#rows + 1] = { request = o } end
    end
    return rows
end
