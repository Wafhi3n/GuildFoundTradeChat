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

-- ============================================================
-- RÉCEPTION
-- ============================================================

-- Extrait le nom court du joueur (sans realm)
local function GetPlayerShort(fullName)
    if not fullName then return nil end
    return fullName:match("^([^%-]+)") or fullName
end

-- Parse et traite un message reçu (HI / OF / DN)
function NET:HandleMessage(senderName, message)
    if not message or message == "" then return end

    local playerShort = GetPlayerShort(senderName)
    local cmd = message:match("^([A-Z]+)")

    if cmd == "HI" then
        -- Quelqu'un se co : envoyer nos offres
        self:SendAllOffersDelayed()

    elseif cmd == "OF" then
        -- Nouvelle offre reçue
        local parts = {}
        for part in message:gmatch("([^|]+)") do
            table.insert(parts, part)
        end
        if #parts >= 6 then
            local offerType  = parts[2]
            local itemID     = tonumber(parts[3])
            local priceValue = tonumber(parts[4]) or 0
            local priceText  = parts[5]
            local timestamp  = tonumber(parts[6]) or time()
            local player     = parts[1]

            -- Construire l'offre
            local offer = {
                offerType    = offerType,
                player       = player,
                itemID       = itemID,
                itemName     = itemID and TS:GetItemName(itemID) or nil,
                itemLink     = nil,  -- pas de lien dans le payload
                priceText    = (priceText ~= "" and priceText) or nil,
                priceValue   = priceValue,
                rawMsg       = nil,  -- reconstruction pas possible
                timestamp    = timestamp,
                canCraft     = itemID and TS:CanSell(itemID) or false,
                sellCategory = itemID and select(1, TS:GetProducible(itemID)) or nil,
                profession   = itemID and select(2, TS:GetProducible(itemID)) or nil,
                source       = "network",
            }

            TS:AddOffer(offer)
        end

    elseif cmd == "DN" then
        -- Offre marquée comme traitée
        local parts = {}
        for part in message:gmatch("([^|]+)") do
            table.insert(parts, part)
        end
        if #parts >= 2 then
            local player = parts[1]
            local itemID = tonumber(parts[2])
            if itemID then
                TS:MarkDone(player, itemID, true)
            end
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
