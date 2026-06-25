-- TradeScanner_UI_Categories.lua
-- Bande latérale gauche « façon Hôtel des ventes » de la fenêtre principale :
--   - ARBRE de catégories déroulant : catégorie (classID) → sous-catégorie (subClassID),
--     ex. Armes → Épées à une main / Haches à deux mains… ; Armure → Tissu / Cuir / …
--   - filtre QUALITÉ (bouton qui cycle : Toutes → Médiocre … Légendaire),
--   - filtre NIVEAU requis (min / max).
-- Fournit aussi le prédicat UI:_OfferPassesFilters utilisé par UI:_GetActiveOffers.

local TS = TradeScanner
local UI = TS.UI
local L  = TS.L

local SIDEBAR_INNER = 150   -- doit rester < SIDEBAR_W (166) de TradeScanner_UI.lua
local ROW_H         = 18
local INDENT        = 12     -- décalage par niveau de profondeur

-- Catégories de tête (classID API objet) dans l'ordre d'affichage.
local TOP_CLASSES = { 2, 4, 0, 7, 9, 1, 3, 5, 12, 15 }

-- Repli si GetItemClassInfo renvoie nil.
local CLASS_FALLBACK = {
    [0] = "Consumable", [1] = "Container", [2] = "Weapon", [3] = "Gem", [4] = "Armor",
    [5] = "Reagent", [7] = "Trade Goods", [9] = "Recipe", [12] = "Quest", [15] = "Miscellaneous",
}

local QUALITIES = { nil, 0, 1, 2, 3, 4, 5 }  -- Toutes, Médiocre → Légendaire

-- Armure : 3e niveau = slots d'équipement (invType). Restreint aux sous-classes
-- PORTÉES (Divers/Tissu/Cuir/Mailles/Plaques) pour éviter le bruit sous Boucliers/reliques.
local ARMOR_WEARABLE = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
local ARMOR_SLOTS = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
    "INVTYPE_CHEST", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST",
    "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
    "INVTYPE_SHIELD", "INVTYPE_HOLDABLE",
}

local function ClassLabel(classID)
    return (GetItemClassInfo and GetItemClassInfo(classID))
        or CLASS_FALLBACK[classID] or ("class " .. classID)
end

local function QualityText(q)
    if q == nil then return L["Quality"] .. ": " .. L["Any"] end
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    local c    = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
    return L["Quality"] .. ": " .. ((c and c.hex) or "|cFFFFFFFF") .. name .. "|r"
end

-- ============================================================
-- CONSTRUCTION DE L'ARBRE (une seule fois)
-- ============================================================

