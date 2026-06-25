-- TradeScanner_UI.lua — Fenêtre principale avec tableau d'offres

local TS = TradeScanner
local UI = {}
TS.UI = UI
local L  = TS.L

-- ============================================================
-- CONSTANTES UI
-- ============================================================

local FRAME_W   = 700   -- largeur de conception du TABLEAU d'offres (colonnes calées dessus)
local FRAME_H   = 460
local ROW_H     = 22
local MAX_ROWS  = 18
local TAB_W     = 128
local SIDEBAR_W = 166   -- bande gauche « façon HdV » (arbre catégories + filtres qualité/niveau)

-- NB : la géométrie des colonnes vit dans TradeScanner_UI_Rows.lua (lignes) et
-- TradeScanner_UI_Filters.lua (en-têtes triables) ; pas besoin d'une copie ici.

local TABS = {
    { id = "all",    label = "All"          },
    { id = "wts",    label = "Sales (WTS)"  },
    { id = "buy",    label = "Wanted (WTB)" },
    { id = "gift",   label = "Gifts (WTG)"  },
    { id = "sell",   label = "Sellable"     },
    { id = "orders", label = "Orders"       },
}

-- ============================================================
-- HELPERS
-- ============================================================

local function FormatAge(ts)
    local age = time() - ts
    if age < 60      then return age .. "s"
    elseif age < 3600 then return math.floor(age / 60) .. "m"
    else                   return math.floor(age / 3600) .. "h"
    end
end

-- Délègue au module skin (ligne 1px warm, cf. TradeScanner_UI_Skin.lua).
local function MakeSeparator(parent, offsetY)
    return UI.Skin.MakeSeparator(parent, offsetY)
end

-- ============================================================
-- BUILD SUB-METHODS
-- ============================================================

function UI:_BuildTitleBar(f)
    -- Wordmark « Guild Economy » gravé en or (police bundle MORPHEUS, cf. skin).
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFontObject(UI.Skin.WordmarkFont())
    title:SetPoint("TOP", 0, -14)
    title:SetText("Guild Economy")
    -- Sous-ligne « Watching » conservée pour _UpdateStatus mais masquée : l'info des
    -- canaux vit désormais dans la barre de statut (cf. mockup).
    local chanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLabel:SetPoint("TOP", 0, -40)
    chanLabel:SetTextColor(UI.Skin.unpack(UI.Skin.color.goldOre))
    chanLabel:Hide()
    self.chanLabel = chanLabel
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    local gearBtn = CreateFrame("Button", nil, f)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("TOPLEFT", 14, -14)
    gearBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gearBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    gearBtn:SetScript("OnClick", function()
        if TS.Settings then TS.Settings:Toggle() end
    end)
    gearBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Settings"]); GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", GameTooltip_Hide)
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPRIGHT", -184, -18)
    searchLabel:SetText("Filter")
    searchLabel:SetTextColor(UI.Skin.unpack(UI.Skin.color.gold))
    UI.Skin.ApplyShadow(searchLabel)
    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(120, 18)
    searchBox:SetPoint("TOPRIGHT", -40, -14)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(box) UI.searchText = box:GetText(); UI:Refresh() end)
    searchBox:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
    self.searchBox = searchBox
end

function UI:_BuildTabButtons(f)
    self.tabBtns = {}
    for i, tabDef in ipairs(TABS) do
        self.tabBtns[tabDef.id] = self:BuildTabButton(f, tabDef, i)
    end
end

function UI:_BuildOffersPane(f)
    local pane = CreateFrame("Frame", nil, f)
    -- Décalé de SIDEBAR_W vers la droite : la bande gauche accueille la sidebar HdV.
    -- Le tableau garde ses coordonnées internes calées sur FRAME_W (700).
    pane:SetPoint("TOPLEFT",     SIDEBAR_W, -70)
    pane:SetPoint("BOTTOMRIGHT", 0,          0)
    self.offersPane = pane
    MakeSeparator(pane, 0)
    self:_BuildSortableHeaders(pane)  -- en-têtes cliquables (tri), cf. UI_Filters
    MakeSeparator(pane, -22)
    self:_BuildScrollRows(pane)
    self:_BuildBottomButtons(pane)
end

function UI:_BuildOrdersPane(f)
    local pane = CreateFrame("Frame", nil, f)
    -- Pane Orders aligné à gauche et borné à FRAME_W (l'embed garde sa géométrie
    -- d'origine ; la sidebar HdV étant masquée sur cet onglet, la bande gauche sert
    -- de marge). Évite que la barre Order/Qty/Price ne fuie à l'extrême droite.
    pane:SetPoint("TOPLEFT",    0, -70)
    pane:SetPoint("BOTTOMLEFT", 0,   0)
    pane:SetWidth(FRAME_W)
    pane:Hide()
    self.ordersPane = pane
    if TS.OrderPanel then TS.OrderPanel:BuildEmbed(pane) end
