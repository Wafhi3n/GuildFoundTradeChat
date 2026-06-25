-- TradeScanner_UI_Rows.lua — Row construction for the main offer table

local TS = TradeScanner
local UI = TS.UI

local FRAME_W = 700
local ROW_H   = 22
local COLUMNS = {
    { label = "Type",    w = 42,  x = 10  },
    { label = "Item",    w = 215, x = 56  },
    { label = "Price",   w = 88,  x = 275 },
    { label = "Player",  w = 115, x = 367 },
    { label = "Age",     w = 34,  x = 486 },
    { label = "Provide", w = 120, x = 524 },
}

local function UIRowTooltip(r)
    if not r.offer then return end
    GameTooltip:SetOwner(r, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    if r.offer.itemLink then
        local hyperlink = r.offer.itemLink:match("|H([^|]+)|h")
        if hyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, hyperlink) end
    elseif r.offer.itemID then
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. r.offer.itemID)
    else
        GameTooltip:AddLine(r.offer.rawMsg or "", 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    local ot = r.offer.offerType
    local typeLabel = (ot == "sell" and "Sale") or (ot == "gift" and "Gift") or "Wanted"
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
    if r.doneBtn then r.doneBtn:Show() end
    if r.wBtn    then r.wBtn:Show()    end
end

local function AddRowButtons(row)
    local doneBtn = CreateFrame("Button", nil, row)
    doneBtn:SetSize(16, 16)
    doneBtn:SetPoint("RIGHT", -26, 0)
    local doneIcon = doneBtn:CreateTexture(nil, "ARTWORK")
    doneIcon:SetAllPoints()
    doneIcon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    doneBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    doneBtn:SetScript("OnClick", function()
        if row.offer and row.offer.player and row.offer.itemID then
            TS:MarkDone(row.offer.player, row.offer.itemID, false)
        end
    end)
    doneBtn:Hide()
    row.doneBtn = doneBtn
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
end

function UI:BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(FRAME_W - 32, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then bg:SetColorTexture(0.09, 0.09, 0.13, 0.7)
    else                    bg:SetColorTexture(0.05, 0.05, 0.09, 0.5) end
    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints(); hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)
    local craftBar = row:CreateTexture(nil, "ARTWORK")
    craftBar:SetWidth(3); craftBar:SetPoint("TOPLEFT"); craftBar:SetPoint("BOTTOMLEFT")
    craftBar:SetColorTexture(1, 0.78, 0, 1); craftBar:Hide()
    row.craftBar = craftBar
    row.typeFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.typeFS:SetPoint("LEFT", COLUMNS[1].x, 0); row.typeFS:SetWidth(COLUMNS[1].w); row.typeFS:SetJustifyH("CENTER")
    row.itemFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.itemFS:SetPoint("LEFT", COLUMNS[2].x, 0); row.itemFS:SetWidth(COLUMNS[2].w)
    row.itemFS:SetJustifyH("LEFT"); row.itemFS:SetWordWrap(false)
    row.priceFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.priceFS:SetPoint("LEFT", COLUMNS[3].x, 0); row.priceFS:SetWidth(COLUMNS[3].w)
    row.priceFS:SetJustifyH("LEFT"); row.priceFS:SetTextColor(1, 0.88, 0.1)
    row.playerFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.playerFS:SetPoint("LEFT", COLUMNS[4].x, 0); row.playerFS:SetWidth(COLUMNS[4].w)
    row.playerFS:SetJustifyH("LEFT"); row.playerFS:SetTextColor(0.85, 0.85, 0.85)
    row.ageFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ageFS:SetPoint("LEFT", COLUMNS[5].x, 0); row.ageFS:SetWidth(COLUMNS[5].w)
    row.ageFS:SetJustifyH("CENTER"); row.ageFS:SetTextColor(0.5, 0.5, 0.5)
    row.craftFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.craftFS:SetPoint("LEFT", COLUMNS[6].x, 0); row.craftFS:SetWidth(COLUMNS[6].w)
    row.craftFS:SetJustifyH("LEFT"); row.craftFS:SetTextColor(1, 0.78, 0)
    AddRowButtons(row)
    row:SetScript("OnEnter", UIRowTooltip)
    row:SetScript("OnLeave", function(r)
        GameTooltip:Hide()
        if r.doneBtn then r.doneBtn:Hide() end
        if r.wBtn    then r.wBtn:Hide()    end
    end)
    row:SetScript("OnClick", function(r)
        if r.offer and r.offer.player then
            ChatFrame_OpenChat("/w " .. r.offer.player .. " ")
        end
    end)
    row:Hide()
    return row
end
