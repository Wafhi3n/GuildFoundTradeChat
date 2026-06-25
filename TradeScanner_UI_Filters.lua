-- TradeScanner_UI_Filters.lua
-- En-têtes de colonnes cliquables (tri façon Hôtel des ventes) pour le tableau
-- d'offres de la fenêtre principale, + la logique de tri UI:_SortOffers.
-- La colonne "Provide" n'est pas triable.

local TS = TradeScanner
local UI = TS.UI

-- Mêmes positions que les colonnes de TradeScanner_UI(_Rows). `sort` = clé de tri.
local COLUMNS = {
    { label = "Type",    w = 42,  x = 10,  sort = "type"   },
    { label = "Item",    w = 215, x = 56,  sort = "item"   },
    { label = "Price",   w = 88,  x = 275, sort = "price"  },
    { label = "Player",  w = 115, x = 367, sort = "player" },
    { label = "Age",     w = 34,  x = 486, sort = "age"    },
    { label = "Provide", w = 120, x = 524 },
}

local ARROW_UP   = " \226\150\178"  -- ▲
local ARROW_DOWN = " \226\150\188"  -- ▼

function UI:_BuildSortableHeaders(pane)
    self.headerBtns = {}
    for _, col in ipairs(COLUMNS) do
        if col.sort then
            local b = CreateFrame("Button", nil, pane)
            b:SetPoint("TOPLEFT", col.x, -4); b:SetSize(col.w, 16)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetAllPoints(); fs:SetJustifyH("LEFT")
            b.fs, b.baseLabel, b.sortKey = fs, col.label, col.sort
            b:SetScript("OnClick", function() UI:_OnHeaderClick(col.sort) end)
            self.headerBtns[col.sort] = b
        else
            local fs = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", col.x, -6); fs:SetWidth(col.w); fs:SetJustifyH("LEFT")
            fs:SetText("|cFFAAAAAA" .. col.label .. "|r")
        end
    end
    self:_UpdateHeaderLabels()
end

function UI:_OnHeaderClick(key)
    if self.sortKey == key then
        self.sortAsc = not self.sortAsc
    else
        self.sortKey, self.sortAsc = key, true
    end
    self:_UpdateHeaderLabels()
    self:Refresh()
end

function UI:_UpdateHeaderLabels()
    for key, b in pairs(self.headerBtns or {}) do
        local arrow = ""
        if self.sortKey == key then arrow = self.sortAsc and ARROW_UP or ARROW_DOWN end
        b.fs:SetText("|cFFAAAAAA" .. b.baseLabel .. arrow .. "|r")
    end
end

-- Tri en place de la liste d'offres selon la colonne sélectionnée. Égalités
-- départagées par fraîcheur (offre la plus récente d'abord) pour rester stable.
function UI:_SortOffers(list)
    local key = self.sortKey
    if not key then return list end
    local asc = self.sortAsc
    local function val(o)
        if key == "type"   then return o.offerType or "" end
        if key == "price"  then return o.priceValue or 0 end
        if key == "player" then return (o.player or ""):lower() end
        if key == "age"    then return time() - (o.timestamp or 0) end
        return (TS:GetItemName(o.itemID, o.itemName) or o.rawMsg or ""):lower()  -- item
    end
    table.sort(list, function(a, b)
        local va, vb = val(a), val(b)
        if va == vb then return (a.timestamp or 0) > (b.timestamp or 0) end
        if asc then return va < vb else return va > vb end
    end)
    return list
end
