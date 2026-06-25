-- TradeScanner_BagSell.lua
-- Raccourci sac → composeur WTS : Alt + clic droit sur un objet du sac AJOUTE l'objet
-- au composeur multi-item (TS.SellComposer), façon « pièces jointes d'un courrier » :
-- on empile plusieurs objets avec prix/quantité, puis on poste le tout d'un coup.
--
-- Ce fichier porte le hook d'entrée + la couche d'ENVOI chat (post multi-lignes avec
-- gestion de la limite de caractères côté composeur, + connexion au canal au besoin).
-- L'UI et la construction des messages vivent dans TradeScanner_SellComposer.lua.

local TS = TradeScanner
local BS = {}
TS.BagSell = BS
local L  = TS.L

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
        if TS.SellComposer then TS.SellComposer:AddItem(itemID, link, name, icon, stack) end
    end)
end

-- ============================================================
-- POST CHAT (multi-lignes) + connexion au canal
-- ============================================================

-- Poste une liste de lignes WTS dans le canal d'ENVOI par défaut (db.channel).
-- Premier message immédiat (pile du clic « Vendre »), les suivants étalés pour ne
-- pas déclencher l'anti-spam chat du client.
function BS:PostToChat(lines)
    if type(lines) == "string" then lines = { lines } end
    if not lines or #lines == 0 then return end
    local chan = TS.db and TS.db.channel
    if not chan or chan == "" then return end
    local id = GetChannelName(chan)
    if not (id and id > 0) then
        self:PromptJoinChannel(lines)
        return
    end
    for i, line in ipairs(lines) do
        if i == 1 then
            SendChatMessage(line, "CHANNEL", nil, id)
        else
            C_Timer.After((i - 1) * 0.6, function()
                local id2 = GetChannelName(chan)
                if id2 and id2 > 0 then SendChatMessage(line, "CHANNEL", nil, id2) end
            end)
        end
    end
end

function BS:PromptJoinChannel(lines)
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
                    for i, line in ipairs(lines) do
                        C_Timer.After((i - 1) * 0.6, function()
                            local id3 = GetChannelName(TS.db.channel)
                            if id3 and id3 > 0 then SendChatMessage(line, "CHANNEL", nil, id3) end
                        end)
                    end
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
