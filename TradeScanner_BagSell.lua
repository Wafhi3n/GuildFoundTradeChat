-- TradeScanner_BagSell.lua
-- Raccourci sac → popup WTS : Alt + clic droit sur un objet du sac ouvre une
-- popup (prix / quantité / note) qui crée l'offre locale (+ broadcast réseau OF)
-- et poste un message WTS dans le canal de commerce (pour les non-utilisateurs
-- de l'addon), en vérifiant/proposant la connexion au canal au besoin.

local TS = TradeScanner
local BS = {}
TS.BagSell = BS
local L  = TS.L

local TRADE_TAG = "WTS"   -- préfixe du message chat

-- ============================================================
-- HOOK : Alt + clic droit sur un objet du sac
-- ============================================================

function BS:Init()
    if self._hooked then return end
    self._hooked = true
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn, button)
        if button ~= "RightButton" then return end
        if not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
        if TS.db and TS.db.bagSellEnabled == false then return end

        local bag  = btn:GetParent() and btn:GetParent():GetID()
        local slot = btn:GetID()
        if not bag or not slot then return end
        local link = C_Container.GetContainerItemLink(bag, slot)
        if not link then return end

        local info     = C_Container.GetContainerItemInfo(bag, slot)
        local itemID   = info and info.itemID
        local icon     = info and info.iconFileID
        local stack    = (info and info.stackCount) or 1
        local name     = link:match("%[(.-)%]") or TS:GetItemName(itemID)
        if not itemID then return end
        BS:ShowPopup(itemID, link, name, icon, stack)
    end)
end

-- ============================================================
-- POPUP
-- ============================================================

function BS:_BuildPopup()
    local f = CreateFrame("Frame", "TradeScannerBagSellPopup", UIParent, "BackdropTemplate")
    f:SetSize(340, 210)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
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

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cFF00CCFF" .. L["Sell to Guild Economy"] .. "|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("TOPLEFT", 18, -44)
    f.itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.itemLabel:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.itemLabel:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.itemLabel:SetJustifyH("LEFT")
    f.itemLabel:SetWordWrap(false)

    f.priceBox = self:_LabeledBox(f, L["Price"], -86, false)
    f.qtyBox   = self:_LabeledBox(f, L["Qty"],   -114, true)
    f.noteBox  = self:_LabeledBox(f, L["Note"],  -142, false)

    local confirm = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    confirm:SetSize(90, 22)
    confirm:SetPoint("BOTTOMRIGHT", -16, 14)
    confirm:SetText(L["Sell"])
    confirm:SetScript("OnClick", function() BS:Confirm() end)
    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("RIGHT", confirm, "LEFT", -8, 0)
    cancel:SetText(L["Cancel"])
    cancel:SetScript("OnClick", function() f:Hide() end)

    f.priceBox:SetScript("OnEnterPressed", function() BS:Confirm() end)
    f:Hide()
    self.popup = f
end

-- Crée un EditBox InputBoxTemplate avec un libellé à gauche, ancré à yOff.
function BS:_LabeledBox(f, labelText, yOff, numeric)
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 18, yOff)
    lbl:SetWidth(60)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(labelText)
    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(220, 18)
    box:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(numeric and true or false)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    return box
end

function BS:ShowPopup(itemID, link, name, icon, stack)
    if not self.popup then self:_BuildPopup() end
    local f = self.popup
    f.itemID, f.itemLink, f.itemName = itemID, link, name
    f.icon:SetTexture(icon or 134400)  -- 134400 = point d'interrogation par défaut
    f.itemLabel:SetText(link or name or "?")
    f.priceBox:SetText("")
    f.qtyBox:SetText(tostring(stack or 1))
    f.noteBox:SetText("")
    f:Show()
    f.priceBox:SetFocus()
end

-- ============================================================
-- VALIDATION
-- ============================================================

function BS:Confirm()
    local f = self.popup
    if not f or not f.itemID then return end
    local priceText, priceValue = TS:ParsePrice(f.priceBox:GetText() or "")
    local qty  = tonumber(f.qtyBox:GetText()) or 1
    if qty < 1 then qty = 1 end
    local note = (f.noteBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local qtyText = qty > 1 and ("x" .. qty) or nil

    -- 1) offre locale + broadcast réseau (garanti même si le chat échoue)
    TS:CreateLocalOffer(f.itemID, f.itemLink, f.itemName, priceText, priceValue, qtyText, note)

    -- 2) message chat pour les non-utilisateurs de l'addon
    local parts = { TRADE_TAG, f.itemLink }
    if qty > 1 then parts[#parts + 1] = "x" .. qty end
    if priceText then parts[#parts + 1] = priceText end
    if note ~= "" then parts[#parts + 1] = note end
    self:PostToChat(table.concat(parts, " "))

    f:Hide()
end

-- ============================================================
-- POST CHAT + connexion au canal
-- ============================================================

function BS:PostToChat(message)
    local chan = TS.db and TS.db.channel
    if not chan or chan == "" then return end
    local id = GetChannelName(chan)
    if id and id > 0 then
        SendChatMessage(message, "CHANNEL", nil, id)
    else
        self:PromptJoinChannel(message)
    end
end

function BS:PromptJoinChannel(message)
    StaticPopupDialogs["TRADESCANNER_JOIN_CHANNEL"] = {
        text         = L["Not connected to the trade channel. Channel to join:"],
        button1      = L["Join"],
        button2      = CANCEL,
        hasEditBox   = true,
        timeout      = 0,
        whileDead    = true,
        hideOnEscape = true,
        OnShow = function(dlg)
            dlg.editBox:SetText(TS.db.channel or "")
            dlg.editBox:HighlightText()
        end,
        OnAccept = function(dlg)
            local name = dlg.editBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return end
            TS.db.channel = name:lower()
            JoinChannelByName(name)
            C_Timer.After(1, function()
                local id2 = GetChannelName(TS.db.channel)
                if id2 and id2 > 0 then
                    SendChatMessage(message, "CHANNEL", nil, id2)
                else
                    print("|cFF00CCFFGuild Economy|r " ..
                        string.format(L["Could not join channel '%s'."], TS.db.channel))
                end
            end)
        end,
        EditBoxOnEnterPressed = function(editBox)
            local parent = editBox:GetParent()
            if parent.button1 and parent.button1:IsEnabled() then parent.button1:Click() end
        end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    }
    StaticPopup_Show("TRADESCANNER_JOIN_CHANNEL")
end
