-- TradeScanner_OrderPanel.lua
-- Panneau autonome "Guild Craft Orders" (ouvert par /ts order).
--   - onglets des métiers connus dans la guilde
--   - catalogue statique du métier sélectionné (recherche par nom)
--   - sélection d'un item → quantité + prix → bouton Order (diffuse une commande)
--   - colonne de droite : mes commandes (Cancel) + commandes ouvertes (Accept)

local TS = TradeScanner
local OP = {}
TS.OrderPanel = OP

local W, H        = 640, 470
local ROW_H       = 16
local CAT_ROWS    = 18
local ORD_ROWS    = 18

-- ------------------------------------------------------------------
-- Construction
-- ------------------------------------------------------------------
function OP:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "TradeScannerOrderPanel", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF00CCFFGuild Craft Orders|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Rangée d'onglets métiers (créés dynamiquement dans RefreshTabs)
    self.tabs = {}
    self.tabContainer = CreateFrame("Frame", nil, f)
    self.tabContainer:SetPoint("TOPLEFT", 14, -38)
    self.tabContainer:SetSize(W - 28, 44)

    -- Barre de recherche
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 16, -86)
    searchLabel:SetText("Search:")
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(180, 18)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(b) OP.searchText = b:GetText():lower(); OP:RefreshCatalog() end)
    search:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    self.search = search

    -- En-têtes de colonnes
    local catHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHdr:SetPoint("TOPLEFT", 16, -112)
    catHdr:SetText("|cFFFFCC00Catalogue|r")
    local ordHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ordHdr:SetPoint("TOPLEFT", 330, -112)
    ordHdr:SetText("|cFFFFCC00Commandes|r")

    -- Colonne catalogue (scroll virtuel : seules CAT_ROWS lignes, repositionnées au défilement)
    local catScroll = CreateFrame("ScrollFrame", "TradeScannerOrderCatScroll", f, "UIPanelScrollFrameTemplate")
    catScroll:SetPoint("TOPLEFT", 16, -130)
    catScroll:SetSize(290, CAT_ROWS * ROW_H)
    local catContent = CreateFrame("Frame", nil, catScroll)
    catContent:SetSize(290, CAT_ROWS * ROW_H)
    catScroll:SetScrollChild(catContent)
    self.catScroll  = catScroll
    self.catContent = catContent
    catScroll:HookScript("OnVerticalScroll", function() OP:RenderCatalog() end)
    self.catRows = {}
    for i = 1, CAT_ROWS do self.catRows[i] = self:BuildCatRow(catContent, i) end

    -- Colonne commandes (scroll)
    local ordScroll = CreateFrame("ScrollFrame", "TradeScannerOrderOrdScroll", f, "UIPanelScrollFrameTemplate")
    ordScroll:SetPoint("TOPLEFT", 330, -130)
    ordScroll:SetSize(270, ORD_ROWS * ROW_H)
    local ordContent = CreateFrame("Frame", nil, ordScroll)
    ordContent:SetSize(270, ORD_ROWS * ROW_H * 4)
    ordScroll:SetScrollChild(ordContent)
    self.ordRows = {}
    for i = 1, ORD_ROWS * 3 do self.ordRows[i] = self:BuildOrdRow(ordContent, i) end

    -- Barre du bas : item sélectionné + qty + prix + Order
    local selLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selLabel:SetPoint("BOTTOMLEFT", 16, 18)
    selLabel:SetText("|cFF888888Sélectionne un item…|r")
    self.selLabel = selLabel

    local orderBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    orderBtn:SetSize(70, 22)
    orderBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    orderBtn:SetText("Order")
    orderBtn:SetScript("OnClick", function() OP:SubmitOrder() end)

    local priceBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    priceBox:SetSize(70, 18)
    priceBox:SetPoint("RIGHT", orderBtn, "LEFT", -12, 0)
    priceBox:SetAutoFocus(false)
    priceBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    self.priceBox = priceBox
    local priceLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLbl:SetPoint("RIGHT", priceBox, "LEFT", -4, 0)
    priceLbl:SetText("Prix")

    local qtyBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    qtyBox:SetSize(40, 18)
    qtyBox:SetPoint("RIGHT", priceLbl, "LEFT", -8, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetText("1")
    qtyBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    self.qtyBox = qtyBox
    local qtyLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("RIGHT", qtyBox, "LEFT", -4, 0)
    qtyLbl:SetText("Qté")

    self.frame = f
end

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
            GameTooltip:AddLine("|cFF888888Enchantement (service)|r")
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
-- Sélection métier / item
-- ------------------------------------------------------------------
function OP:SelectProfession(prof)
    self.currentProf = prof
    self:Refresh()
end

-- entry = { itemID=, name= } (item)  ou  { enchantID=, name= } (enchant)
function OP:SelectEntry(entry)
    self.selEntry = entry
    local disp = entry.itemID and TS:GetItemName(entry.itemID, entry.name) or entry.name
    self.selLabel:SetText("Sélectionné : |cFFFFFFFF" .. (disp or "?")
        .. (entry.enchantID and " |cFFCC88FF(ench.)|r" or "") .. "|r")
    self:RefreshCatalog()
end

function OP:SubmitOrder()
    local e = self.selEntry
    if not e then
        print("|cFF00CCFFTradeScanner|r Sélectionne d'abord un item dans le catalogue.")
        return
    end
    local qty = tonumber(self.qtyBox:GetText()) or 1
    if qty < 1 then qty = 1 end
    local priceText, priceValue = TS:ParsePrice(self.priceBox:GetText() or "")
    if e.enchantID then
        TS.Guild:PlaceEnchantOrder(e.enchantID, e.name, e.profession or self.currentProf, qty, priceValue, priceText)
    else
        TS.Guild:PlaceItemOrder(e.itemID, qty, priceValue, priceText)
    end
    self.priceBox:SetText("")
end

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
function OP:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:RefreshTabs()
    self:RefreshCatalog()
    self:RefreshOrders()
end

function OP:RefreshTabs()
    -- Tous les métiers du catalogue : on doit pouvoir commander n'importe quoi,
    -- même un métier que personne en ligne ne possède (cf. "j'ai besoin d'une potion").
    local seen, profs = {}, {}
    for p in pairs(TS.staticByProfession or {})   do if not seen[p] then seen[p]=true; profs[#profs+1]=p end end
    for p in pairs(TS.enchantsByProfession or {}) do if not seen[p] then seen[p]=true; profs[#profs+1]=p end end
    table.sort(profs)
    -- défaut : 1er métier
    if not self.currentProf and profs[1] then self.currentProf = profs[1] end

    for _, t in ipairs(self.tabs) do t:Hide() end
    local x, rowIdx = 0, 0
    for i, prof in ipairs(profs) do
        local t = self.tabs[i]
        if not t then
            t = CreateFrame("Button", nil, self.tabContainer, "UIPanelButtonTemplate")
            t:SetHeight(20)
            self.tabs[i] = t
        end
        t:SetText(prof)
        t:SetWidth(math.max(60, t:GetFontString():GetStringWidth() + 16))
        if i > 1 and x + t:GetWidth() > (W - 36) then
            x = 0
            rowIdx = rowIdx + 1
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.tabContainer, "TOPLEFT", x, -rowIdx * 22)
        x = x + t:GetWidth() + 4
        local isSel = (prof == self.currentProf)
        t:SetNormalFontObject(isSel and "GameFontHighlight" or "GameFontNormalSmall")
        t:SetScript("OnClick", function() OP:SelectProfession(prof) end)
        t:Show()
    end
    self.tabContainer:SetHeight(math.max(22, (rowIdx + 1) * 22))
end

function OP:RefreshCatalog()
    if not self.frame or not self.frame:IsShown() then return end
    local prof    = self.currentProf
    local items   = (prof and TS.staticByProfession[prof]) or {}
    local enchs   = (prof and TS.enchantsByProfession and TS.enchantsByProfession[prof]) or {}
    local search  = self.searchText
    local function matches(s) return not search or search == "" or s:lower():find(search, 1, true) end

    local list = {}
    for itemID, name in pairs(items) do
        local disp = TS:GetItemName(itemID, name)
        if matches(disp) then list[#list + 1] = { itemID = itemID, name = disp } end
    end
    for _, e in ipairs(enchs) do
        -- profession stockée ici pour SubmitOrder (fix mauvais métier si onglet changé)
        if e.name and matches(e.name) then
            list[#list + 1] = { enchantID = e.id, name = e.name, profession = prof }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)

    self.catList = list
    if self.catContent then
        self.catContent:SetHeight(math.max(#list * ROW_H, CAT_ROWS * ROW_H))
    end
    if self.catScroll then self.catScroll:SetVerticalScroll(0) end
    self:RenderCatalog()
end

-- Affiche le sous-ensemble visible du catalogue (scroll virtuel).
function OP:RenderCatalog()
    local list      = self.catList or {}
    local scrollOff = self.catScroll and math.floor(self.catScroll:GetVerticalScroll() / ROW_H) or 0
    local selKey    = self.selEntry and (
        self.selEntry.itemID    and ("i" .. self.selEntry.itemID)   or
        self.selEntry.enchantID and ("e" .. self.selEntry.enchantID)
    )
    for i = 1, #self.catRows do
        local row     = self.catRows[i]
        local listIdx = scrollOff + i
        local it      = list[listIdx]
        if it then
            row.entry = it
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(listIdx - 1) * ROW_H)
            row.fs:SetText(it.enchantID and ("|cFFCC88FF" .. it.name .. "|r") or it.name)
            local key = it.itemID and ("i" .. it.itemID) or ("e" .. it.enchantID)
            row.sel:SetShown(selKey == key)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

function OP:RefreshOrders()
    if not self.frame or not self.frame:IsShown() then return end
    local me = UnitName("player") or "?"
    local rows = {}  -- liste affichée : headers + commandes

    local mine = TS.Guild:GetMyOrders()
    if #mine > 0 then
        rows[#rows + 1] = { header = "|cFF66CCFF— Mes commandes —|r" }
        for _, o in ipairs(mine) do rows[#rows + 1] = { order = o, mine = true } end
    end
    local open = TS.Guild:GetOpenOrders(self.currentProf)
    rows[#rows + 1] = { header = "|cFFFFCC00— Ouvertes (" .. (self.currentProf or "?") .. ") —|r" }
    for _, o in ipairs(open) do
        if o.buyer ~= me then rows[#rows + 1] = { order = o } end
    end

    for i = 1, #self.ordRows do
        local row = self.ordRows[i]
        local item = rows[i]
        if not item then row:Hide()
        elseif item.header then
            row.fs:SetText(item.header); row.fs:SetWidth(258)
            row.btn:Hide(); row:Show()
        else
            local o   = item.order
            local key = TS.Guild:OrderKey(o)
            local nm  = TS.Guild:OrderName(o)
            local accepted = o.status == "accepted" and (" |cFF33DD33[" .. (o.acceptedBy or "?") .. "]|r") or ""
            row.fs:SetWidth(190)
            row.fs:SetText(string.format("%s x%d %s%s",
                nm, o.qty or 1, o.priceText and ("|cFFFFCC00" .. o.priceText .. "|r") or "", accepted))
            row.btn:Show()
            if item.mine then
                row.btn:SetText("Cancel")
                row.btn:SetScript("OnClick", function() TS.Guild:CancelOrder(o.buyer, key, false) end)
            else
                row.btn:SetText("Accept")
                row.btn:SetScript("OnClick", function() TS.Guild:AcceptOrder(o.buyer, key, false) end)
            end
            row:Show()
        end
    end
end

-- ------------------------------------------------------------------
-- Toggle
-- ------------------------------------------------------------------
function OP:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        self:Refresh()
    end
end
