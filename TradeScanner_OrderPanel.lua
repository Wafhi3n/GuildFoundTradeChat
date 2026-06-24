-- TradeScanner_OrderPanel.lua
-- Panneau autonome "Guild Craft Orders" (ouvert par /ts order).
--   - onglets des métiers connus dans la guilde
--   - catalogue statique du métier sélectionné (recherche par nom)
--   - sélection d'un item → quantité + prix → bouton Order (diffuse une commande)
--   - colonne de droite : mes commandes (Cancel) + commandes ouvertes (Accept)

local TS = TradeScanner
local OP = {}
TS.OrderPanel = OP
local L  = TS.L

local W, H        = 640, 470
local ROW_H       = 16
local CAT_ROWS    = 18
local ORD_ROWS    = 18

function OP:_BuildCatalogPanel(f)
    local catHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHdr:SetPoint("TOPLEFT", 16, -112)
    catHdr:SetText("|cFFFFCC00Catalogue|r")
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
end

function OP:_BuildOrderPanel(f)
    local ordHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ordHdr:SetPoint("TOPLEFT", 330, -112)
    ordHdr:SetText("|cFFFFCC00" .. L["Orders"] .. "|r")
    local ordScroll = CreateFrame("ScrollFrame", "TradeScannerOrderOrdScroll", f, "UIPanelScrollFrameTemplate")
    ordScroll:SetPoint("TOPLEFT", 330, -130)
    ordScroll:SetSize(270, ORD_ROWS * ROW_H)
    local ordContent = CreateFrame("Frame", nil, ordScroll)
    ordContent:SetSize(270, ORD_ROWS * ROW_H * 4)
    ordScroll:SetScrollChild(ordContent)
    self.ordRows = {}
    for i = 1, ORD_ROWS * 3 do self.ordRows[i] = self:BuildOrdRow(ordContent, i) end
end

function OP:_BuildBottomBar(f)
    local selLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selLabel:SetPoint("BOTTOMLEFT", 16, 18)
    selLabel:SetText("|cFF888888" .. L["Select an item..."] .. "|r")
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
    priceLbl:SetText(L["Price"])
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
    qtyLbl:SetText(L["Qty"])
end

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

    self.tabs = {}
    self.tabContainer = CreateFrame("Frame", nil, f)
    self.tabContainer:SetPoint("TOPLEFT", 14, -38)
    self.tabContainer:SetSize(W - 28, 44)

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

    self:_BuildCatalogPanel(f)
    self:_BuildOrderPanel(f)
    self:_BuildBottomBar(f)

    self.frame = f
end

-- ------------------------------------------------------------------
-- Sélection métier / item
-- ------------------------------------------------------------------
function OP:SelectProfession(prof)
    self.currentProf = prof
    self:Refresh()
    if self.embed then self:RefreshEmbed() end
end

-- entry = { itemID=, name= } (item)  ou  { enchantID=, name= } (enchant)
function OP:SelectEntry(entry)
    self.selEntry = entry
    local disp = entry.itemID and TS:GetItemName(entry.itemID, entry.name) or entry.name
    local txt = L["Selected: "] .. "|cFFFFFFFF" .. (disp or "?")
        .. (entry.enchantID and " |cFFCC88FF(ench.)|r" or "") .. "|r"
    if self.selLabel then self.selLabel:SetText(txt) end
    if self.embed and self.embed.selLabel then self.embed.selLabel:SetText(txt) end
    self:RefreshCatalog()
    if self.embed and self.embed.catRows then
        local sv_rows = self.catRows; local sv_sc = self.catScroll
        self.catRows = self.embed.catRows; self.catScroll = self.embed.catScroll
        self:RenderCatalog()
        self.catRows = sv_rows; self.catScroll = sv_sc
    end
end

