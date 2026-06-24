-- TradeScanner_UI.lua — Fenêtre principale avec tableau d'offres

local TS = TradeScanner
local UI = {}
TS.UI = UI
local L  = TS.L

-- ============================================================
-- CONSTANTES UI
-- ============================================================

local FRAME_W   = 700
local FRAME_H   = 460
local ROW_H     = 22
local MAX_ROWS  = 18
local TAB_W     = 128

local COLUMNS = {
    { label = "Type",    w = 42,  x = 10  },
    { label = "Item",    w = 215, x = 56  },
    { label = "Price",   w = 88,  x = 275 },
    { label = "Player",  w = 115, x = 367 },
    { label = "Age",     w = 34,  x = 486 },
    { label = "Provide", w = 120, x = 524 },
}

local TABS = {
    { id = "all",    label = "All"          },
    { id = "wts",    label = "Sales (WTS)"  },
    { id = "buy",    label = "Wanted (WTB)" },
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

local function MakeSeparator(parent, offsetY)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.45, 0.9)
    sep:SetPoint("TOPLEFT",  4,  offsetY)
    sep:SetPoint("TOPRIGHT", -4, offsetY)
    return sep
end

-- ============================================================
-- BUILD SUB-METHODS
-- ============================================================

function UI:_BuildTitleBar(f)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFF00CCFFGuild Economy|r")
    local chanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLabel:SetPoint("TOP", 0, -28)
    chanLabel:SetTextColor(0.55, 0.55, 0.55)
    self.chanLabel = chanLabel
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPRIGHT", -180, -14)
    searchLabel:SetText("|cFFAAAAAAFilter|r")
    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(120, 18)
    searchBox:SetPoint("TOPRIGHT", -36, -10)
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
    pane:SetPoint("TOPLEFT",     0, -70)
    pane:SetPoint("BOTTOMRIGHT", 0,   0)
    self.offersPane = pane
    MakeSeparator(pane, 0)
    for _, col in ipairs(COLUMNS) do
        local fs = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", col.x, -6)
        fs:SetWidth(col.w)
        fs:SetJustifyH("LEFT")
        fs:SetText("|cFFAAAAAA" .. col.label .. "|r")
    end
    MakeSeparator(pane, -22)
    self:_BuildScrollRows(pane)
    self:_BuildSellManagement(pane)
end

function UI:_BuildOrdersPane(f)
    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("TOPLEFT",     0, -70)
    pane:SetPoint("BOTTOMRIGHT", 0,   0)
    pane:Hide()
    self.ordersPane = pane
    if TS.OrderPanel then TS.OrderPanel:BuildEmbed(pane) end
end

function UI:_BuildScrollRows(pane)
    local scrollFrame = CreateFrame("ScrollFrame", "TradeScannerScroll", pane, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     4,  -26)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 62)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(FRAME_W - 32)
    content:SetHeight(MAX_ROWS * ROW_H * 4)
    scrollFrame:SetScrollChild(content)
    self.scrollFrame = scrollFrame
    self.content     = content
    self.rows = {}
    for i = 1, MAX_ROWS * 3 do self.rows[i] = self:BuildRow(content, i) end
    MakeSeparator(pane, -(FRAME_H - 60 - 70))
    local statusText = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", 8, 36)
    statusText:SetTextColor(0.55, 0.55, 0.55)
    self.statusText = statusText
end

function UI:_BuildSellManagement(pane)
    local sellLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sellLabel:SetPoint("BOTTOMLEFT", 8, 11); sellLabel:SetText("|cFF88FF88Sell+|r")
    local addBox = CreateFrame("EditBox", nil, pane, "InputBoxTemplate")
    addBox:SetSize(180, 18); addBox:SetPoint("BOTTOMLEFT", 52, 10); addBox:SetAutoFocus(false)
    addBox:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
    self.addBox = addBox
    local function DoAddSellable()
        local txt    = addBox:GetText() or ""
        local itemID = tonumber(txt:match("|Hitem:(%d+)")) or tonumber(txt:match("^%s*(%d+)%s*$"))
        if itemID then
            TS:AddManualSellable(itemID); addBox:SetText(""); addBox:ClearFocus()
            UI:Refresh()
            print("|cFF00CCFFGuild Economy|r " .. L["Sellable+: "] .. TS:GetItemName(itemID))
        else
            print("|cFF00CCFFGuild Economy|r " .. L["Shift-click an item or enter an item ID."])
        end
    end
    addBox:SetScript("OnEnterPressed", DoAddSellable)
    local addBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22); addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    addBtn:SetText("Add"); addBtn:SetScript("OnClick", DoAddSellable)
    local manageDrop = CreateFrame("Frame", "TradeScannerManageDrop", pane, "UIDropDownMenuTemplate")
    manageDrop:SetPoint("LEFT", addBtn, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(manageDrop, 90); UIDropDownMenu_SetText(manageDrop, "Manage")
    UIDropDownMenu_Initialize(manageDrop, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        info.isTitle = true; info.text = L["Manual sellable (click to remove)"]; info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        local any = false
        for itemID in pairs(TS.db.manualSellable or {}) do
            any = true
            local info2 = UIDropDownMenu_CreateInfo()
            info2.text = TS:GetItemName(itemID); info2.notCheckable = true
            info2.func = function() TS:RemoveManualSellable(itemID); UI:Refresh(); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info2, level)
        end
        if not any then
            local info3 = UIDropDownMenu_CreateInfo()
            info3.text = "|cFF888888" .. L["(empty)"] .. "|r"; info3.notCheckable = true; info3.disabled = true
            UIDropDownMenu_AddButton(info3, level)
        end
    end)
    self.manageDrop = manageDrop
    local refreshBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    refreshBtn:SetSize(90, 22); refreshBtn:SetPoint("BOTTOMRIGHT", -28, 8)
    refreshBtn:SetText("Refresh"); refreshBtn:SetScript("OnClick", function() UI:Refresh() end)
    local clearBtn = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22); clearBtn:SetPoint("BOTTOMRIGHT", -122, 8)
    clearBtn:SetText("Clear"); clearBtn:SetScript("OnClick", function() TS.db.offers = {}; UI:Refresh() end)
