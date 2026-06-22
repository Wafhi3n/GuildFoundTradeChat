-- TradeScanner_UI.lua — Fenêtre principale avec tableau d'offres

local TS = TradeScanner
local UI = {}
TS.UI = UI

-- ============================================================
-- CONSTANTES UI
-- ============================================================

local FRAME_W   = 700
local FRAME_H   = 460
local ROW_H     = 22
local MAX_ROWS  = 18

local COLUMNS = {
    { label = "Type",   w = 42,  x = 10  },
    { label = "Item",   w = 215, x = 56  },
    { label = "Price",  w = 88,  x = 275 },
    { label = "Player", w = 115, x = 367 },
    { label = "Age",    w = 34,  x = 486 },
    { label = "Craft",  w = 120, x = 524 },
}

local TABS = {
    { id = "all",      label = "All"          },
    { id = "sell",     label = "Sales (WTS)"  },
    { id = "buy",      label = "Wanted (WTB)" },
    { id = "craft",    label = "Craftable"    },
}

-- ============================================================
-- HELPERS
-- ============================================================

local function FormatAge(ts)
    local age = time() - ts
    if age < 60   then return age .. "s"
    elseif age < 3600 then return math.floor(age / 60) .. "m"
    else               return math.floor(age / 3600) .. "h"
    end
end

local function MakeBackground(frame, r, g, b, a)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(r, g, b, a or 1)
    return bg
end

local function MakeSeparator(parent, offsetY)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.45, 0.9)
    sep:SetPoint("TOPLEFT",  4,  offsetY)
    sep:SetPoint("TOPRIGHT", -4, offsetY)
    return sep
end

-- ============================================================
-- CONSTRUCTION DE LA FENÊTRE PRINCIPALE
-- ============================================================

function UI:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "TradeScannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.09, 0.96)
    f:SetBackdropBorderColor(0.35, 0.35, 0.5, 1)

    -- Titre
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFF00CCFFTradeScanner|r")

    -- Current channel label
    local chanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLabel:SetPoint("TOP", 0, -28)
    chanLabel:SetTextColor(0.55, 0.55, 0.55)
    self.chanLabel = chanLabel

    -- Bouton fermer
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ---- ONGLETS ----
    self.tabBtns = {}
    for i, tabDef in ipairs(TABS) do
        local btn = self:BuildTabButton(f, tabDef, i)
        self.tabBtns[tabDef.id] = btn
    end

    MakeSeparator(f, -70)

    -- ---- EN-TÊTES DE COLONNES ----
    for _, col in ipairs(COLUMNS) do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", col.x, -76)
        fs:SetWidth(col.w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cFFAAAAAA" .. col.label .. "|r")
    end

    MakeSeparator(f, -92)

    -- ---- SCROLL FRAME ----
    local scrollFrame = CreateFrame(
        "ScrollFrame", "TradeScannerScroll", f, "UIPanelScrollFrameTemplate"
    )
    scrollFrame:SetPoint("TOPLEFT",     4,  -96)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 36)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(FRAME_W - 32)
    content:SetHeight(MAX_ROWS * ROW_H * 4)  -- assez grand pour scroller
    scrollFrame:SetScrollChild(content)

    self.scrollFrame = scrollFrame
    self.content     = content

    -- Pool de lignes
    self.rows = {}
    for i = 1, MAX_ROWS * 3 do
        self.rows[i] = self:BuildRow(content, i)
    end

    -- ---- BARRE DE STATUT ----
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 8, 10)
    statusText:SetTextColor(0.55, 0.55, 0.55)
    self.statusText = statusText

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, 22)
    refreshBtn:SetPoint("BOTTOMRIGHT", -28, 6)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() UI:Refresh() end)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", -122, 6)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        TS.db.offers = {}
        UI:Refresh()
    end)

    self.frame = f

    -- Activer l'onglet par défaut
    self:SetTab("all")

    -- Ticker de rafraîchissement automatique (toutes les 10s)
    C_Timer.NewTicker(10, function()
        if UI.frame and UI.frame:IsShown() then
            UI:Refresh()
        end
    end)
end

-- ============================================================
-- BOUTONS D'ONGLETS
-- ============================================================

function UI:BuildTabButton(parent, tabDef, index)
    local tabW = 160
    local tabH = 22
    local btn  = CreateFrame("Button", nil, parent)
    btn:SetSize(tabW, tabH)
    btn:SetPoint("TOPLEFT", 8 + (index - 1) * (tabW + 4), -48)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
    btn.bg = bg

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetAllPoints()
    txt:SetText(tabDef.label)
    txt:SetTextColor(0.7, 0.7, 0.7)
    btn.txt = txt

    btn.tabID = tabDef.id
    btn:SetScript("OnClick",  function(b) UI:SetTab(b.tabID) end)
    btn:SetScript("OnEnter",  function(b)
        if UI.activeTab ~= b.tabID then
            b.bg:SetColorTexture(0.2, 0.2, 0.3, 0.9)
        end
    end)
    btn:SetScript("OnLeave",  function(b)
        if UI.activeTab ~= b.tabID then
            b.bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
            b.txt:SetTextColor(0.7, 0.7, 0.7)
        end
    end)

    return btn