end

function UI:_BuildScrollRows(pane)
    local scrollFrame = CreateFrame("ScrollFrame", "TradeScannerScroll", pane, "UIPanelScrollFrameTemplate")
    -- x=0 : aligne les lignes (enfants du scroll) sur les en-têtes ancrés au pane.
    scrollFrame:SetPoint("TOPLEFT",     0,  -26)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 62)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(FRAME_W - 32)
    content:SetHeight(MAX_ROWS * ROW_H * 4)
    scrollFrame:SetScrollChild(content)
    self.scrollFrame = scrollFrame
    self.content     = content
    self.rows = {}
    for i = 1, MAX_ROWS * 3 do self.rows[i] = self:BuildRow(content, i) end
    -- Scène tavern en filigrane PERMANENT derrière le tableau (cf. skin).
    self.tableScene = UI.Skin.BuildTableScene(pane, scrollFrame)
    MakeSeparator(pane, -(FRAME_H - 66 - 70))
    local statusText = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 8, 42)
    statusText:SetTextColor(UI.Skin.unpack(UI.Skin.color.textMuted))
    UI.Skin.ApplyShadow(statusText)
    self.statusText = statusText
end

-- Barre du bas : Refresh + Clear. Le bloc « Sell+ / Add / Manage » (vendable manuel)
-- a été retiré d'ici (v1.5) — il est désormais géré dans le panneau Réglages et via
-- /ts sell. La place libérée à gauche accueille la barre de filtres (cf. UI_Filters).
function UI:_BuildBottomButtons(pane)
    -- Boutons or maison (échappent au skin externe qui teinte les boutons en rouge).
    local refreshBtn = UI.Skin.MakeGoldButton(pane, 90, 22, "Refresh")
    refreshBtn:SetPoint("BOTTOMRIGHT", -28, 16)
    refreshBtn:SetScript("OnClick", function()
        if TS.Net then TS.Net:BroadcastWho() end
        UI:Refresh()
    end)
    local clearBtn = UI.Skin.MakeGoldButton(pane, 70, 22, "Clear")
    clearBtn:SetPoint("BOTTOMRIGHT", -122, 16)
    clearBtn:SetScript("OnClick", function() TS.db.offers = {}; UI:Refresh() end)
end

-- ============================================================
-- CONSTRUCTION DE LA FENÊTRE PRINCIPALE
-- ============================================================

function UI:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "TradeScannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W + SIDEBAR_W, FRAME_H); f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10); f:Hide()
    UI.Skin.SkinFrameBackdrop(f)  -- fond brun chaud + cadre or ornementé (cf. skin)
    self:_BuildTitleBar(f)
    self:_BuildTabButtons(f)
    self:_BuildOffersPane(f)
    self:_BuildOrdersPane(f)
    self:_BuildSidebar(f)  -- sidebar HdV (catégories + qualité + niveau), cf. UI_Categories
    self.frame = f
    self:SetTab("all")
    C_Timer.NewTicker(10, function()
        if UI.frame and UI.frame:IsShown() then UI:Refresh() end
    end)
end

-- ============================================================
-- BOUTONS D'ONGLETS
-- ============================================================

function UI:BuildTabButton(parent, tabDef, index)
    local tabW, tabH = TAB_W, 22
    local btn  = CreateFrame("Button", nil, parent)
    btn:SetSize(tabW, tabH)
    btn:SetPoint("TOPLEFT", 14 + (index - 1) * (tabW + 4), -48)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg
    -- Bevel carré « tablette de pierre » : liseré clair en haut, sombre en bas.
    local hiEdge = btn:CreateTexture(nil, "BORDER")
    hiEdge:SetHeight(1); hiEdge:SetPoint("TOPLEFT"); hiEdge:SetPoint("TOPRIGHT")
    hiEdge:SetColorTexture(UI.Skin.unpack(UI.Skin.color.stoneHi))
    local loEdge = btn:CreateTexture(nil, "BORDER")
    loEdge:SetHeight(1); loEdge:SetPoint("BOTTOMLEFT"); loEdge:SetPoint("BOTTOMRIGHT")
    loEdge:SetColorTexture(UI.Skin.unpack(UI.Skin.color.void))
    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetAllPoints(); txt:SetText(tabDef.label)
    UI.Skin.ApplyShadow(txt)
    btn.txt = txt
    btn.tabID = tabDef.id
    UI.Skin.TabColors(btn, "idle")
    -- Clic d'onglet = hardware event → on en profite pour s'annoncer cross-guilde (throttlé).
    btn:SetScript("OnClick", function(b)
        UI:SetTab(b.tabID)
        if TS.Net then TS.Net:BroadcastWho() end
    end)
    btn:SetScript("OnEnter", function(b)
        if UI.activeTab ~= b.tabID then UI.Skin.TabColors(b, "hover") end
    end)
    btn:SetScript("OnLeave", function(b)
        if UI.activeTab ~= b.tabID then UI.Skin.TabColors(b, "idle") end
    end)
    return btn
