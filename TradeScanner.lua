-- TradeScanner - Guild Economy: trade channel scanner with profession integration.
-- Usage: /ts  /tradescan

TradeScanner = {}
local TS = TradeScanner

-- ============================================================
-- CONSTANTS
-- ============================================================

local OFFER_EXPIRY = 1800  -- 30 minutes
local MAX_OFFERS   = 300

local DEFAULTS = {
    channel  = "freshtrade",
    keywords = {
        sell = { "WTS", "VDS", "S>", "VEND", "SELL", "LFW" },
        buy  = { "WTB", "ACH", "B>", "ACHAT", "BUY", "CHERCHE", "ISO", "WTT", "TROC" },
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

function TS:Init()
    if not TradeScannerDB then TradeScannerDB = {} end
    local db = TradeScannerDB

    if not db.channel      then db.channel       = DEFAULTS.channel end
    if not db.keywords     then db.keywords       = {} end
    if not db.keywords.sell then db.keywords.sell = {} end
    if not db.keywords.buy  then db.keywords.buy  = {} end

    -- Seed keyword lists that are still empty
    if #db.keywords.sell == 0 then
        for _, v in ipairs(DEFAULTS.keywords.sell) do table.insert(db.keywords.sell, v) end
    end
    if #db.keywords.buy == 0 then
        for _, v in ipairs(DEFAULTS.keywords.buy) do table.insert(db.keywords.buy, v) end
    end

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
