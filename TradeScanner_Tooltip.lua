-- TradeScanner_Tooltip.lua
-- Ajoute une ligne d'aide « Alt + clic droit : vendre » au survol des objets du SAC,
-- pour faire découvrir le raccourci de vente (cf. TradeScanner_BagSell / SellComposer).

local TS = TradeScanner

local function AddSellHint(tooltip)
    if not (TS.db and TS.db.bagSellEnabled) then return end
    tooltip:AddLine("|cFF00CCFF" .. TS.L["Alt + right-click: sell on the trade channel"] .. "|r")
    tooltip:Show()
end

-- GameTooltip:SetBagItem n'est appelée QUE pour les objets du sac → ciblage propre
-- (pas de pollution des tooltips d'HdV, marchand, équipement…). Hook valide en
-- Classic Era ; on garde une garde au cas où la méthode n'existerait pas.
if GameTooltip and GameTooltip.SetBagItem then
    hooksecurefunc(GameTooltip, "SetBagItem", function(tt) AddSellHint(tt) end)
end
