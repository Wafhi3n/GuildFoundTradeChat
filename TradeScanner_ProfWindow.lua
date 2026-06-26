-- TradeScanner_ProfWindow.lua
-- Fenêtre métier MONO-BLOC : remplace la fenêtre Blizzard (TradeSkillFrame / CraftFrame)
-- par une fenêtre custom 3 colonnes — Recettes | Détail+Craft | Guild wants.
-- La frame native est NEUTRALISÉE (alpha 0, mouse off) mais jamais Hide() tant que la
-- session est ouverte : son OnHide appellerait CloseTradeSkill/CloseCraft et viderait
-- l'API de lecture. Les colonnes vivent dans _Recipes / _Detail / _Wants.

local TS = TradeScanner
local PW = {}
TS.ProfWindow = PW
local L  = TS.L

PW.FRAME_W   = 776
PW.FRAME_H   = 484
PW.HEADER_H  = 56
PW.COL_W_REC = 232
PW.COL_W_DET = 248
PW.COL_W_WAN = 248
PW.COL_GAP   = 10
PW.PAD       = 14

-- ------------------------------------------------------------------
-- Neutralisation de la frame native (garde la session vivante)
-- ------------------------------------------------------------------

local NATIVE = {}  -- état sauvegardé par clé pour restauration propre

-- Toggle : nil/true = on remplace, false = on laisse l'UI Blizzard (échappatoire conflits).
local function takeoverEnabled()
    return not (TS.db and TS.db.replaceProfWindow == false)
end

local function neutralize(frame, key)
    if not frame then return end
    if not NATIVE[key] then
        NATIVE[key] = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled() }
    end
    -- On NE Hide PAS (déclencherait CloseTradeSkill/CloseCraft). On rend invisible + inerte.
    frame:SetAlpha(0)
    frame:EnableMouse(false)
end

local function restore(frame, key)
    if not frame or not NATIVE[key] then return end
    frame:SetAlpha(NATIVE[key].alpha or 1)
    frame:EnableMouse(NATIVE[key].mouse ~= false)
    NATIVE[key] = nil
end

-- Retire les frames natives du gestionnaire de panneaux UNE fois : sinon elles repoussent
-- la feuille de perso / sac en s'ouvrant. Sans danger (aucune fonction sécurisée). Idempotent.
local uiPanelDetached = false
local function detachUIPanels()
    if uiPanelDetached then return end
    uiPanelDetached = true
    if _G.UIPanelWindows then
        UIPanelWindows["TradeSkillFrame"] = nil
        UIPanelWindows["CraftFrame"]      = nil
    end
end

function PW:NeutralizeNative()
    detachUIPanels()
    neutralize(_G.TradeSkillFrame, "trade")
    neutralize(_G.CraftFrame,      "craft")
end

function PW:RestoreNative()
    restore(_G.TradeSkillFrame, "trade")
    restore(_G.CraftFrame,      "craft")
end

-- ------------------------------------------------------------------
-- Construction du shell
-- ------------------------------------------------------------------

function PW:_BuildHeader(f)
    local mark = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetPoint("TOPLEFT", 14, -12)
    mark:SetText("Guild Economy")
    mark:SetTextColor(TS.UI.Skin.unpack(TS.UI.Skin.color.goldOre))
    TS.UI.Skin.ApplyShadow(mark)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Profession")
    title:SetTextColor(TS.UI.Skin.unpack(TS.UI.Skin.color.goldHi))
    TS.UI.Skin.ApplyShadow(title)
    self.titleFS = title

    local rank = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rank:SetPoint("TOP", title, "BOTTOM", 0, -2)
    rank:SetTextColor(TS.UI.Skin.unpack(TS.UI.Skin.color.text))
    TS.UI.Skin.ApplyShadow(rank)
    self.rankFS = rank

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    -- Fermer la fenêtre custom ferme aussi la session de métier (comme la native).
    close:SetScript("OnClick", function()
        if TS.ProfWindow:IsCraftSession() then
            if CloseCraft then CloseCraft() end
        elseif CloseTradeSkill then
            CloseTradeSkill()
        end
        PW:Hide()
    end)

    TS.UI.Skin.MakeSeparator(f, -(self.HEADER_H - 2))
