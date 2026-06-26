-- TradeScanner_SellComposer.lua
-- Composeur de vente multi-item (façon « pièces jointes d'un courrier »).
-- Alt + clic droit sur des objets du sac (cf. TradeScanner_BagSell) les empile ici ;
-- on règle prix/quantité par objet puis « Vendre tout » crée les offres locales et
-- poste un (ou plusieurs) message(s) WTS dans le canal d'envoi (TS.BagSell:PostToChat),
-- en découpant automatiquement sous la limite de caractères du chat.

local TS = TradeScanner
local SC = {}
TS.SellComposer = SC
local L  = TS.L

local ROW_H      = 26
local MAX_ROWS   = 40
local CHAT_LIMIT = 255
local PUB_TAG    = "[Guild Economy]"   -- auto-pub (Lot E), ajouté sur la dernière ligne

SC.basket = {}

-- ============================================================
-- CONSTRUCTION DES MESSAGES WTS (limite de caractères)
-- ============================================================

local function BuildSegment(it)
    local seg = it.itemLink or it.itemName or ("item:" .. tostring(it.itemID))
    if (it.qty or 1) > 1 then seg = seg .. " x" .. it.qty end
    if it.priceText and it.priceText ~= "" then seg = seg .. " " .. it.priceText end
    return seg
end

-- Regroupe les segments d'items en une ou plusieurs lignes "WTS ..." tenant sous la
-- limite chat. Le tag de pub est ajouté sur la DERNIÈRE ligne ; on réserve sa place
-- sur chaque ligne pour garantir que l'ajout final ne dépasse jamais la limite.
local function BuildMessages(items)
    local lines, prefix = {}, "WTS "
    local budget = CHAT_LIMIT - #PUB_TAG - 1
    local cur = prefix
    for _, it in ipairs(items) do
        local seg       = BuildSegment(it)
        local candidate = (cur == prefix) and (cur .. seg) or (cur .. " " .. seg)
        if #candidate > budget and cur ~= prefix then
            lines[#lines + 1] = cur
            cur = prefix .. seg
        else
            cur = candidate
        end
    end
    if cur ~= prefix then lines[#lines + 1] = cur end
    if #lines > 0 then lines[#lines] = lines[#lines] .. " " .. PUB_TAG end
    return lines
end

-- ============================================================
-- CONSTRUCTION UI
-- ============================================================

function SC:_BuildRow(content)
    local row = CreateFrame("Button", nil, content)
    row:SetSize(372, ROW_H)
    local hi = row:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.2)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20); row.icon:SetPoint("LEFT", 4, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", 28, 0); row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
    row.price = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.price:SetSize(70, 18); row.price:SetPoint("LEFT", 186, 0); row.price:SetAutoFocus(false)
    row.price:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    row.price:SetScript("OnTextChanged", function(b) if row.entry then row.entry.price = b:GetText() end end)
    row.qty = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.qty:SetSize(34, 18); row.qty:SetPoint("LEFT", 264, 0)
    row.qty:SetAutoFocus(false); row.qty:SetNumeric(true)
    row.qty:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    row.qty:SetScript("OnTextChanged", function(b) if row.entry then row.entry.qty = tonumber(b:GetText()) or 1 end end)
    row.rm = CreateFrame("Button", nil, row); row.rm:SetSize(16, 16); row.rm:SetPoint("LEFT", 308, 0)
    local t = row.rm:CreateTexture(nil, "ARTWORK"); t:SetAllPoints()
    t:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.rm:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row:SetScript("OnEnter", function(r)
        if not r.entry or not r.entry.itemLink then return end
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        local hl = r.entry.itemLink:match("|H([^|]+)|h")
        if hl then pcall(GameTooltip.SetHyperlink, GameTooltip, hl) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:Hide()
    return row
end

function SC:_BuildButtons(f)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 44); hint:SetTextColor(0.55, 0.55, 0.55)
    hint:SetText(L["Alt+right-click bag items to add them here."])
    -- Sélecteur de destination d'envoi (canaux surveillés + /g). Cliquer cycle.
    local postLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    postLbl:SetPoint("BOTTOMLEFT", 16, 18)
    postLbl:SetText(L["Post to:"])
    local destBtn = TS.UI.Skin.MakeGoldButton(f, 130, 22)
    destBtn:SetPoint("LEFT", postLbl, "RIGHT", 6, 0)
    destBtn:SetScript("OnClick", function() SC:_CycleDest() end)
    self.destBtn = destBtn
    local sell = TS.UI.Skin.MakeGoldButton(f, 90, 24, L["Sell all"])
    sell:SetPoint("BOTTOMRIGHT", -16, 12)
    sell:SetScript("OnClick", function() SC:Confirm() end)
    local clear = TS.UI.Skin.MakeGoldButton(f, 70, 24, L["Clear"])
    clear:SetPoint("RIGHT", sell, "LEFT", -8, 0)
    clear:SetScript("OnClick", function() SC:Clear() end)
end

-- Liste des destinations possibles : canaux surveillés + guilde (/g via GreenWall).
function SC:_DestList()
    local list = {}
    for _, c in ipairs(TS.db.channels or {}) do list[#list + 1] = c end
    if #list == 0 and TS.db.channel then list[1] = TS.db.channel end
    list[#list + 1] = "GUILD"
    return list
end

function SC:_DestLabel(dest)
    if dest == "GUILD" then return "/g (" .. L["Guild"] .. ")" end
    return dest or "?"
end

function SC:_CycleDest()
    local list = self:_DestList()
    local cur  = self.sendDest or TS.db.channel or list[1]
    local idx  = 1
    for i, d in ipairs(list) do if d == cur then idx = i; break end end
    idx = (idx % #list) + 1
    self.sendDest = list[idx]
    if self.destBtn then self.destBtn:SetText(self:_DestLabel(self.sendDest)) end
end

function SC:_Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "TradeScannerSellComposer", UIParent, "BackdropTemplate")
    f:SetSize(420, 340); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:Hide()
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14); title:SetText("|cFF00CCFF" .. L["Sell to Guild Economy"] .. "|r")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    local function hdr(txt, x)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", x, -44); fs:SetText("|cFFAAAAAA" .. txt .. "|r")
    end
    hdr(L["Item"], 24); hdr(L["Price"], 210); hdr(L["Qty"], 290)
    local scroll = CreateFrame("ScrollFrame", "TradeScannerSellComposerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -60); scroll:SetSize(376, 220)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(376, 220)
    scroll:SetScrollChild(content)
    self.scroll, self.content, self.rows = scroll, content, {}
    self:_BuildButtons(f)
    self.frame = f
end

-- ============================================================
-- DONNÉES / REFRESH
-- ============================================================

function SC:_RefreshRows()
    if not self.content then return end
    for _, row in ipairs(self.rows) do row:Hide() end
    local n = math.min(#self.basket, MAX_ROWS)
    for i = 1, n do
        local row = self.rows[i]
        if not row then row = self:_BuildRow(self.content); self.rows[i] = row end
        local it = self.basket[i]
        row.entry = it
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.icon:SetTexture(it.icon or 134400)
        row.name:SetText(it.itemLink or it.itemName or "?")
        if not row.price:HasFocus() then row.price:SetText(it.price or "") end
        if not row.qty:HasFocus()   then row.qty:SetText(tostring(it.qty or 1)) end
        row.rm:SetScript("OnClick", function() SC:RemoveItem(it) end)
        row:Show()
    end
    self.content:SetHeight(math.max(n * ROW_H, 1))
end

function SC:AddItem(itemID, link, name, icon, stack)
    if not itemID then return end
    for _, it in ipairs(self.basket) do
        if it.itemID == itemID then self:Open(); return end  -- déjà dans le panier
    end
    self.basket[#self.basket + 1] = {
        itemID = itemID, itemLink = link, itemName = name, icon = icon,
        stack = stack or 1, price = "", qty = stack or 1,
    }
    self:Open()
end

function SC:RemoveItem(entry)
    for i = #self.basket, 1, -1 do
        if self.basket[i] == entry then table.remove(self.basket, i); break end
    end
    self:_RefreshRows()
end

function SC:Clear()
    wipe(self.basket)
    self:_RefreshRows()
end

function SC:Open()
    self:_Build()
    if not self.sendDest then self.sendDest = TS.db.channel end
    if self.destBtn then self.destBtn:SetText(self:_DestLabel(self.sendDest)) end
    self:_RefreshRows()
    self.frame:Show()
end

-- ============================================================
-- VALIDATION
-- ============================================================

function SC:Confirm()
    if #self.basket == 0 then return end
    local items = {}
    for _, it in ipairs(self.basket) do
        local priceText, priceValue = TS:ParsePrice(it.price or "")
        local qty = tonumber(it.qty) or 1
        if qty < 1 then qty = 1 end
        local qtyText = qty > 1 and ("x" .. qty) or nil
        -- Offre locale + broadcast réseau (garanti même si le chat échoue).
        TS:CreateLocalOffer(it.itemID, it.itemLink, it.itemName, priceText, priceValue, qtyText, "")
        -- Unification : vendre un objet le marque aussi « vendable » (persistant) →
        -- il remonte dans l'onglet Sellable + alertes craft. Retrait via Réglages.
        TS:AddManualSellable(it.itemID)
        items[#items + 1] = { itemID = it.itemID, itemLink = it.itemLink,
                              itemName = it.itemName, qty = qty, priceText = priceText }
    end
    local lines = BuildMessages(items)
    if TS.BagSell then TS.BagSell:PostToChat(lines, self.sendDest) end
    self:Clear()
    if self.frame then self.frame:Hide() end
end
