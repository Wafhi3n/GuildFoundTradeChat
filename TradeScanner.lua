-- TradeScanner - Guild Economy: trade channel scanner with profession integration.
-- Usage: /ts  /tradescan

TradeScanner = {}
local TS = TradeScanner

-- ============================================================
-- CONSTANTS
-- ============================================================

local OFFER_EXPIRY = 1800  -- 30 minutes
local MAX_OFFERS   = 300
local ORDER_EXPIRY = 7 * 24 * 3600  -- 7 jours : purge des commandes de craft dormantes

local DEFAULTS = {
    channel  = "freshtrade",
    keywords = {
        sell = { "WTS", "VDS", "S>", "VEND", "SELL", "LFW" },
        buy  = { "WTB", "ACH", "B>", "ACHAT", "BUY", "CHERCHE", "ISO", "WTT", "TROC" },
        gift = { "WTG", "GIFT", "FREE", "GRATUIT", "DON" },
    },
}

-- Keywords added after initial release; re-injected into existing saved DBs on load.
local KEYWORD_MIGRATIONS = {
    sell = { "LFW" },
    buy  = { "WTT", "TROC" },
}

-- ============================================================
-- INIT & SAVEDVARIABLES
-- ============================================================

local function ApplyKeywordMigrations(db)
    for side, words in pairs(KEYWORD_MIGRATIONS) do
        local list = db.keywords[side]
        for _, kw in ipairs(words) do
            local present = false
            for _, existing in ipairs(list) do
                if existing == kw then present = true; break end
            end
            if not present then table.insert(list, kw) end
        end
    end
end

-- Crée les listes de mots-clés manquantes (sell/buy/gift) et y injecte les valeurs
-- par défaut tant qu'elles sont vides (anciennes DB → seed automatique des dons WTG).
local function SeedKeywords(db)
    if not db.keywords then db.keywords = {} end
    for side, defaults in pairs(DEFAULTS.keywords) do
        if not db.keywords[side] then db.keywords[side] = {} end
        if #db.keywords[side] == 0 then
            for _, v in ipairs(defaults) do table.insert(db.keywords[side], v) end
        end
    end
end

function TS:Init()
    if not TradeScannerDB then TradeScannerDB = {} end
    local db = TradeScannerDB

    if not db.channel      then db.channel       = DEFAULTS.channel end
    -- v1.5 : multi-canaux. db.channel = canal d'ENVOI par défaut (BagSell / composeur) ;
    -- db.channels = liste des canaux SURVEILLÉS au scan. Migration depuis l'unique canal.
    if not db.channels or #db.channels == 0 then db.channels = { db.channel } end
    SeedKeywords(db)  -- crée + seed sell/buy/gift au besoin

    if not db.offers        then db.offers        = {} end
    if not db.craftedItems  then db.craftedItems  = {} end
    if not db.craftedNames  then db.craftedNames  = {} end
    if not db.manualSellable then db.manualSellable = {} end
    if not db.excludedItems  then db.excludedItems  = {} end
    if not db.doneOffers     then db.doneOffers     = {} end
    if not db.guildRoster    then db.guildRoster    = {} end
    if not db.craftOrders    then db.craftOrders    = {} end
    if db.alertSound == nil  then db.alertSound     = true end
    if db.scanGuild  == nil  then db.scanGuild      = true end
    if db.debugLog   == nil  then db.debugLog       = false end
    if db.bagSellEnabled == nil then db.bagSellEnabled = true end
    if db.useGreenWall   == nil then db.useGreenWall   = true end

    self.db           = db
    self.craftedItems = db.craftedItems
    self.craftedNames = db.craftedNames

    if self.LoadStaticData then self:LoadStaticData() end

    -- Purge UNKNOWN entries from old Enchanting scan via wrong API
    for id, prof in pairs(self.craftedItems) do
        if prof == "UNKNOWN" then self.craftedItems[id] = nil end
    end
    for name, info in pairs(self.craftedNames) do
        if type(info) == "table" and info.profession == "UNKNOWN" then
            self.craftedNames[name] = nil
        end
    end

    ApplyKeywordMigrations(db)

    self:PurgeOldOrders()  -- vide les commandes de craft dormantes (cf. doc §8)

    if not db.errorLog then db.errorLog = {} end

    if not TradeScannerLog then TradeScannerLog = { entries = {} } end
    self.log = TradeScannerLog
end

-- ============================================================
-- OFFER DATABASE (storage utilities)
-- ============================================================

function TS:GetOffers(filterType, craftOnly)
    local now, result = time(), {}
    for _, offer in ipairs(self.db.offers) do
        if (now - offer.timestamp) <= OFFER_EXPIRY then
            local typeOk  = (filterType == nil or offer.offerType == filterType)
            local craftOk = (not craftOnly) or offer.canCraft
            local doneOk  = not (offer.itemID and self:IsDone(offer.player, offer.itemID))
            if typeOk and craftOk and doneOk then table.insert(result, offer) end
        end
    end
    return result
