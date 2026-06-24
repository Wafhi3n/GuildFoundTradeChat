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

-- ============================================================
-- ENVOI
-- ============================================================

function NET:Send(payload)
    if not payload or payload == "" then return end

    -- Guilde locale (API standard WoW)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    end

    -- GreenWall (cross-serveur) — désactivé pour l'instant (timing issues)
    -- if GreenWallAPI and type(GreenWallAPI.SendMessage) == "function" then
    --     local ok = pcall(function()
    --         GreenWallAPI.SendMessage(PREFIX, payload)
    --     end)
    -- end
end

-- Envoie un HELLO (invite les autres à envoyer leurs offres)
function NET:BroadcastHello()
    self:Send("HI")
end

-- Envoie une offre unique
function NET:BroadcastOffer(offer)
    if not offer or offer.source == "network" then return end
    local payload = string.format("OF|%s|%s|%s|%d|%s|%d",
        offer.player or "",
        offer.offerType or "",
        offer.itemID or "0",
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

-- Annonce mes métiers : "PR|prof1,prof2,..."
function NET:BroadcastProfessions(professions)
    local list = professions or {}
    self:Send("PR|" .. table.concat(list, ","))
end

-- Nouvelle commande : "CO|buyer|kind|id|qty|priceValue|priceText|profession|name"
--   kind = "I" (item, id=itemID) | "E" (enchant, id=spellID, name=libellé)
function NET:BroadcastOrder(o)
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
end

-- Annulation : "CC|buyer|kind|id"
function NET:BroadcastCancel(buyer, kind, id)
    if not buyer or not id then return end
    self:Send(string.format("CC|%s|%s|%d", buyer, kind or "I", id))
end

-- Acceptation : "CA|crafter|buyer|kind|id"
function NET:BroadcastAccept(crafter, buyer, kind, id)
    if not crafter or not buyer or not id then return end
    self:Send(string.format("CA|%s|%s|%s|%d", crafter, buyer, kind or "I", id))
end

-- Envoie toutes les commandes actives staggered (réponse à HI)
function NET:SendAllOrdersDelayed()
    local orders = (TS.db and TS.db.craftOrders) or {}
    local sent = 0
    C_Timer.NewTicker(OFFER_TICK, function(ticker)
        if sent >= #orders or sent >= MAX_OFFERS then
            ticker:Cancel()
            return
        end
        sent = sent + 1
        if TS.Net then TS.Net:BroadcastOrder(orders[sent]) end
    end, MAX_OFFERS)
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
    local parts = {}
    for part in message:gmatch("([^|]+)") do table.insert(parts, part) end
    if #parts < 6 then return end
    local player     = parts[1]
    local offerType  = parts[2]
    local itemID     = tonumber(parts[3])
    local priceValue = tonumber(parts[4]) or 0
    local priceText  = parts[5]
    local timestamp  = tonumber(parts[6]) or time()
    local cat, prof
    if itemID then cat, prof = TS:GetProducible(itemID) end
    TS:AddOffer({
        offerType    = offerType, player = player, itemID = itemID,
        itemName     = itemID and TS:GetItemName(itemID) or nil,
        itemLink     = nil, priceText = (priceText ~= "" and priceText) or nil,
        priceValue   = priceValue, rawMsg = nil, timestamp = timestamp,
        canCraft     = cat ~= nil, sellCategory = cat, profession = prof,
        source       = "network",
    })
end

function NET:_HandleDN(message)
    local parts = {}
    for part in message:gmatch("([^|]+)") do table.insert(parts, part) end
    if #parts >= 2 then
        local itemID = tonumber(parts[2])
        if itemID then TS:MarkDone(parts[1], itemID, true) end
    end
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

function NET:HandleMessage(senderName, message)
    if not message or message == "" then return end
    local playerShort = GetPlayerShort(senderName)
    local cmd = message:match("^([A-Z]+)")

    if cmd == "HI" then
        self:SendAllOffersDelayed()
        self:SendAllOrdersDelayed()
        if TS.Guild then
            if not TS.Guild.myProfessions then TS.Guild:DetectMyProfessions() end
            self:BroadcastProfessions(TS.Guild.myProfessions)
        end

    elseif cmd == "OF" then self:_HandleOF(message)
    elseif cmd == "DN" then self:_HandleDN(message)

    elseif cmd == "PR" then
        if TS.Guild then
            local body = message:match("^PR|(.*)$") or ""
            local profs = {}
            for p in body:gmatch("([^,]+)") do profs[#profs + 1] = p end
            TS.Guild:UpdateRoster(playerShort, profs)
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
    end
end

-- ============================================================
-- INIT & EVENTS
-- ============================================================

function NET:Init()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then
        return  -- trop vieux ou pas dispo
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

    -- GreenWallAPI (cross-serveur) — désactivé pour l'instant (timing issues au login)
    -- À réactiver plus tard avec meilleur timing
    -- if GreenWallAPI and type(GreenWallAPI.AddMessageHandler) == "function" then
    --     pcall(function()
    --         GreenWallAPI.AddMessageHandler(..., PREFIX, 0)
    --     end)
    -- end

    -- HELLO initial (2s après login)
    C_Timer.After(HELLO_DELAY, function()
        NET:BroadcastHello()
    end)
end
