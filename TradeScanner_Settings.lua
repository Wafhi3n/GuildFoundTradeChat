-- TradeScanner_Settings.lua
-- Panneau de réglages (ouvert par le bouton engrenage de la fenêtre principale ou
-- /ts settings). Regroupe : canaux surveillés (multi-canaux v1.5), canal d'envoi,
-- toggles (son, /g, GreenWall, bagSell, debug) et gestion du vendable manuel
-- (déplacé depuis l'ancien bloc « Sell+ » de la fenêtre principale).

local TS  = TradeScanner
local SET = {}
TS.Settings = SET
local L   = TS.L

local W, H        = 520, 440
local ROW_H       = 18
local MAX_CHAN    = 7
local MAX_SELL    = 120  -- plafond de lignes pooled pour le vendable manuel

-- ============================================================
-- HELPERS
-- ============================================================

local function MakeCheck(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetChecked(get() and true or false)
    cb:SetScript("OnClick", function(b) set(b:GetChecked() and true or false) end)
    return cb
end

-- Petit bouton "X" rouge de suppression de ligne.
local function MakeRemoveBtn(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

-- ============================================================
-- CONSTRUCTION
-- ============================================================

function SET:_BuildChannels(f)
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 16, -40)
    hdr:SetText("|cFFFFCC00" .. L["Watched channels"] .. "|r")

    self.chanRows = {}
    for i = 1, MAX_CHAN do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(220, ROW_H)
        row:SetPoint("TOPLEFT", 16, -58 - (i - 1) * ROW_H)
        row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.fs:SetPoint("LEFT", 2, 0); row.fs:SetJustifyH("LEFT")
        row.rm = MakeRemoveBtn(row)
        row.rm:SetPoint("LEFT", row.fs, "LEFT", 200, 0)
        row:Hide()
        self.chanRows[i] = row
    end

    local addBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    addBox:SetSize(120, 18)
    addBox:SetPoint("TOPLEFT", 18, -58 - MAX_CHAN * ROW_H - 6)
    addBox:SetAutoFocus(false)
    addBox:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    self.chanAddBox = addBox
    local function DoAdd()
        if TS:AddWatchedChannel(addBox:GetText()) then
            JoinChannelByName((addBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end
        addBox:SetText(""); addBox:ClearFocus()
        self:Refresh(); if TS.UI then TS.UI:Refresh() end
    end
    addBox:SetScript("OnEnterPressed", DoAdd)
    local addBtn = TS.UI.Skin.MakeGoldButton(f, 50, 22, L["Add"])
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    addBtn:SetScript("OnClick", DoAdd)
end

function SET:_BuildSendChannel(f)
    local y = -58 - MAX_CHAN * ROW_H - 34
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 16, y)
    lbl:SetText(L["Send channel:"])
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(120, 18)
    box:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(b)
        local name = (b:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if name ~= "" then TS.db.channel = name end
        b:ClearFocus(); if TS.UI then TS.UI:Refresh() end
    end)
    self.sendBox = box
end

function SET:_BuildToggles(f)
    local y0 = -58 - MAX_CHAN * ROW_H - 62
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(0.3, 0.3, 0.45, 0.9)
    sep:SetPoint("TOPLEFT", 14, y0 + 6); sep:SetPoint("TOPRIGHT", f, "TOPLEFT", 250, y0 + 6)

    local db = TS.db
    MakeCheck(f, L["Craft alert sound"], 16, y0,
        function() return db.alertSound end, function(v) db.alertSound = v end)
    MakeCheck(f, L["Scan guild chat (/g)"], 16, y0 - 26,
        function() return db.scanGuild end, function(v) db.scanGuild = v end)
    MakeCheck(f, L["Cross-realm sync (GreenWall)"], 16, y0 - 52,
        function() return db.useGreenWall end, function(v) db.useGreenWall = v end)
    MakeCheck(f, L["Bag Alt-right-click to sell"], 16, y0 - 78,
        function() return db.bagSellEnabled end, function(v) db.bagSellEnabled = v end)
    MakeCheck(f, L["Debug log (chat)"], 16, y0 - 104,
        function() return db.debugLog end, function(v) db.debugLog = v end)
end

function SET:_BuildSellable(f)
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", 270, -40)
    hdr:SetText("|cFF88FF88" .. L["Manual sellable"] .. "|r")

    local addBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    addBox:SetSize(140, 18); addBox:SetPoint("TOPLEFT", 272, -62); addBox:SetAutoFocus(false)
    addBox:SetScript("OnEscapePressed", function(b) b:SetText(""); b:ClearFocus() end)
    self.sellAddBox = addBox
    local function DoAdd()
        local txt    = addBox:GetText() or ""
        local itemID = tonumber(txt:match("|Hitem:(%d+)")) or tonumber(txt:match("^%s*(%d+)%s*$"))
        if itemID then
            TS:AddManualSellable(itemID); addBox:SetText(""); addBox:ClearFocus()
            self:Refresh(); if TS.UI then TS.UI:Refresh() end
        else
            print("|cFF00CCFFGuild Economy|r " .. L["Shift-click an item or enter an item ID."])
        end
    end
    addBox:SetScript("OnEnterPressed", DoAdd)
    local addBtn = TS.UI.Skin.MakeGoldButton(f, 50, 22, L["Add"])
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    addBtn:SetScript("OnClick", DoAdd)

    local scroll = CreateFrame("ScrollFrame", "TradeScannerSettingsSellScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 272, -88)
    scroll:SetSize(210, H - 130)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(210, H - 130)
    scroll:SetScrollChild(content)
    self.sellScroll  = scroll
    self.sellContent = content
    self.sellRows    = {}
end

function SET:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "TradeScannerSettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(W, H); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cFF00CCFFGuild Economy|r — " .. L["Settings"])
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    self:_BuildChannels(f)
    self:_BuildSendChannel(f)
    self:_BuildToggles(f)
    self:_BuildSellable(f)
    self.frame = f
end

-- ============================================================
-- REFRESH
-- ============================================================

function SET:_RefreshChannels()
    local list = TS.db.channels or {}
    for i, row in ipairs(self.chanRows) do
        local name = list[i]
        if name then
            row.fs:SetText("|cFF00CCFF" .. name .. "|r")
            row.rm:SetScript("OnClick", function()
                TS:RemoveWatchedChannel(name)
                self:Refresh(); if TS.UI then TS.UI:Refresh() end
            end)
            row:Show()
        else
            row:Hide()
        end
    end
    if self.sendBox and not self.sendBox:HasFocus() then
        self.sendBox:SetText(TS.db.channel or "")
    end
end

function SET:_RefreshSellable()
    if not self.sellContent then return end
    local items = {}
    for itemID in pairs(TS.db.manualSellable or {}) do items[#items + 1] = itemID end
    table.sort(items, function(a, b)
        return (TS:GetItemName(a) or "") < (TS:GetItemName(b) or "")
    end)
    for i, row in ipairs(self.sellRows) do row:Hide() end
    local shown = math.min(#items, MAX_SELL)
    for i = 1, shown do
        local row = self.sellRows[i]
        if not row then
            row = CreateFrame("Frame", nil, self.sellContent)
            row:SetSize(200, ROW_H)
            row.fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.fs:SetPoint("LEFT", 2, 0); row.fs:SetWidth(176)
            row.fs:SetJustifyH("LEFT"); row.fs:SetWordWrap(false)
            row.rm = MakeRemoveBtn(row)
            row.rm:SetPoint("RIGHT", 0, 0)
            self.sellRows[i] = row
        end
        local itemID = items[i]
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.fs:SetText(TS:GetItemName(itemID))
        row.rm:SetScript("OnClick", function()
            TS:RemoveManualSellable(itemID)
            self:Refresh(); if TS.UI then TS.UI:Refresh() end
        end)
        row:Show()
    end
    self.sellContent:SetHeight(math.max(shown * ROW_H, 1))
end

function SET:Refresh()
    if not self.frame then return end
    self:_RefreshChannels()
    self:_RefreshSellable()
end

-- ============================================================
-- TOGGLE
-- ============================================================

function SET:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end