end

function UI:SetTab(tabID)
    self.activeTab = tabID
    for id, btn in pairs(self.tabBtns) do
        UI.Skin.TabColors(btn, id == tabID and "active" or "idle")
    end
    local isOrders = (tabID == "orders")
    if self.offersPane then self.offersPane:SetShown(not isOrders) end
    if self.ordersPane then self.ordersPane:SetShown(isOrders) end
    if self.sidebar    then self.sidebar:SetShown(not isOrders) end
    if tabID == "sell" and TS.Minimap then TS.Minimap:SetAlert(false) end
    self:Refresh()
end

-- ============================================================
-- REFRESH SUB-METHODS
-- ============================================================

function UI:_GetActiveOffers()
    local tab = self.activeTab or "all"
    local offers
    if     tab == "all"  then offers = TS:GetOffers(nil,    false)
    elseif tab == "wts"  then offers = TS:GetOffers("sell", false)
    elseif tab == "buy"  then offers = TS:GetOffers("buy",  false)
    elseif tab == "gift" then offers = TS:GetOffers("gift", false)
    elseif tab == "sell" then offers = TS:GetSellableOffers()
    end
    offers = offers or {}
    -- 1) Recherche texte (nom d'objet ou joueur)
    if self.searchText and self.searchText ~= "" then
        local needle, filtered = self.searchText:lower(), {}
        for _, offer in ipairs(offers) do
            local label = (offer.itemID and TS:GetItemName(offer.itemID, offer.itemName))
                          or offer.itemName or offer.rawMsg or ""
            if label:lower():find(needle, 1, true)
               or (offer.player and offer.player:lower():find(needle, 1, true)) then
                filtered[#filtered + 1] = offer
            end
        end
        offers = filtered
    end
    -- 2) Filtres HdV : catégorie / qualité / niveau (cf. UI_Categories)
    if self._OfferPassesFilters then
        local kept = {}
        for _, offer in ipairs(offers) do
            if self:_OfferPassesFilters(offer) then kept[#kept + 1] = offer end
        end
        offers = kept
    end
    -- 3) Tri par colonne si sélectionné (cf. UI_Filters)
    if self._SortOffers then offers = self:_SortOffers(offers) end
    return offers
end

function UI:_FillRow(row, offer)
    row.offer = offer
    local srcTag = (offer.source == "guild") and "|cFFFFAA00[G]|r " or ""
    if offer.offerType == "sell" then row.typeFS:SetText(srcTag .. "|cFF33DD33WTS|r")
    elseif offer.offerType == "gift" then row.typeFS:SetText(srcTag .. "|cFFCC66FFWTG|r")
    else                              row.typeFS:SetText(srcTag .. "|cFF33AAFFWTB|r") end
    if offer.itemLink then
        row.itemFS:SetText(offer.itemLink)
    elseif offer.itemID then
        -- Offre réseau (itemID sans lien) : résoudre le nom EN DIRECT. S'il n'est pas
        -- encore en cache client, déclencher le chargement et afficher un placeholder ;
        -- GET_ITEM_INFO_RECEIVED relancera un refresh quand l'info arrive (cf. 1.5.2).
        local name, _, quality = GetItemInfo(offer.itemID)
        if name then
            -- Nom coloré par rareté WoW (convention HdV).
            local c = quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
            row.itemFS:SetText(c and (c.hex .. name .. "|r") or name)
        else
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(offer.itemID)
            end
            row.itemFS:SetText("|cFF888888" .. (SEARCH_LOADING_TEXT or "…") .. "|r")
        end
    elseif offer.itemName then
        row.itemFS:SetText(offer.itemName)
    else
        local raw = offer.rawMsg or ""
        if #raw > 38 then raw = raw:sub(1, 38) .. "…" end
        row.itemFS:SetText("|cFF888888" .. raw .. "|r")
    end
    if offer.priceText then
        local px = offer.priceText
        if offer.qtyText then px = px .. " |cFF888888" .. offer.qtyText .. "|r" end
        row.priceFS:SetText(px)
    elseif offer.qtyText then
        row.priceFS:SetText("|cFF888888" .. offer.qtyText .. "|r")
    else
        row.priceFS:SetText("|cFF555555—|r")
    end
    row.playerFS:SetText(offer.player or "?")
    row.ageFS:SetText(FormatAge(offer.timestamp))
    if offer.canCraft then
        row.craftBar:Show()
        if offer.sellCategory == "disenchant" then
            row.craftBar:SetColorTexture(0.4, 0.8, 1, 1)
            row.craftFS:SetText("|cFF66CCFFDE|r " .. (offer.profession or ""))
        elseif offer.sellCategory == "manual" then
            row.craftBar:SetColorTexture(0.6, 1, 0.6, 1)
            row.craftFS:SetText("|cFF88FF88" .. (offer.profession or "Manuel") .. "|r")
        else
            row.craftBar:SetColorTexture(1, 0.78, 0, 1)
            row.craftFS:SetText(offer.profession or "")
        end
    else
        row.craftBar:Hide(); row.craftFS:SetText("")
    end
    row.wBtn:Hide()
    row:Show()
end

function UI:_UpdateStatus(totalAll, totalSell, profCount)
    if self.tabBtns and self.tabBtns["sell"] then
        local btn = self.tabBtns["sell"]
        if totalSell > 0 then btn.txt:SetText(string.format("|cFFFFCC00Sellable (%d)|r", totalSell))
        else                  btn.txt:SetText("Sellable") end
    end
    if self.statusText then
        local guildState = (TS.db and TS.db.scanGuild)
            and "|cFF33DD33/g ON|r" or "|cFFFF4444/g OFF|r"
        self.statusText:SetText(string.format(
            "|cFFE8B84B%d|r offers  |  |cFFFFDD00%d WTB sellable|r  |  Channels: |cFF00CCFF%s|r  |  %s  |  |cFFE8B84B%d|r profession(s)",
            totalAll, totalSell, TS:ChannelsLabel(), guildState, profCount))
    end
    if self.chanLabel and TS.db then
        self.chanLabel:SetText("Watching: |cFF00CCFF" .. TS:ChannelsLabel() .. "|r")
    end
end

-- La scène tavern reste un filigrane permanent ; on ne fait qu'ajuster le voile
-- (plus clair quand vide pour la faire ressortir) et afficher le label si vide.
function UI:_UpdateEmptyState(isEmpty)
    local sc = self.tableScene
    if not sc then return end
    sc.veil:SetAlpha(isEmpty and 0.18 or 0.62)
    if isEmpty then
        local filtered = (self.searchText and self.searchText ~= "")
            or self.filterClassID or self.filterQuality
            or self.filterLevelMin or self.filterLevelMax
        if filtered then
            sc.label:SetText("No offers match your filters.")
        else
            sc.label:SetText("Watching " .. TS:ChannelsLabel()
                .. "  —  WTB and WTS in balance.")
        end
    end
    sc.label:SetShown(isEmpty)
end

-- ============================================================
-- RAFRAÎCHISSEMENT
-- ============================================================

function UI:Refresh()
    if not self.frame then return end
    if self.activeTab == "orders" then
        if TS.OrderPanel then TS.OrderPanel:RefreshEmbed() end
        return
    end
    TS:ClearExpired()
    local offers = self:_GetActiveOffers()
    for _, row in ipairs(self.rows) do
        row:Hide(); row.offer = nil
        if row.doneBtn then row.doneBtn:Hide() end
        if row.wBtn    then row.wBtn:Hide()    end
    end
    local count = math.min(#offers, #self.rows)
    for i = 1, count do self:_FillRow(self.rows[i], offers[i]) end
    self:_UpdateEmptyState(#offers == 0)
    local totalAll  = #TS:GetOffers(nil, false)
    local totalSell = #TS:GetSellableOffers()
    local profCount = 0
    for _ in pairs(TS:GetCraftedProfessions()) do profCount = profCount + 1 end
    self:_UpdateStatus(totalAll, totalSell, profCount)
end

-- ============================================================
-- AFFICHER / MASQUER
-- ============================================================

function UI:Toggle()
    if not self.frame then self:Build() end
    if self.frame:IsShown() then self.frame:Hide()
    else self:Refresh(); self.frame:Show() end
end

function UI:Show()
    if not self.frame then self:Build() end
    self:Refresh()
    self.frame:Show()
end
