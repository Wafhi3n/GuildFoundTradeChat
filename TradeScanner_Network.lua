-- TradeScanner_Network.lua
-- Sync réseau inter-addon (guilde locale + GreenWall cross-serveur)
-- Protocoles: HI (hello), WHO/IM (présence), OF (offer), DN (done)

local TS  = TradeScanner
local NET = {}
TS.Net    = NET

local PREFIX      = "TradeScanner"
local HELLO_DELAY = 5      -- secondes après login (attendre stabilité)
local OFFER_TICK  = 0.1    -- secondes entre envois staggered
local MAX_OFFERS  = 50     -- max offres envoyées par sync

local HELLO_RESPOND_THROTTLE = 10   -- s : un seul HI honoré par fenêtre (logins groupés)
local HELLO_JITTER           = 3    -- s : étalement aléatoire des réponses au HI
local SEND_INTERVAL          = 0.15 -- s entre 2 AddonMessage (~6-7 msg/s, sous le plafond client)

-- ============================================================
-- ENVOI
-- ============================================================

-- Envoi guilde locale (canal addon). Jamais soumis à ADDON_ACTION_BLOCKED.
-- File FIFO throttlée : le client WoW a un plafond caché de débit d'AddonMessage,
-- au-delà duquel des messages sont DROPPÉS silencieusement (→ resync incomplète).
-- On borne donc le débit sortant global, quelle que soit la source (events isolés
-- + tickers de resync staggered). 1er message immédiat (latence ~0 pour un envoi
-- isolé), les suivants espacés de SEND_INTERVAL. Ordre préservé.
local sendQueue = {}
local sendBusy  = false

local function RawSend(payload)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    end
end

local function PumpSend()
    if sendBusy then return end
    local payload = table.remove(sendQueue, 1)
    if not payload then return end
    RawSend(payload)
    sendBusy = true
    C_Timer.After(SEND_INTERVAL, function()
        sendBusy = false
        PumpSend()
    end)
end

