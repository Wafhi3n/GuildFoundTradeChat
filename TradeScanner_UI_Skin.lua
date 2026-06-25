-- TradeScanner_UI_Skin.lua — Thème « tavern doré » centralisé de la fenêtre principale.
-- Palette mappée 1:1 depuis le design system Guild Economy (tokens/colors.css, direction
-- warm tavern). Expose UI.Skin : table de couleurs + helpers de skinning consommés par
-- TradeScanner_UI / _UI_Rows / _UI_Categories / _UI_Filters.
--
-- INTOUCHABLE : le langage couleur des offres (WTS vert / WTB bleu / WTG violet), les
-- indicateurs Provide (or / cyan / vert) et la rareté d'objet ne sont JAMAIS recolorés ici.
-- Ce module ne touche QUE le chrome (surfaces brunes, cadre or, onglets, en-têtes, ombres).

local TS = TradeScanner
local UI = TS.UI
local Skin = {}
UI.Skin = Skin

-- ============================================================
-- PALETTE (RGB 0..1) — cf. tokens/colors.css
-- ============================================================

Skin.color = {
    panel     = { 0.082, 0.063, 0.043 },        -- #15100b fond fenêtre (warm near-black)
    panel2    = { 0.114, 0.086, 0.063 },        -- #1d1610 panneau encastré
    stone     = { 0.141, 0.110, 0.078 },        -- #241c14 tablette d'onglet / sidebar
    stoneHi   = { 0.204, 0.157, 0.110 },        -- #34281c bevel highlight / hover onglet
    void      = { 0.039, 0.031, 0.024 },        -- #0a0806 puits le plus profond
    gold      = { 0.910, 0.722, 0.294 },        -- #e8b84b or primaire (en-têtes)
    goldHi    = { 0.941, 0.776, 0.455 },        -- #f0c674 or vif (titre, tri actif)
    goldOre   = { 0.541, 0.392, 0.125 },        -- #8a6420 métal sombre
    price     = { 1.000, 0.867, 0.000 },        -- #ffdd00 prix
    border    = { 0.353, 0.290, 0.180 },        -- #5a4a2e métal du cadre
    separator = { 0.353, 0.290, 0.180 },        -- ligne 1px warm (remplace le slate-violet)
    text      = { 0.910, 0.863, 0.784 },        -- #e8dcc8 crème
    textMuted = { 0.550, 0.550, 0.550 },        -- statut / secondaire
    tabActive = { 0.149, 0.349, 0.651 },        -- #2659A6 onglet actif (bleu, inchangé)
    rowEven   = { 0.114, 0.090, 0.063, 0.55 },  -- zébrage warm pair
    rowOdd    = { 0.075, 0.059, 0.043, 0.40 },  -- zébrage warm impair
    rowHover  = { 0.25,  0.45,  0.85,  0.25 },  -- wash bleu au survol (inchangé)
}

-- Versions |cffRRGGBB pour le texte inline (status bar, etc.).
Skin.hex = {
    gold      = "FFE8B84B",
    goldHi    = "FFF0C674",
    price     = "FFFFDD00",
    muted     = "FF8C8C8C",
    cyan      = "FF00CCFF",
}

local function unpackc(c) return c[1], c[2], c[3], c[4] or 1 end
Skin.unpack = unpackc

-- ============================================================
-- OMBRE PORTÉE — chaque texte WoW reçoit un drop 1px noir dur
-- ============================================================

function Skin.ApplyShadow(fs)
    if fs and fs.SetShadowColor then
        fs:SetShadowColor(0, 0, 0, 0.95)
        fs:SetShadowOffset(1, -1)
    end
    return fs
end

-- ============================================================
-- WORDMARK — « Guild Economy » gravé en or (police bundle MORPHEUS)
-- ============================================================

local wordmarkFont
function Skin.WordmarkFont()
    if not wordmarkFont then
        wordmarkFont = CreateFont("TradeScannerWordmarkFont")
        if not wordmarkFont:SetFont("Fonts\\MORPHEUS.ttf", 24, "") then
            -- Repli si MORPHEUS indisponible (locales non-latines) : serif standard.
            wordmarkFont:SetFontObject("GameFontNormalLarge")
        end
        wordmarkFont:SetTextColor(unpackc(Skin.color.goldHi))
        wordmarkFont:SetShadowColor(0, 0, 0, 1)
        wordmarkFont:SetShadowOffset(1, -1)
    end
    return wordmarkFont
end

-- ============================================================
-- CADRE — fond brun chaud + bordure or ornementée (bundle Blizzard)
-- ============================================================

function Skin.SkinFrameBackdrop(f)
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- Fond OPAQUE : évite que le chat / le monde derrière ne « bave » à travers la
    -- fenêtre (le texte fantôme et le point rouge venaient de cette semi-transparence).
    f:SetBackdropColor(Skin.color.panel[1], Skin.color.panel[2], Skin.color.panel[3], 1)
    f:SetBackdropBorderColor(1, 1, 1, 1)  -- le rope or est déjà coloré dans la texture
end

-- Puits encastré warm (sidebar / zones de liste), bevel-in via backdrop sombre.
function Skin.SkinWell(f)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(Skin.color.void[1], Skin.color.void[2], Skin.color.void[3], 0.85)
    f:SetBackdropBorderColor(Skin.color.goldOre[1], Skin.color.goldOre[2], Skin.color.goldOre[3], 0.7)
end

