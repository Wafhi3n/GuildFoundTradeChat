-- TradeScanner_Trade.lua
-- Auto-validation des commandes de craft via la fenêtre d'échange (côté ACHETEUR).
--
-- Principe : seul le destinataire valide. Quand un trade se conclut et qu'un objet
-- REÇU correspond à une de MES commandes ouvertes, on la valide automatiquement
-- (Guild:FulfillOrder → CF). Le crafter (qui DONNE l'objet) ne déclenche rien ;
-- s'il faut valider à la main (acheteur sans addon), c'est le bouton « Valider ».
--
-- Le snapshot des objets reçus est pris au moment où les DEUX parties acceptent
-- (les liens d'objet ne sont plus lisibles une fois la fenêtre fermée). La
-- conclusion réelle est déduite : trade accepté des 2 côtés puis fermé SANS
-- annulation (TRADE_REQUEST_CANCEL).
--
-- Diffusion en local-only : on est dans un handler d'event (pas un hardware event),
-- donc pas de relais GreenWall cross-guilde (→ ADDON_ACTION_BLOCKED). Les
-- guildmates locaux reçoivent le CF ; en confédération, le crafter peut valider
-- manuellement de son côté.

local TS    = TradeScanner
local Trade = {}
TS.Trade    = Trade

-- Quantités reçues du partenaire, agrégées par itemID (slots 1..6 ; le 7 = « ne
-- sera pas échangé »). Un même item peut occuper plusieurs slots → on cumule.
local function SnapshotReceivedItems()
    local byItem = {}
    if not GetTradeTargetItemLink then return byItem end
    for i = 1, 6 do
        local link = GetTradeTargetItemLink(i)
        local id   = link and tonumber(link:match("item:(%d+)"))
        if id then
            local _, _, qty = GetTradeTargetItemInfo(i)
            byItem[id] = (byItem[id] or 0) + (qty or 1)
        end
    end
    return byItem
end

function Trade:OnComplete()
    local pending = self.pending
    self.pending, self.accepted = nil, false
    if not pending or not TS.Guild then return end
    for itemID, qty in pairs(pending) do
        local o = TS.Guild:MyOrderForItem(itemID)
        if o then
            -- livraison partielle = décrémente ; complète = retire (côté FulfillOrder)
            TS.Guild:FulfillOrder(o.buyer, TS.Guild:OrderKey(o), qty, false, true)
        end
    end
end

function Trade:Init()
    local f = CreateFrame("Frame", "TradeScannerTradeFrame")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_REQUEST_CANCEL")
    f:RegisterEvent("TRADE_CLOSED")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "TRADE_SHOW" then
            Trade.accepted, Trade.pending = false, nil
        elseif event == "TRADE_ACCEPT_UPDATE" then
            -- arg1 = moi accepté, arg2 = partenaire accepté
            if arg1 == 1 and arg2 == 1 then
                Trade.accepted = true
                Trade.pending  = SnapshotReceivedItems()
            end
        elseif event == "TRADE_REQUEST_CANCEL" then
            Trade.accepted, Trade.pending = false, nil
        elseif event == "TRADE_CLOSED" then
            -- Fermé après acceptation mutuelle sans annulation ⇒ trade conclu.
            if Trade.accepted then Trade:OnComplete() end
            Trade.accepted = false
        end
    end)
end
