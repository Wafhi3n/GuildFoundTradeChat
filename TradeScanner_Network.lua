-- TradeScanner_Network.lua
-- Sync réseau inter-addon (guilde locale + GreenWall cross-serveur)
-- Protocoles: HI (hello), OF (offer), DN (done)

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
-- client refuse d'exécuter hors hardware event (→ ADDON_ACTION_BLOCKED). C'est
-- pourquoi seules les actions de commande (CO/CC/CA, déclenchées par un bouton)
-- passent par ici ; les syncs auto (HI/OF/PR) restent en guilde locale.
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

-- Ping de présence "qui est en ligne ?" — déclenché par un clic (onglet Orders).
-- Volontairement GUILDE-LOCALE : la réponse IM ne peut PAS traverser GreenWall
-- (émise depuis un handler réseau, hors hardware event). Un WHO confédéral ferait
-- donc répondre les 11 guildes sœurs dans LEUR propre canal, pour des IM que
-- l'émetteur ne reçoit jamais → amplification pure (cf. doc charge à l'échelle).
-- On garde WHO local comme HI. Throttlé pour éviter le spam.
function NET:BroadcastWho()
    local now = GetTime()
    if self.lastWho and (now - self.lastWho) < 5 then return end
    self.lastWho = now
    self:Send("WHO")
    -- BroadcastWho n'est appelé QUE sur clic (minimap, onglet, Refresh) = hardware
    -- event → on en profite pour pousser MES métiers en CROSS-GUILDE. Indispensable :
    -- les guildes sœurs ne reçoivent jamais nos réponses IM/PR automatiques (émises
    -- hors hardware event) donc sans cette poussée proactive elles ignorent nos métiers.
    self:BroadcastProfessions(nil, true)
end

-- Réponse de présence : "IM|prof1,prof2|version". Émise depuis un handler
-- réseau (réception de WHO) → guilde locale uniquement (pas de hardware event).
function NET:BroadcastPresence()
    local profs = (TS.Guild and TS.Guild.myProfessions) or {}
    self:Send("IM|" .. table.concat(profs, ",") .. "|" .. GetAddonVersion())
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
    local offers = TS:GetOffers(nil, false)  -- toutes offres non-expirées
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

-- ------------------------------------------------------------------
-- Guilde : métiers (PR) + commandes de craft (CO / CC / CA)
-- ------------------------------------------------------------------

-- Annonce mes métiers + version : "PR|prof1,prof2,...|version".
-- fromUser=true ⇒ appel dans la pile d'un hardware event ⇒ propagation cross-guilde
-- (GreenWall) en plus de la guilde locale. Voir BroadcastWho pour le déclencheur.
function NET:BroadcastProfessions(professions, fromUser)
    local list = professions or (TS.Guild and TS.Guild.myProfessions) or {}
    local payload = "PR|" .. table.concat(list, ",") .. "|" .. GetAddonVersion()
    self:Send(payload)
    if fromUser then self:SendConfederation(payload) end
end

-- Nouvelle commande : "CO|buyer|kind|id|qty|priceValue|priceText|profession|name"
--   kind = "I" (item, id=itemID) | "E" (enchant, id=spellID, name=libellé)
--   fromUser = déclenchée par un clic joueur → propageable cross-guilde (GreenWall).
function NET:BroadcastOrder(o, fromUser)
    if not o then return end
    local kind = o.enchantID and "E" or "I"
    local id   = o.enchantID or o.itemID
    if not id then return end
    local payload = string.format("CO|%s|%s|%d|%d|%d|%s|%s|%s",
        o.buyer or "",
        kind,
        id,
        o.qty or 1,
        o.priceValue or 0,
        (o.priceText or ""):gsub("|", ""),
        o.profession or "",
        (o.enchantName or ""):gsub("|", ""))
    self:Send(payload)
    if fromUser then self:SendConfederation(payload) end
end

-- Annulation : "CC|buyer|kind|id" (toujours déclenchée par un clic → cross-guilde)
function NET:BroadcastCancel(buyer, kind, id)
    if not buyer or not id then return end
    local payload = string.format("CC|%s|%s|%d", buyer, kind or "I", id)
    self:Send(payload)
    self:SendConfederation(payload)
end

-- Acceptation : "CA|crafter|buyer|kind|id" (clic → cross-guilde)
function NET:BroadcastAccept(crafter, buyer, kind, id)
    if not crafter or not buyer or not id then return end
    local payload = string.format("CA|%s|%s|%s|%d", crafter, buyer, kind or "I", id)
    self:Send(payload)
    self:SendConfederation(payload)
end

-- Validation/livraison : "CF|buyer|kind|id|delivered" → décrémente la quantité ;
-- retirée partout quand il ne reste rien. `delivered` = quantité livrée (>=1).
-- localOnly = true ⇒ pas de relais GreenWall (appel hors hardware event, ex. trade auto).
function NET:BroadcastFulfill(buyer, kind, id, delivered, localOnly)
    if not buyer or not id then return end
    local payload = string.format("CF|%s|%s|%d|%d", buyer, kind or "I", id, delivered or 0)
    self:Send(payload)
    if not localOnly then self:SendConfederation(payload) end
end