function OP:SubmitOrder()
    local e = self.selEntry
    if not e then
        print("|cFF00CCFFGuild Economy|r " .. L["Select an item from the catalogue first."])
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
    if not self.catScroll then return end
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
    if not self.ordRows then return end
    local me   = UnitName("player") or "?"
    local rows = self:BuildOrderList(self.currentProf, me)

    for i = 1, #self.ordRows do
        local row = self.ordRows[i]
        local item = rows[i]
        if not item then row:Hide()
        elseif item.header then
            row.fs:SetText(item.header); row.fs:SetWidth(258)
            row.btn:Hide(); row:Show()
        elseif item.presence then
            local u     = item.presence
            local profs = #u.professions > 0 and table.concat(u.professions, ", ") or ""
            local nameC = u.isSelf and "|cFFFFFFFF" or "|cFFCCCCCC"
            row.fs:SetWidth(258)
            row.fs:SetText(string.format("|cFF33FF33%s|r %s%s|r%s", "\226\151\143",
                nameC, u.player,
                profs ~= "" and ("  |cFF888888" .. profs .. "|r") or ""))
            row.btn:Hide(); row:Show()
        elseif item.request then
            local o   = item.request
            local nm  = TS:GetItemName(o.itemID, o.itemName)
            row.fs:SetWidth(190)
            row.fs:SetText(string.format("%s |cFF888888(%s)|r %s",
                nm, o.player or "?", o.priceText and ("|cFFFFCC00" .. o.priceText .. "|r") or ""))
            row.btn:Show()
            row.btn:SetText("Whisper")
            row.btn:SetScript("OnClick", function()
                if ChatFrame_OpenChat then
                    ChatFrame_OpenChat("/w " .. (o.player or "") .. " " .. nm .. " : ")
                end
            end)
            row:Show()
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
-- Mode embarqué dans la fenêtre principale (onglet Orders)
-- ------------------------------------------------------------------

function OP:_BuildEmbedCatalog(parent, E)
    local catHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catHdr:SetPoint("TOPLEFT", 8, -72)
    catHdr:SetText("|cFFFFCC00Catalogue|r")
    E.catScroll = CreateFrame("ScrollFrame", "TradeScannerEmbedCatScroll", parent, "UIPanelScrollFrameTemplate")
    E.catScroll:SetPoint("TOPLEFT", 8, -90)
    E.catScroll:SetSize(290, CAT_ROWS * ROW_H)
    E.catContent = CreateFrame("Frame", nil, E.catScroll)
    E.catContent:SetSize(290, CAT_ROWS * ROW_H)
    E.catScroll:SetScrollChild(E.catContent)
    E.catScroll:HookScript("OnVerticalScroll", function()
        local sv_rows = self.catRows; local sv_scroll = self.catScroll
        self.catRows = E.catRows; self.catScroll = E.catScroll
        self:RenderCatalog()
        self.catRows = sv_rows; self.catScroll = sv_scroll
    end)
    E.catRows = {}
    for i = 1, CAT_ROWS do E.catRows[i] = self:BuildCatRow(E.catContent, i) end
end

function OP:_BuildEmbedOrders(parent, E)
    local ordHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ordHdr:SetPoint("TOPLEFT", 322, -72)
    ordHdr:SetText("|cFFFFCC00" .. L["Orders"] .. "|r")
    E.ordScroll = CreateFrame("ScrollFrame", "TradeScannerEmbedOrdScroll", parent, "UIPanelScrollFrameTemplate")
    E.ordScroll:SetPoint("TOPLEFT", 322, -90)
    E.ordScroll:SetSize(270, ORD_ROWS * ROW_H)
    local ordContent = CreateFrame("Frame", nil, E.ordScroll)
    ordContent:SetSize(270, ORD_ROWS * ROW_H * 4)
    E.ordScroll:SetScrollChild(ordContent)
    E.ordRows = {}
    for i = 1, ORD_ROWS * 3 do E.ordRows[i] = self:BuildOrdRow(ordContent, i) end