end

function TS:ClearExpired()
    local now = time()
    for i = #self.db.offers, 1, -1 do
        if now - self.db.offers[i].timestamp > OFFER_EXPIRY then
            table.remove(self.db.offers, i)
        end
    end
end

-- ============================================================
-- CANAUX SURVEILLÉS (multi-canaux, v1.5)
-- ============================================================

-- True si un nom de canal reçu (déjà nettoyé du préfixe "N. " et en minuscules)
-- correspond à l'un des canaux surveillés. Correspondance partielle tolérée comme
-- avant ("freshtrade" matche une entrée "freshtrade").
function TS:ChannelIsWatched(chanClean)
    if not chanClean then return false end
    chanClean = chanClean:lower()
    for _, c in ipairs(self.db.channels or {}) do
        if c ~= "" and chanClean:find(c:lower(), 1, true) then return true end
    end
    return false
end

-- Ajoute un canal à la liste surveillée (normalisé en minuscules, sans doublon).
function TS:AddWatchedChannel(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if name == "" then return false end
    self.db.channels = self.db.channels or {}
    for _, c in ipairs(self.db.channels) do
        if c == name then return false end
    end
    table.insert(self.db.channels, name)
    return true
end

-- Retire un canal de la liste surveillée.
function TS:RemoveWatchedChannel(name)
    name = (name or ""):lower()
    local list = self.db.channels or {}
    for i = #list, 1, -1 do
        if list[i] == name then table.remove(list, i); return true end
    end
    return false
end

-- Libellé compact des canaux surveillés (pour la barre de statut / labels).
function TS:ChannelsLabel()
    local list = self.db.channels or {}
    if #list == 0 then return "?" end
    return table.concat(list, ", ")
end

-- ============================================================
-- VERSION (alerte de mise à jour, v1.5)
-- ============================================================

function TS:GetVersion()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    return (f and f("TradeScanner", "Version")) or "?"
end

-- Compare deux versions "x.y.z". Retourne 1 si a>b, -1 si a<b, 0 si égales.
function TS:CompareVersion(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- Si une version reçue (roster réseau) est plus récente que la mienne, alerte UNE
-- seule fois par session que l'utilisateur doit se mettre à jour.
function TS:NotifyIfNewerVersion(otherVersion)
    if self._versionAlerted then return end
    if not otherVersion or otherVersion == "" or otherVersion == "?" then return end
    local mine = self:GetVersion()
    if mine == "?" then return end
    if self:CompareVersion(otherVersion, mine) > 0 then
        self._versionAlerted = true
        print("|cFF00CCFFGuild Economy|r " .. string.format(
            self.L["A newer version (%s) is available — you have %s."], otherVersion, mine))
        if self.db and self.db.alertSound then PlaySound(1191) end
    end
end

-- Refresh d'UI coalescé : regroupe les rafales réseau (resync HI, login storm,
-- bursts CO/OF) en UN seul rebuild après un court délai, au lieu d'un rebuild par
-- message reçu. Indispensable à l'échelle (guildes de 1000 → pics de logins).
--   • La fenêtre d'offres n'est rebuild que si VISIBLE — UI:Refresh ne teste pas
--     IsShown lui-même, donc sans ce garde elle se reconstruit fenêtre fermée.
--   • Les panneaux guilde (OrderPanel/ProfPanel) s'auto-gardent déjà par IsShown.
local refreshPending = false
function TS:RequestRefresh()
    local function doRefresh()
        refreshPending = false
        if TS.UI and TS.UI.Refresh and TS.UI.frame and TS.UI.frame:IsShown() then
            TS.UI:Refresh()
        end
        if TS.Guild and TS.Guild.Refresh then TS.Guild:Refresh() end
    end
    if not (C_Timer and C_Timer.After) then return doRefresh() end
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, doRefresh)
end

-- Purge les commandes de craft dormantes (auteur parti / jamais livrées). Sans ça,
-- db.craftOrders ne se vide jamais (contrairement aux offres, OFFER_EXPIRY) et la
-- liste tend vers le plafond MAX_OFFERS → resync HI maximale en permanence (doc §8).
-- La livraison CF en retire déjà, ceci rattrape les commandes abandonnées.
function TS:PurgeOldOrders()
    local orders = self.db and self.db.craftOrders
    if not orders then return end
    local now = time()
    for i = #orders, 1, -1 do
        if now - (orders[i].timestamp or 0) > ORDER_EXPIRY then
            table.remove(orders, i)
        end
    end
end

-- ============================================================
-- PROFESSION INTEGRATION
-- ============================================================