-- ============================================================
-- SÉPARATEUR — fine ligne 1px warm
-- ============================================================

function Skin.MakeSeparator(parent, offsetY)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(Skin.color.separator[1], Skin.color.separator[2], Skin.color.separator[3], 0.7)
    sep:SetPoint("TOPLEFT",  4,  offsetY)
    sep:SetPoint("TOPRIGHT", -4, offsetY)
    return sep
end

-- ============================================================
-- ONGLETS — tablettes de pierre warm ; actif = bleu, texte blanc
-- ============================================================

function Skin.TabColors(btn, state)
    -- state : "active" | "hover" | "idle"
    if state == "active" then
        btn.bg:SetColorTexture(unpackc(Skin.color.tabActive)); btn.bg:SetAlpha(0.95)
        btn.txt:SetTextColor(1, 1, 1)
    elseif state == "hover" then
        btn.bg:SetColorTexture(unpackc(Skin.color.stoneHi)); btn.bg:SetAlpha(0.95)
    else
        btn.bg:SetColorTexture(unpackc(Skin.color.stone)); btn.bg:SetAlpha(0.9)
        btn.txt:SetTextColor(unpackc(Skin.color.text))
    end
end

-- ============================================================
-- EN-TÊTES DE COLONNES — texte or (or vif si tri actif)
-- ============================================================

function Skin.HeaderColor(fs, active)
    fs:SetTextColor(unpackc(active and Skin.color.goldHi or Skin.color.gold))
    Skin.ApplyShadow(fs)
end

-- ============================================================
-- EMPTY-STATE — scène tavern peinte (bannières Alliance/Horde,
-- grimoire, or). Texture livrée avec l'addon (PNG → TGA 1024×512,
-- cf. Textures\tavern-empty.tga). Dégrade proprement si absente :
-- il reste un panneau sombre + le label.
-- ============================================================

local EMPTY_TEX = "Interface\\AddOns\\TradeScanner\\Textures\\tavern-empty.tga"

-- Scène tavern peinte en filigrane PERMANENT derrière le tableau : la texture +
-- un voile assombrissant (alpha piloté par UI:_UpdateEmptyState — léger quand vide
-- pour faire ressortir la scène, soutenu quand des offres s'affichent pour la
-- lisibilité). Le label « no offers » n'est montré que lorsque le tableau est vide.
-- `region` = cadre dont la scène épouse les bords (le ScrollFrame du tableau).
function Skin.BuildTableScene(parent, region)
    local s = {}
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
    tex:SetPoint("TOPLEFT",     region, "TOPLEFT",     0, 0)
    tex:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 22, 0)
    tex:SetTexture(EMPTY_TEX)
    tex:SetVertexColor(0.85, 0.85, 0.85, 1)
    s.tex = tex
    local veil = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
    veil:SetPoint("TOPLEFT", tex, "TOPLEFT"); veil:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT")
    veil:SetColorTexture(Skin.color.panel[1], Skin.color.panel[2], Skin.color.panel[3], 1)
    veil:SetAlpha(0.62)
    s.veil = veil
    -- Label centré bas, masqué tant qu'il y a des offres (sous les lignes en z-order,
    -- mais visible quand le tableau est vide).
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOM", tex, "BOTTOM", 0, 22)
    label:SetTextColor(unpackc(Skin.color.text))
    Skin.ApplyShadow(label)
    label:Hide()
    s.label = label
    return s
end

-- Bouton or « maison » (cadre métal warm + texte or). N'utilise PAS de template
-- Blizzard : échappe ainsi aux addons de skin externes (ElvUI/Masque) qui reteintent
-- les UIPanelButtonTemplate en rouge. Expose SetText/GetFontString comme un bouton std.
function Skin.MakeGoldButton(parent, w, h, text)
    local small = (h <= 16)  -- liseré + police réduits pour les petits boutons (lignes)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",  -- liseré 1px carré, scale parfait
        edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local fs = b:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    fs:SetPoint("CENTER"); Skin.ApplyShadow(fs)
    if text then fs:SetText(text) end
    b.text = fs
    b.selected = false
    b.SetText = function(self, t) self.text:SetText(t) end
    b.GetFontString = function(self) return self.text end
    -- État au repos : honore la sélection (onglet métier actif = stone-hi + or vif).
    local function rest(self)
        if self.selected then
            self:SetBackdropColor(unpackc(Skin.color.stoneHi))
            self:SetBackdropBorderColor(unpackc(Skin.color.goldHi))
            self.text:SetTextColor(unpackc(Skin.color.goldHi))
        else
            self:SetBackdropColor(unpackc(Skin.color.stone))
            self:SetBackdropBorderColor(unpackc(Skin.color.border))
            self.text:SetTextColor(unpackc(Skin.color.gold))
        end
    end
    b.SetSelected = function(self, on) self.selected = on; rest(self) end
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpackc(Skin.color.stoneHi))
        self:SetBackdropBorderColor(unpackc(Skin.color.goldHi))
        self.text:SetTextColor(unpackc(Skin.color.goldHi))
    end)
    b:SetScript("OnLeave", rest)
    -- Enfoncement : on assombrit le fond (pas de re-ancrage du texte, pour rester
    -- compatible avec un libellé aligné à gauche comme « Quality: … »).
    b:SetScript("OnMouseDown", function(self) self:SetBackdropColor(unpackc(Skin.color.void)) end)
    b:SetScript("OnMouseUp",   rest)
    rest(b)
    return b
end