end

function UI:SetTab(tabID)
    self.activeTab = tabID
    for id, btn in pairs(self.tabBtns) do
        if id == tabID then
            btn.bg:SetColorTexture(0.15, 0.35, 0.65, 0.95)
            btn.txt:SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
            btn.txt:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    -- L'utilisateur consulte les demandes craftables : on efface l'alerte minimap
    if tabID == "craft" and TS.Minimap then
        TS.Minimap:SetAlert(false)
    end
    self:Refresh()
end

-- ============================================================
-- LIGNES DU TABLEAU
-- ============================================================

function UI:BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(FRAME_W - 32, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)

    -- Fond alterné
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(0.09, 0.09, 0.13, 0.7)
    else
        bg:SetColorTexture(0.05, 0.05, 0.09, 0.5)
    end

    -- Survol
    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)

    -- Barre gauche "craftable" (or)
    local craftBar = row:CreateTexture(nil, "ARTWORK")
    craftBar:SetWidth(3)
    craftBar:SetPoint("TOPLEFT")
    craftBar:SetPoint("BOTTOMLEFT")
    craftBar:SetColorTexture(1, 0.78, 0, 1)
    craftBar:Hide()
    row.craftBar = craftBar

    -- Type (WTS / WTB)
    local typeFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeFS:SetPoint("LEFT", COLUMNS[1].x, 0)
    typeFS:SetWidth(COLUMNS[1].w)
    typeFS:SetJustifyH("CENTER")
    row.typeFS = typeFS

    -- Item
    local itemFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemFS:SetPoint("LEFT", COLUMNS[2].x, 0)
    itemFS:SetWidth(COLUMNS[2].w)
    itemFS:SetJustifyH("LEFT")
    itemFS:SetWordWrap(false)
    row.itemFS = itemFS

    -- Prix
    local priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceFS:SetPoint("LEFT", COLUMNS[3].x, 0)
    priceFS:SetWidth(COLUMNS[3].w)
    priceFS:SetJustifyH("LEFT")
    priceFS:SetTextColor(1, 0.88, 0.1)
    row.priceFS = priceFS

    -- Joueur
    local playerFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerFS:SetPoint("LEFT", COLUMNS[4].x, 0)
    playerFS:SetWidth(COLUMNS[4].w)
    playerFS:SetJustifyH("LEFT")
    playerFS:SetTextColor(0.85, 0.85, 0.85)
    row.playerFS = playerFS

    -- Âge
    local ageFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ageFS:SetPoint("LEFT", COLUMNS[5].x, 0)
    ageFS:SetWidth(COLUMNS[5].w)
    ageFS:SetJustifyH("CENTER")
    ageFS:SetTextColor(0.5, 0.5, 0.5)
    row.ageFS = ageFS

    -- Métier craftable
    local craftFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftFS:SetPoint("LEFT", COLUMNS[6].x, 0)
    craftFS:SetWidth(COLUMNS[6].w)
    craftFS:SetJustifyH("LEFT")
    craftFS:SetTextColor(1, 0.78, 0)
    row.craftFS = craftFS

    -- Bouton whisper (icône lettre)
    local wBtn = CreateFrame("Button", nil, row)
    wBtn:SetSize(16, 16)
    wBtn:SetPoint("RIGHT", -6, 0)
    local wIcon = wBtn:CreateTexture(nil, "ARTWORK")
    wIcon:SetAllPoints()
    wIcon:SetTexture("Interface\\GossipFrame\\PetitionGossipIcon")
    wBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(wBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Whisper " .. (row.offer and row.offer.player or "?"))
        GameTooltip:Show()
    end)
    wBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wBtn:SetScript("OnClick", function()
        if row.offer and row.offer.player then
            ChatFrame_OpenChat("/w " .. row.offer.player .. " ")
        end
    end)
    wBtn:Hide()
    row.wBtn = wBtn

    -- Tooltip on hover — use the full item link to get suffix stats (e.g. "of the Bear")
    row:SetScript("OnEnter", function(r)
        if not r.offer then return end
        GameTooltip:SetOwner(r, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()

        if r.offer.itemLink then
            -- Extract the full hyperlink content (includes enchant/suffix IDs)
            -- e.g. "item:12345:0:0:0:0:0:-7:0:60" from "|Hitem:12345:...|h[Name]|h"
            local hyperlink = r.offer.itemLink:match("|H([^|]+)|h")
            if hyperlink then
                pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink)
            end
        elseif r.offer.itemID then
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. r.offer.itemID)
        else
            GameTooltip:AddLine(r.offer.rawMsg or "", 1, 1, 1, true)
        end

        GameTooltip:AddLine(" ")
        local typeLabel = r.offer.offerType == "sell" and "Sale" or "Wanted"
        local srcLabel  = r.offer.source == "guild" and " |cFFFFAA00[Guild]|r" or " |cFF00CCFF[Channel]|r"
        GameTooltip:AddLine(typeLabel .. srcLabel .. " by |cFFFFFFFF" .. (r.offer.player or "?") .. "|r")

        if r.offer.priceText then
            GameTooltip:AddLine("Price: |cFFFFDD00" .. r.offer.priceText .. "|r")
        end

        if r.offer.canCraft then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFFFFCC00You can craft this item!|r")
            GameTooltip:AddLine("Profession: " .. (r.offer.profession or "?"), 1, 0.78, 0)
        end

        GameTooltip:AddLine("|cFF888888Left-click to whisper|r")
        GameTooltip:Show()
        r.wBtn:Show()
    end)

    row:SetScript("OnLeave", function(r)
        GameTooltip:Hide()
        if r.wBtn then r.wBtn:Hide() end
    end)

    -- Clic gauche = whisper
    row:SetScript("OnClick", function(r)
        if r.offer and r.offer.player then
            ChatFrame_OpenChat("/w " .. r.offer.player .. " ")
        end
    end)

    row:Hide()
    return row