end

-- ============================================================
-- CONSTRUCTION DE LA FENÊTRE PRINCIPALE
-- ============================================================

function UI:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "TradeScannerMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H); f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true); f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10); f:Hide()
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.09, 0.96)
    f:SetBackdropBorderColor(0.35, 0.35, 0.5, 1)
    self:_BuildTitleBar(f)
    self:_BuildTabButtons(f)
    self:_BuildOffersPane(f)
    self:_BuildOrdersPane(f)
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
    local tabW = TAB_W
    local tabH = 22
    local btn  = CreateFrame("Button", nil, parent)
    btn:SetSize(tabW, tabH)
    btn:SetPoint("TOPLEFT", 8 + (index - 1) * (tabW + 4), -48)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)
    btn.bg = bg
    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetAllPoints(); txt:SetText(tabDef.label); txt:SetTextColor(0.7, 0.7, 0.7)
    btn.txt = txt
    btn.tabID = tabDef.id
    btn:SetScript("OnClick", function(b) UI:SetTab(b.tabID) end)
    btn:SetScript("OnEnter", function(b)
        if UI.activeTab ~= b.tabID then b.bg:SetColorTexture(0.2, 0.2, 0.3, 0.9) end
    end)
    btn:SetScript("OnLeave", function(b)
        if UI.activeTab ~= b.tabID then
            b.bg:SetColorTexture(0.12, 0.12, 0.18, 0.9); b.txt:SetTextColor(0.7, 0.7, 0.7)
        end
    end)
    return btn
end

function UI:SetTab(tabID)
    self.activeTab = tabID
    for id, btn in pairs(self.tabBtns) do
        if id == tabID then
            btn.bg:SetColorTexture(0.15, 0.35, 0.65, 0.95); btn.txt:SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.12, 0.12, 0.18, 0.9); btn.txt:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    local isOrders = (tabID == "orders")
    if self.offersPane then self.offersPane:SetShown(not isOrders) end
    if self.ordersPane then self.ordersPane:SetShown(isOrders) end
    if tabID == "sell" and TS.Minimap then TS.Minimap:SetAlert(false) end
    -- Ouvrir Orders (clic = hardware event) → ping de présence "qui est en ligne ?"
    if isOrders and TS.Net then TS.Net:BroadcastWho() end
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
    elseif tab == "sell" then offers = TS:GetSellableOffers()
    end
    if not (self.searchText and self.searchText ~= "") then return offers end
    local needle   = self.searchText:lower()
    local filtered = {}
    for _, offer in ipairs(offers) do
        local label = (offer.itemID and TS:GetItemName(offer.itemID, offer.itemName))
                      or offer.itemName or offer.rawMsg or ""
        if label:lower():find(needle, 1, true)
           or (offer.player and offer.player:lower():find(needle, 1, true)) then
            table.insert(filtered, offer)
        end
    end
    return filtered
end

function UI:_FillRow(row, offer)
    row.offer = offer
    local srcTag = (offer.source == "guild") and "|cFFFFAA00[G]|r " or ""
    if offer.offerType == "sell" then row.typeFS:SetText(srcTag .. "|cFF33DD33WTS|r")
    else                              row.typeFS:SetText(srcTag .. "|cFF33AAFFWTB|r") end
    if offer.itemLink then
        row.itemFS:SetText(offer.itemLink)
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
            "%d offers  |  |cFFFFCC00%d WTB sellable|r  |  Channel: |cFF00CCFF%s|r  |  %s  |  %d profession(s)",
            totalAll, totalSell, TS.db and TS.db.channel or "?", guildState, profCount))
    end
    if self.chanLabel and TS.db then
        self.chanLabel:SetText("Watching: |cFF00CCFF#" .. TS.db.channel .. "|r")
    end
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
