-- TradeScanner_ProfPanel.lua
-- Panneau accolé à la fenêtre de métier (TradeSkillFrame) :
--   - bouton Scan (réindexe le métier ouvert)
--   - bouton Filtre (exclut/réintègre la recette sélectionnée du scan)
--   - case "Only wanted"
--   - liste "qui veut quoi" : mats de désenchantement + produits vendables
--     + enchantements recherchés par les membres de la guilde, avec les joueurs.

local TS = TradeScanner
local PP = {}
TS.ProfPanel = PP

local PANEL_W   = 270
local ROW_H     = 18
local MAX_ROWS  = 26

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------

local function GetOpenProfession()
    local name = TS:GetOpenProfessionInfo()
    if not name then return nil end
    return TS:ResolveProfession(name), name
end

-- ------------------------------------------------------------------
-- Construction du panneau
-- ------------------------------------------------------------------

function PP:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "TradeScannerProfPanel", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_W, 420)
    f:SetFrameStrata("HIGH")
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.09, 0.96)
    f:SetBackdropBorderColor(0.35, 0.35, 0.5, 1)
    f:Hide()

    -- Titre
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cFF00CCFFGuild wants|r")
    self.title = title

    -- Bouton Scan
    local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanBtn:SetSize(70, 20)
    scanBtn:SetPoint("TOPLEFT", 8, -28)
    scanBtn:SetText("Scan")
    scanBtn:SetScript("OnClick", function()
        local count, prof = TS:ScanOpenProfession()
        if prof then
            print(string.format("|cFF00CCFFTradeScanner|r %s: %d recettes indexées.", prof, count))
        end
        PP:Refresh()
    end)
    scanBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText("Réindexe les recettes du métier ouvert", 1, 1, 1)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Bouton Filtre (exclut la recette sélectionnée)
    local filterBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    filterBtn:SetSize(110, 20)
    filterBtn:SetPoint("LEFT", scanBtn, "RIGHT", 6, 0)
    filterBtn:SetText("Filter selected")
    filterBtn:SetScript("OnClick", function()
        local itemID, link = TS:GetSelectedRecipe()
        if not itemID then
            print("|cFF00CCFFTradeScanner|r Sélectionne d'abord une recette.")
            return
        end
        local excluded = TS:ToggleExcluded(itemID)
        local state = excluded and "|cFFFF4444exclu du scan|r" or "|cFF33DD33réintégré|r"
        print("|cFF00CCFFTradeScanner|r " .. (link or itemID) .. " " .. state)
        PP:Refresh()
    end)
    filterBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText("Exclut / réintègre la recette sélectionnée", 1, 1, 1)
        GameTooltip:AddLine("Un item exclu n'est plus proposé comme vendable.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Case "Only wanted"
    local cb = CreateFrame("CheckButton", "TradeScannerOnlyWanted", f, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", 8, -52)
    cb:SetChecked(true)
    self.onlyWanted = true
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text:SetText("Only show needed items")
    cb:SetScript("OnClick", function(b)
        PP.onlyWanted = b:GetChecked()
        PP:Refresh()
    end)

    -- Zone scrollable
    local scroll = CreateFrame("ScrollFrame", "TradeScannerProfScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -78)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(PANEL_W - 34)
    content:SetHeight(MAX_ROWS * ROW_H * 4)
    scroll:SetScrollChild(content)
    self.content = content

    -- Pool de lignes
    self.rows = {}
    for i = 1, MAX_ROWS * 3 do
        self.rows[i] = self:BuildRow(content, i)
    end

    self.frame = f
end

function PP:BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(PANEL_W - 34, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)

    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetPoint("LEFT", 4, 0)
    nameFS:SetWidth(160)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    local cntFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cntFS:SetPoint("RIGHT", -4, 0)
    cntFS:SetWidth(60)
    cntFS:SetJustifyH("RIGHT")
    row.cntFS = cntFS

    row:SetScript("OnEnter", function(r)
        if not r.entry then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if r.isHeader then return end
        if r.entry.isOrder then
            local o = r.entry.order
            if o.itemID then
                pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. o.itemID)
            else
                GameTooltip:SetText(TS.Guild:OrderName(o), 1, 1, 1)
                GameTooltip:AddLine("|cFFCC88FFEnchantement (service)|r")
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("|cFFFFCC00%s|r veut x%d  %s", o.buyer, o.qty or 1, o.priceText or ""), 1, 1, 1)
            if o.status == "accepted" then
                GameTooltip:AddLine("|cFF33DD33Accepté par " .. (o.acceptedBy or "?") .. "|r")
            end
            if r.entry.mineOrder then
                GameTooltip:AddLine("|cFF888888Ta commande — clic = annuler|r")
            else
                GameTooltip:AddLine("|cFF888888Clic = accepter (whisper " .. o.buyer .. ")|r")
            end
            GameTooltip:Show()
            return
        end
        if r.entry.link then
            local hyperlink = r.entry.link:match("|H([^|]+)|h")
            if hyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink) end
        elseif r.entry.itemID then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. r.entry.itemID)
        else
            GameTooltip:AddLine(r.entry.name or "", 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        if r.entry.count and r.entry.count > 0 then
            GameTooltip:AddLine("|cFFFFCC00Player who want this:|r")
            for _, p in ipairs(r.entry.players) do
                GameTooltip:AddLine("  " .. p, 1, 1, 1)
            end
            GameTooltip:AddLine("|cFF888888Clic = whisper " .. (r.entry.players[1] or "") .. "|r")
        else
            GameTooltip:AddLine("|cFF888888Personne ne le demande (encore)|r")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(r)
        if r.entry and r.entry.isOrder then
            local o   = r.entry.order
            local key = TS.Guild:OrderKey(o)
            if r.entry.mineOrder then
                TS.Guild:CancelOrder(o.buyer, key, false)
            else
                TS.Guild:AcceptOrder(o.buyer, key, false)
            end
        elseif r.entry and r.entry.players and r.entry.players[1] then
            ChatFrame_OpenChat("/w " .. r.entry.players[1] .. " ")
        end
    end)

    row:Hide()
    return row