-- Envoie MES commandes actives staggered (réponse à HI).
-- On ne rebroadcast QUE les commandes dont je suis l'auteur (o.buyer == moi),
-- comme BroadcastOffer ignore déjà les offres source=="network" : sinon chaque
-- membre réémettrait toute la liste confédérale (jusqu'à MAX_OFFERS) à CHAQUE
-- login de la guilde → tempête O(k×liste). Chaque auteur porte sa resync ;
-- une commande dont l'auteur est hors-ligne resync à son prochain login.
function NET:SendAllOrdersDelayed()
    local me   = UnitName("player") or "?"
    local mine = {}
    for _, o in ipairs((TS.db and TS.db.craftOrders) or {}) do
        if o.buyer == me then mine[#mine + 1] = o end
    end
    local sent = 0
    C_Timer.NewTicker(OFFER_TICK, function(ticker)
        if sent >= #mine or sent >= MAX_OFFERS then
            ticker:Cancel()
            return
        end
        sent = sent + 1
        if TS.Net then TS.Net:BroadcastOrder(mine[sent]) end
    end, MAX_OFFERS)
end

-- Réponse à un HELLO reçu : resync de MES offres/commandes + annonce de mes métiers.
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
        NET:SendAllOrdersDelayed()
        if TS.Guild then
            if not TS.Guild.myProfessions then TS.Guild:DetectMyProfessions() end
            NET:BroadcastProfessions(TS.Guild.myProfessions)
        end
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
    local cat, prof
    if itemID then cat, prof = TS:GetProducible(itemID) end
    TS:AddOffer({
        offerType    = offerType, player = player, itemID = itemID,
        -- nil si l'objet n'est pas encore en cache (résolu à l'affichage) ; l'appel
        -- GetItemInfo déclenche aussi le chargement asynchrone. (hotfix 1.5.2)
        itemName     = (GetItemInfo(itemID)),
        itemLink     = nil, priceText = (priceText ~= "" and priceText) or nil,
        priceValue   = priceValue, rawMsg = nil, timestamp = timestamp,
        canCraft     = cat ~= nil, sellCategory = cat, profession = prof,
        source       = "network",
    })
end

function NET:_HandleDN(message)
    -- Match ancré : "DN|player|itemID" (l'ancien split prenait "DN" comme player).
    local player, itemID = message:match("^DN|([^|]+)|(%d+)")
    if player and itemID then TS:MarkDone(player, tonumber(itemID), true) end
end

function NET:_HandleCO(message)
    local buyer, kind, id, qty, pv, ptext, prof, name =
        message:match("^CO|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    id = tonumber(id)
    if not (TS.Guild and buyer and id) then return end
    local o = {
        buyer      = buyer, qty = tonumber(qty) or 1,
        priceValue = tonumber(pv) or 0,
        priceText  = (ptext ~= "" and ptext) or nil,
        profession = (prof  ~= "" and prof)  or nil,
        status     = "open", timestamp = time(),
    }
    if kind == "E" then
        o.enchantID = id; o.enchantName = (name ~= "" and name) or nil
    else
        o.itemID = id
    end
    TS.Guild:AddOrder(o, true)
end

function NET:_HandleCF(message)
    local buyer, kind, id, delivered = message:match("^CF|([^|]+)|([^|]+)|(%d+)|?(%d*)")
    if TS.Guild and buyer and id then
        delivered = tonumber(delivered)  -- nil/0 = livraison complète (compat)
        if delivered == 0 then delivered = nil end
        TS.Guild:FulfillOrder(buyer, (kind == "E" and "e" or "i") .. id, delivered, true)
    end
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
        -- Ping de présence : je réponds qui je suis (métiers + version).
        self:BroadcastPresence()

    elseif cmd == "IM" then
        -- "IM|prof1,prof2|version" — réponse de présence d'un membre.
        if TS.Guild then
            local body, ver = message:match("^IM|([^|]*)|?(.*)$")
            local profs = {}
            for p in (body or ""):gmatch("([^,]+)") do profs[#profs + 1] = p end
            TS.Guild:UpdateRoster(playerShort, profs, ver ~= "" and ver or nil)
        end

    elseif cmd == "OF" then self:_HandleOF(message)
    elseif cmd == "DN" then self:_HandleDN(message)

    elseif cmd == "PR" then
        if TS.Guild then
            -- "PR|profs|version" (version optionnelle : compat anciens clients "PR|profs").
            local body, ver = message:match("^PR|([^|]*)|?(.*)$")
            local profs = {}
            for p in (body or ""):gmatch("([^,]+)") do profs[#profs + 1] = p end
            TS.Guild:UpdateRoster(playerShort, profs, ver ~= "" and ver or nil)
        end

    elseif cmd == "CO" then self:_HandleCO(message)

    elseif cmd == "CC" then
        local buyer, kind, id = message:match("^CC|([^|]+)|([^|]+)|(%d+)")
        if TS.Guild and buyer and id then
            TS.Guild:CancelOrder(buyer, (kind == "E" and "e" or "i") .. id, true)
        end

    elseif cmd == "CA" then
        local crafter, buyer, kind, id = message:match("^CA|([^|]+)|([^|]+)|([^|]+)|(%d+)")
        if TS.Guild and crafter and buyer and id then
            TS.Guild:AcceptOrder(buyer, (kind == "E" and "e" or "i") .. id, true, crafter)
        end

    elseif cmd == "CF" then self:_HandleCF(message)
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

-- Enregistre le handler GreenWall dès que l'API est disponible.
-- Le handler reçoit (addon, sender, message, echo, guild) :
--   echo  = mon propre message (renvoyé par le bridge)
--   guild = vient de MA guilde (déjà reçu via le canal addon "GUILD")
-- → on n'agit que sur le trafic des guildes sœurs.
function NET:RegisterGreenWall(attempt)
    attempt = attempt or 1
    if self.gwRegistered then return end

    if GreenWallAPI and type(GreenWallAPI.AddMessageHandler) == "function" then
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
        if ok then
            self.gwRegistered = true
            return
        end
    end

    if attempt < 12 then  -- ~1 min de tentatives (5s × 12)
        C_Timer.After(5, function() NET:RegisterGreenWall(attempt + 1) end)
    end
end
