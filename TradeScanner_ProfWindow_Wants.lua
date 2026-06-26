-- TradeScanner_ProfWindow_Wants.lua
-- Colonne DROITE : "Guild wants" — commandes de craft (Accept/Cancel/Validate),
-- mats de désenchantement, objets vendables et enchantements recherchés par la guilde.
-- Logique portée depuis TradeScanner_ProfPanel.

local TS = TradeScanner
local PW = TS.ProfWindow
local L  = TS.L

local ROW_H   = 18
local VISIBLE = 20

local function canonicalProf()
    local openName = TS:GetOpenProfessionInfo()
    if not openName then return nil end
    return TS:ResolveProfession(openName), openName
end

-- ------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------

function PW:_BuildWantRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(220, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetPoint("LEFT", 4, 0)
    nameFS:SetWidth(150)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    local cntFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cntFS:SetPoint("RIGHT", -4, 0)
    cntFS:SetWidth(50)
    cntFS:SetJustifyH("RIGHT")
    row.cntFS = cntFS

    local actionBtn = TS.UI.Skin.MakeGoldButton(row, 54, 14)
    actionBtn:SetPoint("RIGHT", -2, 0)
    actionBtn:Hide()
    row.actionBtn = actionBtn

    row:SetScript("OnEnter", function(r) PW:_WantTooltip(r) end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(r)
        if r.entry and r.entry.isOrder then return end
        if r.entry and r.entry.players and r.entry.players[1] then
            ChatFrame_OpenChat("/w " .. r.entry.players[1] .. " ")
        end
    end)
    row:Hide()
    return row
end

function PW:_BuildWants(col)
    local hdr = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 8, -6)
    hdr:SetText("|cFF00CCFFGuild wants|r")
    self.wantHdr = hdr

    local cb = CreateFrame("CheckButton", "TradeScannerProfWinOnlyWanted", col, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetPoint("TOPLEFT", 6, -24)
    cb:SetChecked(true)
    self.onlyWanted = true
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText(L["Only show needed items"])
    cb:SetScript("OnClick", function(b)
        PW.onlyWanted = b:GetChecked()
        PW:RefreshWants()
        PW:RefreshRecipes()
    end)

    local scroll = CreateFrame("ScrollFrame", "TradeScannerProfWinWantScroll", col, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -46)
    scroll:SetPoint("BOTTOMRIGHT", -24, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(220, VISIBLE * ROW_H)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() PW:RenderWants() end)
    self.wantScroll  = scroll
    self.wantContent = content

    self.wantRows = {}
    for i = 1, VISIBLE do self.wantRows[i] = self:_BuildWantRow(content, i) end
end

-- ------------------------------------------------------------------
-- Liste d'affichage (orders + disenchant + sellable + enchants)
-- ------------------------------------------------------------------

function PW:_WantsDisplayList(profName)
    local wants = TS:GetGuildWants(profName)
    local list  = {}

    local function addSection(label, entries, extraCatalog)
        table.sort(entries, function(a, b) return (a.count or 0) > (b.count or 0) end)
        local rowsToAdd, present = {}, {}
        for _, e in ipairs(entries) do
            present[e.itemID or e.name] = true
            rowsToAdd[#rowsToAdd + 1] = e
        end
        if not self.onlyWanted and extraCatalog then
            for id, nm in pairs(extraCatalog) do
                if not present[id] then
                    rowsToAdd[#rowsToAdd + 1] =
                        { itemID = id, name = TS:GetItemName(id, nm), players = {}, count = 0 }
                end
            end
        end
        if #rowsToAdd == 0 then return end
        list[#list + 1] = { isHeader = true, name = label }
        for _, e in ipairs(rowsToAdd) do list[#list + 1] = e end
    end

    if TS.Guild then
        local me     = UnitName("player") or "?"
        local orders = TS.Guild:GetOpenOrders(profName)
        if #orders > 0 then
            list[#list + 1] = { isHeader = true, name = "|cFF66FF99— " .. L["Craft orders"] .. " —|r" }
            for _, o in ipairs(orders) do
                local nm   = TS.Guild:OrderName(o)
                local mine = (o.buyer == me)
                list[#list + 1] = {
                    isOrder = true, order = o, itemID = o.itemID, mineOrder = mine,
                    name    = nm .. " |cFF888888" .. o.buyer .. (mine and " (moi)" or "") .. "|r",
                    count   = o.qty or 1,
                }
            end
        end
    end

    addSection("|cFF66CCFF— " .. L["Disenchant"] .. " —|r", wants.disenchant,
               (not self.onlyWanted) and TS:GetDisenchantMats(profName) or nil)
    addSection("|cFFFFCC00— " .. L["Sellable"] .. " —|r", wants.sellable, nil)
    addSection("|cFFCC88FF— " .. L["Enchants"] .. " —|r", wants.enchants, nil)
    return list
end

-- Carte itemID → { count } pour les badges des lignes de recettes (col. gauche).
function PW:_ComputeWantedMap()
    local profName = canonicalProf()
    if not profName then return nil end
    local map   = {}
    local wants = TS:GetGuildWants(profName)
    for _, e in ipairs(wants.sellable) do
        if e.itemID and (e.count or 0) > 0 then
            map[e.itemID] = { count = (map[e.itemID] and map[e.itemID].count or 0) + e.count }
        end
    end
    if TS.Guild then
        for _, o in ipairs(TS.Guild:GetOpenOrders(profName)) do
            if o.itemID then
                map[o.itemID] = { count = (map[o.itemID] and map[o.itemID].count or 0) + (o.qty or 1) }
            end
        end
    end
    return map
end

-- ------------------------------------------------------------------
-- Refresh / rendu virtuel
-- ------------------------------------------------------------------

function PW:RefreshWants()
    if not self.wantScroll then return end
    local profName = canonicalProf()
    self.wantList = profName and self:_WantsDisplayList(profName) or {}
    if self.wantContent then
        self.wantContent:SetHeight(math.max(#self.wantList * ROW_H, VISIBLE * ROW_H))
    end
    self:RenderWants()
end

function PW:RenderWants()
    local list = self.wantList or {}
    local off  = self.wantScroll and math.floor(self.wantScroll:GetVerticalScroll() / ROW_H) or 0
    for i = 1, #self.wantRows do
        local row     = self.wantRows[i]
        local listIdx = off + i
        local e       = list[listIdx]
        if e then
            row.entry = e
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(listIdx - 1) * ROW_H)
            row:SetPoint("RIGHT", self.wantContent, "RIGHT", -2, 0)
            self:_FillWantRow(row, e)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    if #list == 0 then
        local row = self.wantRows[1]
        if row then
            row.entry = nil
            row.actionBtn:Hide()
            row.nameFS:SetWidth(210)
            row.nameFS:SetText("|cFF888888" .. L["No matching requests"] .. "|r")
            row.cntFS:SetText("")
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, 0)
            row:Show()
        end
    end
end

function PW:_FillWantRow(row, item)
    row.actionBtn:Hide()
    if item.isHeader then
        row.nameFS:SetWidth(212); row.nameFS:SetText(item.name); row.cntFS:SetText("")
        return
    end
    if item.isOrder then
        local o   = item.order
        local key = TS.Guild:OrderKey(o)
        local me  = UnitName("player") or "?"
        row.nameFS:SetWidth(150); row.nameFS:SetText(item.name); row.cntFS:SetText("")
        local btn = row.actionBtn; btn:Show()
        if o.status == "accepted" and (o.acceptedBy == me or o.buyer == me) then
            btn:SetText(L["Validate"])
            btn:SetScript("OnClick", function() TS.Guild:FulfillOrder(o.buyer, key, nil, false, false) end)
        elseif item.mineOrder then
            btn:SetText("Cancel")
            btn:SetScript("OnClick", function() TS.Guild:CancelOrder(o.buyer, key, false) end)
        else
            btn:SetText("Accept")
            btn:SetScript("OnClick", function() TS.Guild:AcceptOrder(o.buyer, key, false) end)
        end
        return
    end
    row.nameFS:SetWidth(160)
    local nm = item.name or (item.itemID and TS:GetItemName(item.itemID)) or "?"
    if item.count and item.count > 0 then
        row.nameFS:SetText(nm); row.cntFS:SetText("|cFFFFCC00x" .. item.count .. "|r")
    else
        row.nameFS:SetText("|cFF777777" .. nm .. "|r"); row.cntFS:SetText("|cFF555555—|r")
    end
end

-- ------------------------------------------------------------------
-- Tooltip (porté de ProfPanel)
-- ------------------------------------------------------------------

function PW:_WantTooltip(row)
    local e = row.entry
    if not e or e.isHeader then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    if e.isOrder then
        local o = e.order
        if o.itemID then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. o.itemID)
        else
            GameTooltip:SetText(TS.Guild:OrderName(o), 1, 1, 1)
            GameTooltip:AddLine("|cFFCC88FF" .. L["Enchantment (service)"] .. "|r")
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|cFFFFCC00%s|r veut x%d  %s",
            o.buyer, o.qty or 1, o.priceText or ""), 1, 1, 1)
        local me = UnitName("player") or "?"
        if o.status == "accepted" then
            GameTooltip:AddLine("|cFF33DD33" .. L["Accepted by "] .. (o.acceptedBy or "?") .. "|r")
        end
        if e.mineOrder then
            GameTooltip:AddLine("|cFF888888" .. L["Your order — click to cancel"] .. "|r")
        elseif not (o.status == "accepted") then
            GameTooltip:AddLine("|cFF888888" .. string.format(L["Click to accept (whisper %s)"], o.buyer) .. "|r")
        end
        GameTooltip:Show()
        return
    end
    if e.itemID then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.itemID)
    else
        GameTooltip:AddLine(e.name or "", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if e.count and e.count > 0 and e.players then
        GameTooltip:AddLine("|cFFFFCC00" .. L["Player who want this:"] .. "|r")
        for _, p in ipairs(e.players) do GameTooltip:AddLine("  " .. p, 1, 1, 1) end
    else
        GameTooltip:AddLine("|cFF888888" .. L["No one is asking for this (yet)"] .. "|r")
    end
    GameTooltip:Show()
end