end

-- Crée un conteneur de colonne (well sombre) ancré et de largeur fixe.
function PW:_BuildColumn(f, width, leftAnchor)
    local col = CreateFrame("Frame", nil, f)
    col:SetWidth(width)
    col:SetPoint("TOPLEFT", leftAnchor.frame, leftAnchor.point, leftAnchor.x, -self.HEADER_H)
    col:SetPoint("BOTTOM", f, "BOTTOM", 0, self.PAD)
    if TS.UI.Skin.SkinWell then TS.UI.Skin.SkinWell(col) end
    return col
end

function PW:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "TradeScannerProfWindow", UIParent, "BackdropTemplate")
    f:SetSize(self.FRAME_W, self.FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    TS.UI.Skin.SkinFrameBackdrop(f)
    f:Hide()

    self.frame = f
    self:_BuildHeader(f)

    local recCol = self:_BuildColumn(f, self.COL_W_REC, { frame = f, point = "TOPLEFT", x = self.PAD })
    local detCol = self:_BuildColumn(f, self.COL_W_DET, { frame = recCol, point = "TOPRIGHT", x = self.COL_GAP })
    local wanCol = self:_BuildColumn(f, self.COL_W_WAN, { frame = detCol, point = "TOPRIGHT", x = self.COL_GAP })
    self.recCol, self.detCol, self.wanCol = recCol, detCol, wanCol

    if self._BuildRecipes then self:_BuildRecipes(recCol) end
    if self._BuildDetail  then self:_BuildDetail(detCol)  end
    if self._BuildWants   then self:_BuildWants(wanCol)   end
end

-- ------------------------------------------------------------------
-- État / helpers
-- ------------------------------------------------------------------

function PW:IsCraftSession()
    return TS:IsCraftOpen()
end

function PW:OpenProfessionName()
    local name = TS:GetOpenProfessionInfo()
    return name
end

function PW:Hide()
    if self.frame then self.frame:Hide() end
end

-- ------------------------------------------------------------------
-- Refresh (coalescé) — relit les recettes et rafraîchit les 3 colonnes
-- ------------------------------------------------------------------

function PW:_DoRefresh()
    self._refreshPending = false
    if not self.frame or not self.frame:IsShown() then return end
    local name = self:OpenProfessionName()
    if not name then return end

    self.titleFS:SetText(name)
    local rank, maxRank = TS:GetOpenProfessionRank()
    if rank and maxRank then
        self.rankFS:SetText(string.format("|cFFE8B84B%d|r / %d", rank, maxRank))
    else
        self.rankFS:SetText("")
    end

    self.recipes = TS:ReadOpenRecipes() or {}
    if self.RefreshRecipes then self:RefreshRecipes() end
    if self.RefreshDetail  then self:RefreshDetail()  end
    if self.RefreshWants   then self:RefreshWants()   end
end

function PW:Refresh()
    if not (C_Timer and C_Timer.After) then return self:_DoRefresh() end
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.1, function() PW:_DoRefresh() end)
end

-- ------------------------------------------------------------------
-- Entrées d'événements (appelées depuis TradeScanner.lua)
-- ------------------------------------------------------------------

function PW:OnProfessionShow()
    if not takeoverEnabled() then
        self:RestoreNative()
        return
    end
    if not self:OpenProfessionName() then return end
    self:Build()
    self:NeutralizeNative()
    if not self.frame:IsShown() then self.frame:Show() end
    self:Refresh()
end

function PW:OnProfessionClose()
    self.selectedIndex = nil
    self:Hide()
    self:RestoreNative()
end
