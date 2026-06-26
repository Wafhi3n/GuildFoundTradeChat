-- TradeScanner_GFMBridge.lua
-- Pont LECTURE SEULE vers GuildFoundMarket (GFM). TS agit comme un client GFM : il
-- émet les mêmes requêtes que GFM sur le canal caché et parse les réponses whisper,
-- pour afficher les ventes du marché GFM dans les onglets WTS + All.
--
-- POURQUOI ce pont : GFM n'a AUCUNE base partagée. Les offres des autres joueurs ne
-- sont jamais persistées — elles n'existent que le temps d'une requête live P2P (cf.
-- GuildFoundMarket/Core.lua). GFM n'expose pas non plus d'API en mémoire (son `ns` est
-- un upvalue privé). La seule voie est donc le protocole réseau, ici reproduit.
--
-- ARCHITECTURE : les offres récoltées vivent dans un BUCKET MÉMOIRE séparé (GFM.offers),
-- jamais écrit en SavedVariables ni passé à TS:AddOffer/db.offers. Elles sont fusionnées
-- UNIQUEMENT à l'affichage (UI:_GetActiveOffers). Ainsi le réseau TS (OF) et la
-- persistance ne voient jamais le marché GFM → pas de rediffusion, pas d'éviction des
-- offres chat (plafond 300), pas de pollution du fichier.
--
-- Gate d'activation : actif seulement si GFM est dans la liste d'addons du joueur
-- (C_AddOns.IsAddOnLoaded) ET si le toggle db.useGFM est actif ET si un canal est dérivable.

local TS  = TradeScanner
local GFM = {}
TS.GFM    = GFM

--========================================================================
-- Config (constantes alignées sur GuildFoundMarket/Core.lua)
--========================================================================
local GFM_ADDON        = "GuildFoundMarket"
local PREFIX           = "GFMarket"  -- prefix addon des réponses whisper de GFM (<=16 c.)
local CHAT_TAG         = "GFMqp1:"   -- tag protocole sur le canal caché (filtré par GFM chargé)
local SEND_TICK        = 0.30        -- s entre 2 whispers L~ (throttle, comme GFM)
local HARVEST_COOLDOWN = 45          -- s : anti-spam de récolte (reclics rapides sur WTS)
local SELLER_CAP       = 150         -- garde-fou : nb max de vendeurs collectés par scan