end

-- ------------------------------------------------------------------
-- Remplissage
-- ------------------------------------------------------------------

-- Construit la liste de lignes à afficher (headers + entrées)
function PP:BuildDisplayList(profName)
    local wants = TS:GetGuildWants(profName)
    local list  = {}

    local function addSection(label, color, entries, extraCatalog)
        -- entries déjà triées par count desc
        table.sort(entries, function(a, b) return (a.count or 0) > (b.count or 0) end)

        local rowsToAdd = {}
        local present = {}
        for _, e in ipairs(entries) do
            present[e.itemID or e.name] = true
            table.insert(rowsToAdd, e)
        end
        -- Si "Only wanted" décoché, on complète avec le catalogue (count 0)
        if not self.onlyWanted and extraCatalog then
            for id, nm in pairs(extraCatalog) do
                if not present[id] then
                    table.insert(rowsToAdd, { itemID = id, name = TS:GetItemName(id, nm), players = {}, count = 0 })
                end
            end
        end

        if #rowsToAdd == 0 then return end
        table.insert(list, { isHeader = true, name = label, color = color })
        for _, e in ipairs(rowsToAdd) do
            table.insert(list, e)
        end
    end

    -- Commandes de craft pour ce métier (en haut). Clic = Accept (commande d'un autre)
    -- ou Cancel (ta propre commande, marquée "(moi)").
    if TS.Guild then
        local me     = UnitName("player") or "?"
        local orders = TS.Guild:GetOpenOrders(profName)
        if #orders > 0 then
            table.insert(list, { isHeader = true, name = "|cFF66FF99— Craft orders —|r" })
            for _, o in ipairs(orders) do
                local nm   = TS.Guild:OrderName(o)
                local mine = (o.buyer == me)
                table.insert(list, {
                    isOrder = true, order = o, itemID = o.itemID, mineOrder = mine,
                    name    = nm .. " |cFF888888" .. o.buyer .. (mine and " (moi)" or "") .. "|r",
                    count   = o.qty or 1,
                })
            end
        end
    end

    addSection("|cFF66CCFF— Disenchant —|r", "dis", wants.disenchant,
               (not self.onlyWanted) and TS:GetDisenchantMats(profName) or nil)
    addSection("|cFFFFCC00— Sellable —|r", "sell", wants.sellable, nil)
    addSection("|cFFCC88FF— Enchants —|r", "ench", wants.enchants, nil)

    return list
end

function PP:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local profName, openName = GetOpenProfession()
    if not profName then return end

    self.title:SetText("|cFF00CCFFGuild wants|r — |cFFFFFFFF" .. (openName or profName) .. "|r")

    local list = self:BuildDisplayList(profName)

    for _, row in ipairs(self.rows) do
        row:Hide()
        row.entry = nil
        row.isHeader = nil
    end

    local count = math.min(#list, #self.rows)
    for i = 1, count do
        local item = list[i]
        local row  = self.rows[i]
        row.entry  = item

        if item.isHeader then
            row.isHeader = true
            row.nameFS:SetText(item.name)
            row.cntFS:SetText("")
            row.nameFS:SetWidth(230)
        else
            row.nameFS:SetWidth(160)
            local nm = item.name or (item.itemID and TS:GetItemName(item.itemID)) or "?"
            if item.count and item.count > 0 then
                row.nameFS:SetText(nm)
                row.cntFS:SetText("|cFFFFCC00x" .. item.count .. "|r")
            else
                row.nameFS:SetText("|cFF777777" .. nm .. "|r")
                row.cntFS:SetText("|cFF555555—|r")
            end
        end
        row:Show()
    end

    if count == 0 then
        -- rien à afficher
        local row = self.rows[1]
        row.nameFS:SetWidth(230)
        row.nameFS:SetText("|cFF888888Aucune demande correspondante|r")
        row.cntFS:SetText("")
        row.isHeader = true
        row:Show()
    end
end

-- ------------------------------------------------------------------
-- Ancrage à la fenêtre de métier
-- ------------------------------------------------------------------

function PP:Anchor()
    if not self.frame then return end
    -- S'accroche à la fenêtre réellement ouverte : CraftFrame (Enchantement)
    -- ou TradeSkillFrame (autres métiers)
    local host = TS:IsCraftOpen() and _G.CraftFrame or _G.TradeSkillFrame
    self.frame:ClearAllPoints()
    if host then
        local h = host:GetHeight()
        self.frame:SetHeight(h and h > 100 and h or 420)
        self.frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
    else
        -- Repli : flottant à droite de l'écran
        self.frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
    end
end

function PP:OnTradeSkillShow()
    local profName = GetOpenProfession()
    if not profName then return end
    self:Build()
    self:Anchor()
    self.frame:Show()
    self:Refresh()
end

function PP:OnTradeSkillClose()
    if self.frame then self.frame:Hide() end
end