function NET:Send(payload)
    if not payload or payload == "" then return end
    if not (C_Timer and C_Timer.After) then return RawSend(payload) end
    sendQueue[#sendQueue + 1] = payload
    PumpSend()
end

-- Envoi à la confédération (guildes sœurs) via GreenWall.
-- ⚠️ À n'appeler QUE dans la pile d'un hardware event (clic/touche joueur) :
-- GreenWall relaie via SendChatMessage sur un canal, fonction protégée que le
-- client refuse d'exécuter hors hardware event (→ ADDON_ACTION_BLOCKED).
function NET:SendConfederation(payload)
    if not payload or payload == "" then return end
    if TS.db and TS.db.useGreenWall == false then return end
    if not (GreenWallAPI and type(GreenWallAPI.SendMessage) == "function") then return end
    if TS.db and TS.db.gwDebug then
        print("|cFF00CCFF[GW→]|r " .. payload)
    end
    pcall(GreenWallAPI.SendMessage, PREFIX, payload)
end

-- Envoie un HELLO (invite les autres à envoyer leurs offres)
function NET:BroadcastHello()
    self:Send("HI")
end

local function GetAddonVersion()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return (f and f("TradeScanner", "Version")) or "?"
end

-- Ping de présence "qui est en ligne ?" — déclenché par un clic (onglet/Refresh).
-- Volontairement GUILDE-LOCALE : la réponse IM ne peut PAS traverser GreenWall
-- (émise depuis un handler réseau, hors hardware event). Throttlé pour éviter le spam.
function NET:BroadcastWho()
    local now = GetTime()
    if self.lastWho and (now - self.lastWho) < 5 then return end
    self.lastWho = now
    self:Send("WHO")
end

-- Réponse de présence : "IM|version". Émise depuis un handler réseau (réception
-- de WHO) → guilde locale uniquement (pas de hardware event).
function NET:BroadcastPresence()
    self:Send("IM|" .. GetAddonVersion())
end

-- Envoie une offre unique
function NET:BroadcastOffer(offer)
    if not offer or offer.source == "network" then return end
    -- Offre en texte brut (sans lien d'objet) : chaque client la parse lui-même depuis le
    -- chat. La diffuser via OF (qui ne porte pas le rawMsg) la reconstruirait en "item:0"
    -- chez les autres → on ne diffuse que les offres avec un itemID réel. (hotfix 1.5.1)
    if not offer.itemID then return end
    local payload = string.format("OF|%s|%s|%s|%d|%s|%d",
        offer.player or "",
        offer.offerType or "",
        offer.itemID,
        offer.priceValue or 0,
        (offer.priceText or ""):gsub("|", ""),  -- échappe les pipes
        offer.timestamp or 0
    )
    self:Send(payload)
end

-- Envoie toutes les offres actives staggered (réponse à HI)
function NET:SendAllOffersDelayed()
    local offers = TS:GetOffers(nil)  -- toutes offres non-expirées
    local sent = 0

    local ticker = C_Timer.NewTicker(OFFER_TICK, function(ticker)
        if sent >= #offers or sent >= MAX_OFFERS then
            ticker:Cancel()
            return
        end
        sent = sent + 1
        self:BroadcastOffer(offers[sent])
    end, MAX_OFFERS)
end

-- Broadcast qu'une offre est traitée
function NET:BroadcastDone(player, itemID)
    if not player or not itemID then return end
    local payload = string.format("DN|%s|%d", player, itemID)
    self:Send(payload)
end

-- Réponse à un HELLO reçu : resync de MES offres.
-- Deux protections d'échelle (cf. doc charge à l'échelle) :
--   • Throttle : un seul HI honoré par fenêtre — si plusieurs membres se loguent
--     en rafale, on ne relance pas N jeux de tickers de resync concurrents.
--   • Jitter : délai initial aléatoire — quand 50 membres reçoivent le MÊME HI, on
--     évite que tous démarrent leur resync au même instant (burst synchronisé).
function NET:RespondToHello()
    local now = GetTime()
    if self.lastHelloResp and (now - self.lastHelloResp) < HELLO_RESPOND_THROTTLE then
        return
    end
    self.lastHelloResp = now
    C_Timer.After(math.random() * HELLO_JITTER, function()
        NET:SendAllOffersDelayed()
    end)
end

-- ============================================================
-- RÉCEPTION
-- ============================================================

-- Extrait le nom court du joueur (sans realm)
local function GetPlayerShort(fullName)
    if not fullName then return nil end
    return fullName:match("^([^%-]+)") or fullName
end

function NET:_HandleOF(message)
    -- Match ancré (comme CO/CC/CA) : le split naïf "[^|]+" comptait le token "OF"
    -- comme 1er champ (décalage) et avalait les champs vides (priceText ""), cf. bug v1.3.4.
    local player, offerType, itemID, priceValue, priceText, timestamp =
        message:match("^OF|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if not player then return end
    itemID     = tonumber(itemID)
    -- Ignore les offres sans objet réel (itemID 0 = client pré-1.5.1 diffusant une offre
    -- texte brut → "item:0"). Elles sont de toute façon parsées localement depuis le chat.
    if not itemID or itemID == 0 then return end
    priceValue = tonumber(priceValue) or 0
    timestamp  = tonumber(timestamp) or time()
    TS:AddOffer({
        offerType    = offerType, player = player, itemID = itemID,
        -- nil si l'objet n'est pas encore en cache (résolu à l'affichage) ; l'appel
        -- GetItemInfo déclenche aussi le chargement asynchrone. (hotfix 1.5.2)
        itemName     = (GetItemInfo(itemID)),
        itemLink     = nil, priceText = (priceText ~= "" and priceText) or nil,
        priceValue   = priceValue, rawMsg = nil, timestamp = timestamp,
        source       = "network",
    })
end

function NET:_HandleDN(message)
    -- Match ancré : "DN|player|itemID" (l'ancien split prenait "DN" comme player).
    local player, itemID = message:match("^DN|([^|]+)|(%d+)")
    if player and itemID then TS:MarkDone(player, tonumber(itemID), true) end
end

function NET:HandleMessage(senderName, message)
    if not message or message == "" then return end
    local playerShort = GetPlayerShort(senderName)
    local cmd = message:match("^([A-Z]+)")

    -- Présence passive : tout message reçu prouve que l'expéditeur est en ligne avec l'addon.
    if TS.Guild and playerShort then TS.Guild:MarkSeen(playerShort) end

    if cmd == "HI" then
        self:RespondToHello()

    elseif cmd == "WHO" then
        -- Ping de présence : je réponds qui je suis (version).
        self:BroadcastPresence()

    elseif cmd == "IM" then
        -- "IM|version" — réponse de présence d'un membre.
        if TS.Guild then
            local ver = message:match("^IM|(.*)$")
            TS.Guild:MarkSeen(playerShort, ver ~= "" and ver or nil)
        end

    elseif cmd == "OF" then self:_HandleOF(message)
    elseif cmd == "DN" then self:_HandleDN(message)

    -- Verbes de métiers (PR/RK) et de commandes de craft (CO/CC/CA/CF) DÉCOMMISSIONNÉS
    -- (Étape F) : le craft-social vit désormais entièrement dans « Crafting Order - Classic ».
    -- GE n'émet plus et n'agit plus sur ces messages.
    end
end

-- ============================================================
-- INIT & EVENTS
-- ============================================================

function NET:Init()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return  -- trop vieux ou pas dispo
    end

    -- Graine RNG dépendante du perso : le jitter des réponses au HI doit DIFFÉRER
    -- d'un client à l'autre (math.random non semé = même séquence → aucun étalement).
    if math.randomseed then
        local seed = (time and time() or 0)
        local n = UnitName and UnitName("player")
        if n then for i = 1, #n do seed = seed + n:byte(i) * i end end
        math.randomseed(seed)
    end

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Enregistrer CHAT_MSG_ADDON (guilde locale)
    local msgFrame = CreateFrame("Frame", "TradeScannerNetworkFrame")
    msgFrame:RegisterEvent("CHAT_MSG_ADDON")
    msgFrame:SetScript("OnEvent", function(self, event, prefix, message, distribution, sender)
        if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
            local playerShort = GetPlayerShort(sender)
            local myName = UnitName("player") or "?"

            -- Exclure ses propres messages (échos)
            if playerShort ~= myName then
                NET:HandleMessage(sender, message)
            end
        end
    end)

    -- GreenWall (confédération) : l'API n'est pas forcément prête au login,
    -- on réessaie l'enregistrement jusqu'à ce qu'elle réponde.
    self:RegisterGreenWall()

    -- HELLO initial (HELLO_DELAY = 5s après login)
    C_Timer.After(HELLO_DELAY, function()
        NET:BroadcastHello()
    end)
end

-- Enregistre les deux greffes GreenWall dès que disponibles (retry ~1 min) :
--   (1) le CHAT des co-guildes — pour PARSER les offres WTS/WTB des guildes sœurs ;
--   (2) le PROTOCOLE addon (OF/DN/…) via GreenWallAPI.
function NET:RegisterGreenWall(attempt)
    attempt = attempt or 1
    self:_HookGreenWallChat()
    self:_RegisterGreenWallProtocol()
    -- Réessayer tant que l'un des deux n'est pas en place.
    if (not self.gwRegistered or not self.gwChatHooked) and attempt < 12 then
        C_Timer.After(5, function() NET:RegisterGreenWall(attempt + 1) end)
    end
end

-- (1) GreenWall n'émet PAS d'event CHAT_MSG_GUILD pour le chat des co-guildes : il
-- l'affiche directement via gw.ReplicateMessage('GUILD', msg, guild_id, arglist) (cf.
-- GreenWall/Chat.lua). Le handler /g de TradeScanner ne les voit donc jamais ; le brut
-- "C#<id>#…" n'arrive que sur le canal-pont → jeté en skip_chan. On hook ReplicateMessage
-- pour parser ces offres comme du chat de guilde. arglist[2] = auteur d'origine.
function NET:_HookGreenWallChat()
    if self.gwChatHooked then return end
    local gwt = _G.gw
    if type(gwt) ~= "table" or type(gwt.ReplicateMessage) ~= "function" then return end
    self.gwChatHooked = true
    hooksecurefunc(gwt, "ReplicateMessage", function(event, message, guild_id, arglist)
        if event ~= "GUILD" then return end
        if not (TS.db and TS.db.scanGuild) then return end
        local sender = arglist and arglist[2]
        if not sender or not message or message == "" then return end
        local playerShort = sender:match("^([^%-]+)") or sender
        -- Défensif : retire un éventuel tag GreenWall "<id> " en tête (normalement absent
        -- ici, le tag étant ajouté APRÈS l'argument que reçoit le hook).
        local clean = message:gsub("^<[^>]+>%s*", "")
        if TS.db and TS.db.gwDebug then
            print(string.format("|cFF00CCFF[GW chat]|r <%s> %s: %s",
                tostring(guild_id), playerShort, tostring(clean)))
        end
        local ok, err = pcall(function() TS:ParseMessage(clean, playerShort, "guild", "guild") end)
        if not ok and TS.db and TS.db.gwDebug then
            print("|cFFFF4444TS gw chat parse error:|r " .. tostring(err))
        end
    end)
    if TS.db and TS.db.gwDebug then print("|cFF00CCFF[GW]|r co-guild chat hook installed") end
end

-- (2) Handler du protocole addon. Reçoit (addon, sender, message, echo, guild) :
--   echo  = mon propre message (renvoyé par le bridge)
--   guild = vient de MA guilde (déjà reçu via le canal addon "GUILD")
-- → on n'agit que sur le trafic des guildes sœurs.
function NET:_RegisterGreenWallProtocol()
    if self.gwRegistered then return end
    if not (GreenWallAPI and type(GreenWallAPI.AddMessageHandler) == "function") then return end
    local ok = pcall(function()
        GreenWallAPI.AddMessageHandler(function(_, sender, message, echo, guild)
            if TS.db and TS.db.gwDebug then
                print(string.format("|cFF00CCFF[GW←]|r %s (echo=%s guild=%s) %s",
                    tostring(sender), tostring(echo), tostring(guild), tostring(message)))
            end
            if echo or guild then return end
            NET:HandleMessage(sender, message)
        end, PREFIX, 0)
    end)
    if ok then self.gwRegistered = true end
end