-- Localised item name via WoW API. Falls back to label or "item:ID".
function TS:GetItemName(itemID, fallback)
    if not itemID then return fallback end
    local name = GetItemInfo(itemID)
    return name or fallback or ("item:" .. itemID)
end

-- Returns category, profession for an item the player can supply.
--   "manual"     = manually added via dropdown
--   "scan"       = recipe indexed from open profession window
--   "sellable"   = listed in a static profession DB
--   "disenchant" = disenchant mat listed in static DB
-- Returns nil if unknown or explicitly excluded.
function TS:GetProducible(itemID)
    if not itemID then return nil end
    if self.db and self.db.excludedItems and self.db.excludedItems[itemID] then return nil end
    if self.db and self.db.manualSellable and self.db.manualSellable[itemID] then
        return "manual", "Manuel"
    end
    local scanned = self.craftedItems[itemID]
    if scanned then return "scan", scanned end
    local s = self.staticItems and self.staticItems[itemID]
    if s then return s.category, s.profession end
    return nil
end

function TS:CanSell(itemID)
    return (self:GetProducible(itemID)) ~= nil
end

-- Toggles exclusion of an item from scan results (ProfPanel filter button).
function TS:ToggleExcluded(itemID)
    if not itemID then return end
    self.db.excludedItems = self.db.excludedItems or {}
    if self.db.excludedItems[itemID] then
        self.db.excludedItems[itemID] = nil
    else
        self.db.excludedItems[itemID] = true
    end
    self:RefreshCraftStatus()
    return self.db.excludedItems[itemID] == true
end

function TS:AddManualSellable(itemID, name)
    if not itemID then return end
    self.db.manualSellable = self.db.manualSellable or {}
    self.db.manualSellable[itemID] = name or self:GetItemName(itemID)
    self:RefreshCraftStatus()
end

function TS:RemoveManualSellable(itemID)
    if not itemID or not self.db.manualSellable then return end
    self.db.manualSellable[itemID] = nil
    self:RefreshCraftStatus()
end

-- ============================================================
-- EVENTS
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:RegisterEvent("CRAFT_SHOW")
eventFrame:RegisterEvent("CRAFT_UPDATE")
eventFrame:RegisterEvent("CRAFT_CLOSE")

-- Debounced profession scan: avoids stacking C_Timer.After on UPDATE bursts.
local scanPending = false
local function HandleProfessionShow()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.3, function()
        scanPending = false
        local ok, err = pcall(function() TS:ScanOpenProfession() end)
        if not ok then print("|cFFFF4444TS scan error:|r " .. tostring(err)) end
        if TS.ProfPanel then
            local ok2, err2 = pcall(function() TS.ProfPanel:OnTradeSkillShow() end)
            if not ok2 then print("|cFFFF4444TS panel error:|r " .. tostring(err2)) end
        end
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == "TradeScanner" then TS:Init() end

    elseif event == "PLAYER_LOGIN" then
        SLASH_TRADESCANNER1 = "/ts"
        SLASH_TRADESCANNER2 = "/tradescan"
        SlashCmdList["TRADESCANNER"] = function(msg) TS:HandleSlash(msg) end
        if TS.Minimap then TS.Minimap:Init() end
        if TS.Net     then TS.Net:Init()     end
        if TS.Guild   then TS.Guild:Init()   end
        if TS.Trade   then TS.Trade:Init()   end
        if TS.BagSell then TS.BagSell:Init() end
        local _origErr = geterrorhandler and geterrorhandler()
        seterrorhandler(function(err)
            local db = TS.db
            if db and type(err) == "string" and err:find("TradeScanner") then
                local t = date and date("%H:%M:%S") or "?"
                table.insert(db.errorLog, 1, { e = err:sub(1, 220), t = t })
                if #db.errorLog > 30 then table.remove(db.errorLog) end
            end
            if _origErr then return _origErr(err) end
        end)
        local cached = 0
        for _ in pairs(TS.craftedItems or {}) do cached = cached + 1 end
        local msg = "|cFF00CCFFGuild Economy|r loaded — /ts to open"
        if cached > 0 then msg = msg .. string.format(" (%d recipes cached)", cached) end
        print(msg)

    elseif event == "CHAT_MSG_CHANNEL" then
        local msg, player, _, channelName = ...
        if msg and player and channelName then
            local playerShort = player:match("^([^%-]+)") or player
            TS:ParseMessage(msg, playerShort, channelName, "channel")
        end

    elseif event == "CHAT_MSG_GUILD" then
        if not TS.db or not TS.db.scanGuild then return end
        local msg, player = ...
        if msg and player then
            local playerShort = player:match("^([^%-]+)") or player
            TS:ParseMessage(msg, playerShort, "guild", "guild")
        end

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        HandleProfessionShow()

    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        if TS.ProfPanel then TS.ProfPanel:OnTradeSkillClose() end
    end
end)