end

function OP:_BuildEmbedBottomBar(parent, E)
    E.selLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    E.selLabel:SetPoint("BOTTOMLEFT", 8, 18)
    E.selLabel:SetText("|cFF888888" .. L["Select an item..."] .. "|r")
    local orderBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    orderBtn:SetSize(70, 22)
    orderBtn:SetPoint("BOTTOMRIGHT", -8, 14)
    orderBtn:SetText("Order")
    orderBtn:SetScript("OnClick", function() OP:SubmitOrderFromEmbed() end)
    E.priceBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    E.priceBox:SetSize(70, 18)
    E.priceBox:SetPoint("RIGHT", orderBtn, "LEFT", -12, 0)
    E.priceBox:SetAutoFocus(false)
    E.priceBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    local priceLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLbl:SetPoint("RIGHT", E.priceBox, "LEFT", -4, 0)
    priceLbl:SetText(L["Price"])
    E.qtyBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    E.qtyBox:SetSize(40, 18)
    E.qtyBox:SetPoint("RIGHT", priceLbl, "LEFT", -8, 0)
    E.qtyBox:SetAutoFocus(false)
    E.qtyBox:SetNumeric(true)
    E.qtyBox:SetText("1")
    E.qtyBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    local qtyLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLbl:SetPoint("RIGHT", E.qtyBox, "LEFT", -4, 0)
    qtyLbl:SetText(L["Qty"])
end

function OP:BuildEmbed(parent)
    if self.embed then return end
    local E = {}
    self.embed = E

    E.tabContainer = CreateFrame("Frame", nil, parent)
    E.tabContainer:SetPoint("TOPLEFT", 0, 0)
    E.tabContainer:SetSize(W - 16, 44)
    E.tabs = {}

    local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 8, -50)
    searchLabel:SetText("Search:")
    E.search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    E.search:SetSize(180, 18)
    E.search:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    E.search:SetAutoFocus(false)
    E.search:SetScript("OnTextChanged", function(b)
        OP.searchText = b:GetText():lower()
        OP:RefreshEmbed()
    end)
    E.search:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)

    self:_BuildEmbedCatalog(parent, E)
    self:_BuildEmbedOrders(parent, E)
    self:_BuildEmbedBottomBar(parent, E)
end

function OP:RefreshEmbed()
    local E = self.embed
    if not E then return end
    local sv = {
        tabContainer = self.tabContainer,
        catScroll    = self.catScroll,
        catContent   = self.catContent,
        catRows      = self.catRows,
        ordRows      = self.ordRows,
        selLabel     = self.selLabel,
        priceBox     = self.priceBox,
        qtyBox       = self.qtyBox,
        tabs         = self.tabs,
    }
    self.tabContainer = E.tabContainer
    self.catScroll    = E.catScroll
    self.catContent   = E.catContent
    self.catRows      = E.catRows
    self.ordRows      = E.ordRows
    self.selLabel     = E.selLabel
    self.priceBox     = E.priceBox
    self.qtyBox       = E.qtyBox
    self.tabs         = E.tabs
    self:RefreshTabs()
    self:RefreshCatalog()
    self:RefreshOrders()
    self.tabContainer = sv.tabContainer
    self.catScroll    = sv.catScroll
    self.catContent   = sv.catContent
    self.catRows      = sv.catRows
    self.ordRows      = sv.ordRows
    self.selLabel     = sv.selLabel
    self.priceBox     = sv.priceBox
    self.qtyBox       = sv.qtyBox
    self.tabs         = sv.tabs
end

function OP:SubmitOrderFromEmbed()
    local E = self.embed
    if not E then return end
    local sv_qty, sv_price = self.qtyBox, self.priceBox
    self.qtyBox, self.priceBox = E.qtyBox, E.priceBox
    self:SubmitOrder()
    self.qtyBox, self.priceBox = sv_qty, sv_price
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