--========================================================================
-- État (tout local : rien n'est persisté)
--========================================================================
GFM.offers          = {}   -- BUCKET d'affichage : [seller#id#suffix] = offre au format TS
local channelName          -- nom du canal caché dérivé de l'info de guilde
local activeSid            -- id du scan vendeurs courant (jette les réponses périmées)
local activeLids    = {}   -- [lid] = seller : catalogues en cours de réception
local scanSeq       = 0
local lastHarvest   = 0
local sendQ         = {}    -- file throttlée de whispers L~ : { {msg, to}, ... }
local sellersSeen   = {}    -- [seller] = true durant un scan (dédup + cap)
local sellerCount   = 0
local refreshPending = false

--========================================================================
-- Dérivation du canal caché : port de simpleHash + parseGuildConfig + nom de canal
-- (GuildFoundMarket/Core.lua:104-140). GFM se gate sur une ligne GFMc:/GWc: de l'info
-- de guilde ; on dérive le même nom de canal "GFM<hex>" pour rejoindre le même marché.
--========================================================================
local function simpleHash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 0x7FFFFFFF end
    return h
end

local function parseGuildConfig()
    local text = GetGuildInfoText()
    if not text or text == "" then return nil end
    local vars, picked = {}, {}
    local function applyVars(s) return (s:gsub("%$(.)", function(n) return vars[n] or ("$" .. n) end)) end
    for line in text:gmatch("[^\r\n]+") do
        local src, op, args
        op, args = line:match("^GFM(%a):(.*)$"); if op then src = "GFM" end
        if not op then op, args = line:match("^GW(%a):(.*)$");  if op then src = "GW" end end
        if not op then op, args = line:match("^GW:(%a):(.*)$"); if op then src = "GW" end end
        if op then
            if op == "s" then
                local value, name = strsplit(":", args)
                if name and name ~= "" then vars[name] = value end
            elseif op == "c" then
                local chan, pass = strsplit(":", args)
                picked[src] = { channel = applyVars(chan or ""), password = pass or "" }
            end
        end
    end
    local chosen = picked.GFM or picked.GW
    if not chosen or not chosen.channel or chosen.channel == "" then return nil end
    return { channel = chosen.channel, password = chosen.password }
end

local function refreshChannelName()
    local cfg = parseGuildConfig()
    channelName = cfg and ("GFM" .. string.format("%x", simpleHash(cfg.channel .. ":" .. (cfg.password or "")))) or nil
    return channelName
end

-- Rejoint (ou retrouve) le canal caché ; renvoie son index ou nil. Si GFM est chargé il
-- a déjà rejoint ce canal → GetChannelName renvoie l'index existant (membership partagé).
local function ensureChannel()
    if not channelName then return nil end
    local idx = GetChannelName(channelName)
    if not idx or idx == 0 then
        JoinTemporaryChannel(channelName)
        idx = GetChannelName(channelName)
    end
    return (idx and idx > 0) and idx or nil
end

--========================================================================
-- Disponibilité + mapping offre GFM → offre TS
--========================================================================
local function gfmLoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(GFM_ADDON)
end

function GFM:IsAvailable()
    if not gfmLoaded() then return false end
    if TS.db and TS.db.useGFM == false then return false end
    return refreshChannelName() ~= nil
end

-- Construit une offre TS "sell" à partir d'une ligne de catalogue GFM.
local function makeOffer(seller, id, suffix, qty, price)
    local cat, prof = TS:GetProducible(id)
    return {
        offerType    = "sell",
        player       = seller,
        itemID       = id,
        itemName     = (GetItemInfo(id)),                       -- nil si pas en cache → résolu à l'affichage
        priceValue   = price,
        priceText    = (price > 0 and GetCoinTextureString(price)) or "Bid",
        qtyText      = (qty and qty > 1) and ("x" .. qty) or nil,
        timestamp    = time(),
        source       = "gfm",
        canCraft     = cat ~= nil,
        sellCategory = cat,
        profession   = prof,
        suffix       = suffix,
    }
end

-- Liste d'offres pour l'affichage (fusionnée dans UI:_GetActiveOffers). Respecte le
-- filtre "done" comme les offres chat. Vide si le pont est indisponible/désactivé.
function GFM:GetOffers()
    if not self:IsAvailable() then return {} end
    local list = {}
    for _, o in pairs(self.offers) do
        if not (TS.IsDone and TS:IsDone(o.player, o.itemID)) then
            list[#list + 1] = o
        end
    end
    return list
end

--========================================================================
-- Récolte : scan vendeurs (S~) puis catalogue de chacun (L~ → K~)
--========================================================================
local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.3, function()
        refreshPending = false
        if TS.UI and TS.UI.Refresh then TS.UI:Refresh() end
    end)
end

local function enqueueWhisper(msg, to)
    sendQ[#sendQ + 1] = { msg = msg, to = to }
end

-- DOIT être appelée dans la pile d'un hardware event (clic d'onglet) : le broadcast canal
-- (SendChatMessage CHANNEL) est refusé hors hardware event (ADDON_ACTION_BLOCKED).
function GFM:Harvest()
    if not self:IsAvailable() then return end
    local now = GetTime()
    if now - lastHarvest < HARVEST_COOLDOWN then return end   -- cache encore frais : on ne rescanne pas
    lastHarvest = now

    wipe(self.offers)      -- purge : la récolte reflète "en ligne maintenant"
    wipe(sellersSeen); wipe(activeLids); wipe(sendQ)
    sellerCount = 0
    scanSeq  = scanSeq + 1
    activeSid = "TS#S" .. scanSeq   -- namespace distinct du GFM local (pas de collision de sid)

    local idx = ensureChannel()
    if not idx then return end
    local gfmVer = (((C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata)(GFM_ADDON, "Version")) or "?"
    -- S~sid~filter(vide = qui vend ?)~version. On échote la version de GFM installée pour
    -- ne pas déclencher son nag de mise à jour chez les pairs (notePeerVersion).
    SendChatMessage(CHAT_TAG .. ("S~%s~~%s"):format(activeSid, gfmVer), "CHANNEL", nil, idx)
    scheduleRefresh()
end

--========================================================================
-- Réception des réponses whisper (CHAT_MSG_ADDON, prefix GFMarket)
--   C~sid~count~loc       : un vendeur répond au scan → on demande son catalogue
--   K~lid~more~chunk      : catalogue (id:qty:price:suffix;...) ; more==0 = dernier chunk
--========================================================================
local function handleReply(text, sender)
    local cmd, a, b, c = strsplit("~", text)
    if cmd == "C" then
        if a ~= activeSid then return end
        local seller = Ambiguate(sender, "short")
        if sellersSeen[seller] then return end
        if sellerCount >= SELLER_CAP then return end
        sellersSeen[seller] = true
        sellerCount = sellerCount + 1
        scanSeq = scanSeq + 1
        local lid = "TS#L" .. scanSeq
        activeLids[lid] = seller
        enqueueWhisper(("L~%s"):format(lid), seller)   -- demande de catalogue (throttlée)
    elseif cmd == "K" then
        local seller = activeLids[a]
        if not seller then return end
        for chunk in (c or ""):gmatch("[^;]+") do
            local id, qty, price, suffix = strsplit(":", chunk)
            id = tonumber(id)
            if id then
                local sfx = tonumber(suffix) or 0
                GFM.offers[seller .. "#" .. id .. "#" .. sfx] =
                    makeOffer(seller, id, sfx, tonumber(qty) or 0, tonumber(price) or 0)
            end
        end
        if tonumber(b) == 0 then activeLids[a] = nil end   -- catalogue complet
        scheduleRefresh()
    end
end

--========================================================================
-- Init & events (n'enregistre rien si GFM n'est pas chargé → pont inerte)
--========================================================================
function GFM:Init()
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    if not gfmLoaded() then return end   -- gate : GFM doit être dans la liste d'addons du joueur

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    refreshChannelName()

    local f = CreateFrame("Frame", "TradeScannerGFMFrame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, msg, _, sender = ...
            if prefix == PREFIX then handleReply(msg, sender) end
        else
            refreshChannelName()   -- l'info de guilde (et donc le canal) a pu changer
        end
    end)

    -- Pompe la file de whispers L~, throttlée comme GFM (un envoi par tick, retry si throttlé).
    -- On en profite pour garder le canal caché rejoint en arrière-plan, afin que le tout
    -- premier clic WTS trouve un index de canal valide (le join est asynchrone).
    C_Timer.NewTicker(SEND_TICK, function()
        ensureChannel()
        local item = sendQ[1]
        if not item then return end
        local res = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", item.to)
        local throttled = Enum and Enum.SendAddonMessageResult
            and res == Enum.SendAddonMessageResult.AddonMessageThrottle
        if not throttled then table.remove(sendQ, 1) end
    end)
end