-- Énumère les sous-classes valides d'une classe via GetItemSubClassInfo (0..20).
local function BuildSubNodes(classID)
    local nodes = {}
    for sub = 0, 20 do
        local name = GetItemSubClassInfo and GetItemSubClassInfo(classID, sub)
        if name and name ~= "" then
            local node = { label = name, classID = classID, subClassID = sub }
            -- Armure portable → 3e niveau : slots d'équipement.
            if classID == 4 and ARMOR_WEARABLE[sub] then
                node.children = {}
                for _, slot in ipairs(ARMOR_SLOTS) do
                    node.children[#node.children + 1] = {
                        label = _G[slot] or slot, classID = classID,
                        subClassID = sub, invType = slot,
                    }
                end
            end
            nodes[#nodes + 1] = node
        end
    end
    return nodes
end

function UI:_BuildCategoryTree()
    if self.catTree then return end
    local tree = { { label = L["All"], isAll = true } }
    for _, classID in ipairs(TOP_CLASSES) do
        local node = { label = ClassLabel(classID), classID = classID }
        local subs = BuildSubNodes(classID)
        if #subs >= 2 then node.children = subs end  -- déroulable si ≥2 sous-catégories
        tree[#tree + 1] = node
    end
    self.catTree     = tree
    self.selectedNode = tree[1]  -- « Toutes » par défaut
end

-- ============================================================
-- CLASSIFICATION + PRÉDICAT
-- ============================================================

function UI:_ItemClassInfo(itemID)
    if not itemID then return nil end
    local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    return classID, subClassID, equipLoc
end

-- True si l'offre passe les filtres catégorie/sous-catégorie/qualité/niveau actifs.
-- Les offres sans itemID (messages bruts) ne passent que si aucun filtre objet n'est actif.
function UI:_OfferPassesFilters(offer)
    local catID, subID = self.filterClassID, self.filterSubClassID
    local q, lmin, lmax = self.filterQuality, self.filterLevelMin, self.filterLevelMax
    if not catID and q == nil and not lmin and not lmax then return true end
    local itemID = offer.itemID
    if not itemID then return false end
    if catID then
        local c, s, e = self:_ItemClassInfo(itemID)
        if c ~= catID then return false end
        if subID and s ~= subID then return false end
        if self.filterInvType and e ~= self.filterInvType then return false end
    end
    if q ~= nil or lmin or lmax then
        local _, _, quality, _, reqLevel = GetItemInfo(itemID)
        if quality ~= nil then  -- nil = pas encore en cache → on laisse passer
            if q ~= nil and quality < q then return false end
            reqLevel = reqLevel or 0
            if lmin and reqLevel < lmin then return false end
            if lmax and reqLevel > lmax then return false end
        end
    end
    return true
end

-- ============================================================
-- FILTRES QUALITÉ / NIVEAU
-- ============================================================

function UI:_BuildQualityFilter(sb)
    self._qIdx = 1
    -- Bouton or maison (échappe au skin externe rouge), libellé aligné à gauche.
    local btn = UI.Skin.MakeGoldButton(sb, SIDEBAR_INNER, 20, QualityText(nil))
    btn:SetPoint("TOPLEFT", 0, 0)
    local bfs = btn:GetFontString()
    bfs:ClearAllPoints(); bfs:SetPoint("LEFT", 8, 0); bfs:SetJustifyH("LEFT")
    btn:SetScript("OnClick", function()
        self._qIdx = (self._qIdx % #QUALITIES) + 1
        self.filterQuality = QUALITIES[self._qIdx]
        btn:SetText(QualityText(self.filterQuality))
        self:Refresh()
    end)
end

function UI:_BuildLevelFilter(sb)
    local lbl = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 0, -28); lbl:SetText(L["Level"])
    lbl:SetTextColor(UI.Skin.unpack(UI.Skin.color.gold)); UI.Skin.ApplyShadow(lbl)
    local function box(xoff)
        local b = CreateFrame("EditBox", nil, sb, "InputBoxTemplate")
        b:SetSize(28, 18); b:SetPoint("TOPLEFT", xoff, -26)
        b:SetAutoFocus(false); b:SetNumeric(true)
        b:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
        return b
    end
    local minB, maxB = box(42), box(86)
    local dash = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dash:SetPoint("LEFT", minB, "RIGHT", 6, 0); dash:SetText("-")
    local function apply()
        self.filterLevelMin = tonumber(minB:GetText())
        self.filterLevelMax = tonumber(maxB:GetText())
        self:Refresh()
    end
    minB:SetScript("OnTextChanged", apply); maxB:SetScript("OnTextChanged", apply)
end

-- ============================================================
-- ARBRE DÉROULANT (scroll + lignes poolées)
-- ============================================================

function UI:_BuildTreeRow()
    local row = CreateFrame("Button", nil, self.catTreeContent)
    row:SetSize(SIDEBAR_INNER - 22, ROW_H)
    local sel = row:CreateTexture(nil, "BACKGROUND"); sel:SetAllPoints()
    sel:SetColorTexture(0.15, 0.35, 0.65, 0.9); sel:Hide(); row.sel = sel
    local hi = row:CreateTexture(nil, "HIGHLIGHT"); hi:SetAllPoints()
    hi:SetColorTexture(0.25, 0.45, 0.85, 0.25)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("RIGHT", 0, 0); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    UI.Skin.ApplyShadow(fs)
    row.fs = fs
    row:SetScript("OnClick", function(r) if r.node then UI:_OnNodeClick(r.node) end end)
    return row
end

local function FlattenInto(out, nodes, depth)
    for _, n in ipairs(nodes) do
        out[#out + 1] = { node = n, depth = depth }
        if n.children and n.expanded then FlattenInto(out, n.children, depth + 1) end
    end
end

function UI:_RenderTree()
    local flat = {}
    FlattenInto(flat, self.catTree, 0)
    self.catTreeContent:SetHeight(math.max(#flat * ROW_H, 1))
    for _, row in ipairs(self.catTreeRows) do row:Hide() end
    for i, e in ipairs(flat) do
        local row = self.catTreeRows[i]
        if not row then row = self:_BuildTreeRow(); self.catTreeRows[i] = row end
        local node = e.node
        row.node = node
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local prefix = node.children and (node.expanded and "- " or "+ ") or ""
        row.fs:ClearAllPoints()
        row.fs:SetPoint("LEFT", 2 + e.depth * INDENT, 0)
        row.fs:SetPoint("RIGHT", 0, 0)
        row.fs:SetText(prefix .. node.label)
        if node == self.selectedNode then
            row.fs:SetTextColor(1, 1, 1)
        else
            row.fs:SetTextColor(UI.Skin.unpack(UI.Skin.color.text))
        end
        row.sel:SetShown(node == self.selectedNode)
        row:Show()
    end
end

-- Clic : sélectionne le nœud comme filtre actif et déroule/replie s'il a des enfants.
function UI:_OnNodeClick(node)
    self.selectedNode     = node
    self.filterClassID    = node.classID
    self.filterSubClassID = node.subClassID
    self.filterInvType    = node.invType
    if node.children then node.expanded = not node.expanded end
    self:_RenderTree()
    self:Refresh()
end

function UI:_BuildSidebar(f)
    if self.sidebar then return end
    local sb = CreateFrame("Frame", nil, f)
    sb:SetPoint("TOPLEFT",    14, -72)
    sb:SetPoint("BOTTOMLEFT", 14,  14)
    sb:SetWidth(SIDEBAR_INNER)
    self.sidebar = sb
    self:_BuildCategoryTree()
    self:_BuildQualityFilter(sb)
    self:_BuildLevelFilter(sb)
    -- Puits encastré warm derrière l'arbre de catégories (cf. skin).
    local well = CreateFrame("Frame", nil, sb, "BackdropTemplate")
    well:SetPoint("TOPLEFT", 0, -54); well:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.Skin.SkinWell(well)
    local scroll = CreateFrame("ScrollFrame", "TradeScannerCatScroll", sb, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -58); scroll:SetPoint("BOTTOMRIGHT", -22, 4)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SIDEBAR_INNER - 22, 10)
    scroll:SetScrollChild(content)
    self.catTreeScroll, self.catTreeContent, self.catTreeRows = scroll, content, {}
    self:_RenderTree()
end