end

-- ============================================================
-- RAFRAÎCHISSEMENT
-- ============================================================

function UI:Refresh()
    if not self.frame then return end

    TS:ClearExpired()

    -- Récupérer les offres selon l'onglet actif
    local tab    = self.activeTab or "all"
    local offers

    if tab == "all"   then offers = TS:GetOffers(nil,    false)
    elseif tab == "sell"  then offers = TS:GetOffers("sell", false)
    elseif tab == "buy"   then offers = TS:GetOffers("buy",  false)
    elseif tab == "craft" then offers = TS:GetOffers("buy",  true)   -- WTB qu'on peut crafter
    end

    -- Masquer toutes les lignes
    for _, row in ipairs(self.rows) do
        row:Hide()
        row.offer = nil
    end

    local count = math.min(#offers, #self.rows)

    for i = 1, count do
        local offer = offers[i]
        local row   = self.rows[i]
        row.offer   = offer

        -- Type badge + source (channel or guild)
        local srcTag = (offer.source == "guild") and "|cFFFFAA00[G]|r " or ""
        if offer.offerType == "sell" then
            row.typeFS:SetText(srcTag .. "|cFF33DD33WTS|r")
        else
            row.typeFS:SetText(srcTag .. "|cFF33AAFFWTB|r")
        end

        -- Item (avec couleur de qualité si lien disponible)
        if offer.itemLink then
            row.itemFS:SetText(offer.itemLink)
        elseif offer.itemName then
            row.itemFS:SetText(offer.itemName)
        else
            local raw = offer.rawMsg or ""
            if #raw > 38 then raw = raw:sub(1, 38) .. "…" end
            row.itemFS:SetText("|cFF888888" .. raw .. "|r")
        end

        -- Prix
        if offer.priceText then
            row.priceFS:SetText(offer.priceText)
        else
            row.priceFS:SetText("|cFF555555—|r")
        end

        -- Joueur
        row.playerFS:SetText(offer.player or "?")

        -- Âge
        row.ageFS:SetText(FormatAge(offer.timestamp))

        -- Craft highlight
        if offer.canCraft then
            row.craftBar:Show()
            row.craftFS:SetText(offer.profession or "")
        else
            row.craftBar:Hide()
            row.craftFS:SetText("")
        end

        row.wBtn:Hide()
        row:Show()
    end

    -- Barre de statut + label onglet Craftable
    local totalAll   = #TS:GetOffers(nil,   false)
    local totalCraft = #TS:GetOffers("buy",  true)
    local profCount  = 0
    for _ in pairs(TS:GetCraftedProfessions()) do profCount = profCount + 1 end

    -- Met à jour le label de l'onglet Craftable avec le compteur
    if self.tabBtns and self.tabBtns["craft"] then
        local btn = self.tabBtns["craft"]
        if totalCraft > 0 then
            btn.txt:SetText(string.format("|cFFFFCC00Craftable (%d)|r", totalCraft))
        else
            btn.txt:SetText("Craftable")
        end
    end

    if self.statusText then
        local guildState = (TS.db and TS.db.scanGuild)
            and "|cFF33DD33/g ON|r" or "|cFFFF4444/g OFF|r"
        self.statusText:SetText(string.format(
            "%d offers  |  |cFFFFCC00%d WTB craftable|r  |  Channel: |cFF00CCFF%s|r  |  %s  |  %d profession(s)",
            totalAll, totalCraft, TS.db and TS.db.channel or "?", guildState, profCount
        ))
    end

    -- Libellé canal dans le titre
    if self.chanLabel and TS.db then
        self.chanLabel:SetText("Watching: |cFF00CCFF#" .. TS.db.channel .. "|r")
    end
end

-- ============================================================
-- AFFICHER / MASQUER
-- ============================================================

function UI:Toggle()
    if not self.frame then self:Build() end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end

function UI:Show()
    if not self.frame then self:Build() end
    self:Refresh()
    self.frame:Show()
end
