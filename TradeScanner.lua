-- TradeScanner - Scanner de canal de commerce avec intégration métiers
-- Usage: /ts  /tradescan

TradeScanner = {}
local TS = TradeScanner

-- ============================================================
-- CONSTANTES
-- ============================================================

local OFFER_EXPIRY  = 1800  -- 30 minutes
local MAX_OFFERS    = 300

local DEFAULTS = {
    channel  = "freshtrade",
    keywords = {
        sell = { "WTS", "VDS", "S>", "VEND", "SELL" },
        buy  = { "WTB", "ACH", "B>", "ACHAT", "BUY", "CHERCHE", "ISO" },
    },
}

-- ============================================================
-- INIT & SAVEDVARIABLES
-- ============================================================

function TS:Init()
    if not TradeScannerDB then TradeScannerDB = {} end
    local db = TradeScannerDB

    if not db.channel      then db.channel      = DEFAULTS.channel end
    if not db.keywords      then db.keywords      = {} end
    if not db.keywords.sell then db.keywords.sell = { unpack(DEFAULTS.keywords.sell) } end
    if not db.keywords.buy  then db.keywords.buy  = { unpack(DEFAULTS.keywords.buy)  } end
    if not db.offers        then db.offers        = {} end
    if not db.craftedItems  then db.craftedItems  = {} end
    if not db.craftedNames  then db.craftedNames  = {} end
    if db.scanGuild == nil  then db.scanGuild     = true end
    if db.alertSound == nil then db.alertSound    = true end
    if db.debugLog == nil   then db.debugLog      = false end

    self.db           = db
    self.craftedItems = db.craftedItems
    self.craftedNames = db.craftedNames

    -- Log séparé dans TradeScannerLog (son propre fichier SavedVariables)
    if not TradeScannerLog then TradeScannerLog = { entries = {} } end
    self.log = TradeScannerLog
end

-- ============================================================
-- PARSING DU CHAT
-- ============================================================

local function StripChannelNumber(channelName)
    -- "4. freshtrade" -> "freshtrade"
    return channelName:gsub("^%d+%.%s*", ""):lower()
end

local function DetectOfferType(msg, keywords)
    local upper = msg:upper()
    for _, kw in ipairs(keywords.sell) do
        if upper:find(kw, 1, true) then return "sell" end
    end
    for _, kw in ipairs(keywords.buy) do
        if upper:find(kw, 1, true) then return "buy" end
    end
    return nil
end

local function ExtractItemLinks(msg)
    local items = {}
    -- Format WoW: |Hitem:ITEMID:enchant:gem...|h[Nom Item]|h
    for itemKey, itemName in msg:gmatch("|H(item:%d+[^|]*)|h%[([^%]]+)%]|h") do
        local itemID = tonumber(itemKey:match("item:(%d+)"))
        if itemID then
            table.insert(items, {
                itemID = itemID,
                name   = itemName,
                link   = "|H" .. itemKey .. "|h[" .. itemName .. "]|h",
            })
        end
    end
    return items
end

local function ExtractPrice(msg)
    local g, s, c

    -- Xg Ys Zc (entiers combinés)
    g, s, c = msg:match("(%d+)%s*[gG]%s*(%d+)%s*[sS]%s*(%d+)%s*[cC]")
    if g then
        return string.format("%sg %ss %sc", g, s, c),
               tonumber(g) * 10000 + tonumber(s) * 100 + tonumber(c)
    end

    -- Xg Ys (entiers combinés)
    g, s = msg:match("(%d+)%s*[gG]%s*(%d+)%s*[sS]")
    if g then
        return string.format("%sg %ss", g, s),
               tonumber(g) * 10000 + tonumber(s) * 100
    end

    -- Or décimal : "1.5g" "1,5g" "1.50g" "1.50 g" (. ou , comme séparateur)
    local dg = msg:match("(%d+[%.,]%d+)%s*[gG]")
    if dg then
        local norm = dg:gsub(",", ".")
        local val  = math.floor(tonumber(norm) * 10000)
        return norm .. "g", val
    end

    -- Or entier : "5g"
    g = msg:match("(%d+)%s*[gG]")
    if g then
        return string.format("%sg", g), tonumber(g) * 10000
    end

    -- Argent décimal : "1.5s" "1,5s"
    local ds = msg:match("(%d+[%.,]%d+)%s*[sS]")
    if ds then
        local norm = ds:gsub(",", ".")
        local val  = math.floor(tonumber(norm) * 100)
        return norm .. "s", val
    end

    -- Argent entier : "30s"
    s = msg:match("(%d+)%s*[sS]")
    if s then
        return string.format("%ss", s), tonumber(s) * 100
    end

    return nil, 0
end

-- ============================================================
-- LOG DES MESSAGES
-- ============================================================

local LOG_MAX = 300

function TS:LogRaw(player, channelName, msg, result)
    local entry = {
        ts  = time(),
        p   = player,
        ch  = channelName,
        m   = msg,
        r   = result,  -- "sell"|"buy"|"skip_chan"|"skip_kw"
    }
    local entries = self.log and self.log.entries
    if entries then
        table.insert(entries, 1, entry)
        if #entries > LOG_MAX then table.remove(entries) end
    end

    if self.db.debugLog then
        local col = result == "sell" and "|cFF33DD33"
               or  result == "buy"  and "|cFF33AAFF"
               or  "|cFF888888"
        print(string.format("|cFF00CCFFTS|r %s[%s]|r %s: %s", col, result, player, msg:sub(1,80)))
    end
end

-- source : "channel" | "guild"
function TS:ParseMessage(msg, player, channelName, source)
    source = source or "channel"

    -- Pour le canal: filtrer par nom de canal configuré
    if source == "channel" then
        local chanClean = StripChannelNumber(channelName)
        if not chanClean:find(self.db.channel:lower(), 1, true) then
            self:LogRaw(player, channelName, msg, "skip_chan")
            return
        end
    end
    -- Pour /g (guild + GreenWall): pas de filtre de canal

    local offerType = DetectOfferType(msg, self.db.keywords)
    if not offerType then
        self:LogRaw(player, channelName, msg, "skip_kw")
        return
    end

    self:LogRaw(player, channelName, msg, offerType)

    local items      = ExtractItemLinks(msg)
    local priceText, priceValue = ExtractPrice(msg)

    if #items == 0 then
        self:AddOffer({
            offerType  = offerType,
            player     = player,
            itemID     = nil,
            itemName   = nil,
            itemLink   = nil,
            priceText  = priceText,
            priceValue = priceValue,
            rawMsg     = msg,
            timestamp  = time(),
            canCraft   = false,
            profession = nil,
            source     = source,
        })
    else
        for _, item in ipairs(items) do
            local canCraft = self:CanCraft(item.itemID)
            self:AddOffer({
                offerType  = offerType,
                player     = player,
                itemID     = item.itemID,
                itemName   = item.name,
                itemLink   = item.link,
                priceText  = priceText,
                priceValue = priceValue,
                rawMsg     = msg,
                timestamp  = time(),
                canCraft   = canCraft,
                profession = canCraft and self:GetCraftProfession(item.itemID) or nil,
                source     = source,
            })
        end
    end
end

-- ============================================================
-- BASE D'OFFRES
-- ============================================================

function TS:AddOffer(offer)
    local db  = self.db

    -- Déduplication: même joueur + même item (sans limite de temps)
    -- On met à jour l'entrée existante et on la remonte en tête
    if offer.itemID then
        for i, existing in ipairs(db.offers) do
            if existing.player == offer.player
               and existing.itemID == offer.itemID then
                existing.timestamp  = offer.timestamp
                existing.priceText  = offer.priceText
                existing.priceValue = offer.priceValue
                existing.canCraft   = offer.canCraft
                existing.profession = offer.profession
                existing.source     = offer.source
                -- Remonter en tête de liste
                table.remove(db.offers, i)
                table.insert(db.offers, 1, existing)
                if self.UI then self.UI:Refresh() end
                return
            end
        end
    else
        -- Sans item link: dédupliquer par joueur + message brut
        for i, existing in ipairs(db.offers) do
            if existing.player == offer.player
               and existing.rawMsg == offer.rawMsg then
                existing.timestamp = offer.timestamp
                table.remove(db.offers, i)
                table.insert(db.offers, 1, existing)
                if self.UI then self.UI:Refresh() end
                return
            end
        end
    end

    table.insert(db.offers, 1, offer)

    if #db.offers > MAX_OFFERS then
        table.remove(db.offers)
    end

    -- Alerte si WTB et qu'on peut crafter
    if offer.offerType == "buy" and offer.canCraft then
        self:AlertCraftable(offer)
    end

    if self.UI then self.UI:Refresh() end
end

function TS:GetOffers(filterType, craftOnly)
    local now    = time()
    local result = {}
    for _, offer in ipairs(self.db.offers) do
        if (now - offer.timestamp) <= OFFER_EXPIRY then
            local typeOk  = (filterType == nil or offer.offerType == filterType)
            local craftOk = (not craftOnly) or offer.canCraft
            if typeOk and craftOk then
                table.insert(result, offer)
            end
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
-- INTÉGRATION MÉTIERS
-- ============================================================

function TS:CanCraft(itemID)
    if not itemID then return false end
    return self.craftedItems[itemID] ~= nil
end

function TS:GetCraftProfession(itemID)
    return self.craftedItems[itemID]
end

function TS:ScanCurrentTradeSkill()
    if not GetTradeSkillLine then return 0, nil end
    local skillName = GetTradeSkillLine()
    if not skillName or skillName == "" then return 0, nil end

    local num   = GetNumTradeSkills and GetNumTradeSkills() or 0
    local count = 0

    for i = 1, num do
        local recipeName, skillType = GetTradeSkillInfo(i)
        -- Ignorer les headers de catégorie
        if recipeName and skillType ~= "header" and skillType ~= "subheader" then
            local link = GetTradeSkillItemLink(i)
            if link then
                local itemID = tonumber(link:match("|Hitem:(%d+)"))
                if itemID then
                    self.craftedItems[itemID] = skillName
                    local itemName = link:match("|h%[(.-)%]|h")
                    if itemName then
                        self.craftedNames[itemName:lower()] = {
                            itemID     = itemID,
                            profession = skillName,
                        }
                    end
                    count = count + 1
                end
            end
        end
    end

    -- Mettre à jour le statut canCraft sur les offres existantes
    if count > 0 then
        self:RefreshCraftStatus()
    end

    return count, skillName
end

function TS:RefreshCraftStatus()
    for _, offer in ipairs(self.db.offers) do
        if offer.itemID then
            offer.canCraft   = self:CanCraft(offer.itemID)
            offer.profession = offer.canCraft and self:GetCraftProfession(offer.itemID) or nil
        end
    end
    if self.UI then self.UI:Refresh() end
end

function TS:GetCraftedProfessions()
    -- Retourne un résumé: { profName = count }
    local profs = {}
    for _, profName in pairs(self.craftedItems) do
        profs[profName] = (profs[profName] or 0) + 1
    end
    return profs
end

-- ============================================================
-- ALERTES CRAFT
-- ============================================================

function TS:AlertCraftable(offer)
    local itemStr = offer.itemLink or offer.itemName or "?"
    local prof    = offer.profession or "?"
    print(string.format(
        "|cFF00CCFFTradeScanner|r |cFFFFCC00>> CRAFT|r [%s] %s cherche %s  — |cFFFFFFFF/w %s|r",
        prof, offer.player, itemStr, offer.player
    ))
    if self.db.alertSound then
        PlaySound(1191)  -- cloche Ready Check
    end
    if self.Minimap then
        self.Minimap:SetAlert(true)
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")       -- guild + GreenWall
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == "TradeScanner" then
            TS:Init()
        end

    elseif event == "PLAYER_LOGIN" then
        SLASH_TRADESCANNER1 = "/ts"
        SLASH_TRADESCANNER2 = "/tradescan"
        SlashCmdList["TRADESCANNER"] = function(msg)
            TS:HandleSlash(msg)
        end
        -- Bouton minimap
        if TS.Minimap then TS.Minimap:Init() end
        -- Compter les recettes déjà en cache
        local cached = 0
        for _ in pairs(TS.craftedItems or {}) do cached = cached + 1 end
        local msg = "|cFF00CCFFTradeScanner|r loaded — /ts to open"
        if cached > 0 then
            msg = msg .. string.format(" (%d recipes cached)", cached)
        end
        print(msg)

    elseif event == "CHAT_MSG_CHANNEL" then
        -- arg1=message, arg2=playerName, arg3=language, arg4=channelName
        local msg, player, _, channelName = ...
        if msg and player and channelName then
            local playerShort = player:match("^([^%-]+)") or player
            TS:ParseMessage(msg, playerShort, channelName, "channel")
        end

    elseif event == "CHAT_MSG_GUILD" then
        -- arg1=message, arg2=playerName
        if not TS.db or not TS.db.scanGuild then return end
        local msg, player = ...
        if msg and player then
            local playerShort = player:match("^([^%-]+)") or player
            TS:ParseMessage(msg, playerShort, "guild", "guild")
        end

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
        C_Timer.After(0.3, function()
            TS:ScanCurrentTradeSkill()
        end)
    end
end)

-- ============================================================
-- COMMANDES SLASH
-- ============================================================

function TS:HandleSlash(msg)
    msg = msg or ""
    local cmd, arg = msg:lower():match("^%s*(%S*)%s*(.*)")
    cmd = cmd or ""

    if cmd == "" then
        if self.UI then self.UI:Toggle() end

    elseif cmd == "clear" then
        self.db.offers = {}
        if self.UI then self.UI:Refresh() end
        print("|cFF00CCFFTradeScanner|r Offers cleared.")

    elseif cmd == "scan" then
        local count, prof = self:ScanCurrentTradeSkill()
        if prof then
            print(string.format("|cFF00CCFFTradeScanner|r %s: %d recipes indexed.", prof, count))
        else
            print("|cFF00CCFFTradeScanner|r Open a profession window first.")
        end

    elseif cmd == "channel" then
        if arg and arg ~= "" then
            self.db.channel = arg:lower()
            print("|cFF00CCFFTradeScanner|r Channel: |cFF00CCFF" .. self.db.channel .. "|r")
        else
            print("|cFF00CCFFTradeScanner|r Current channel: |cFF00CCFF" .. self.db.channel .. "|r")
        end

    elseif cmd == "add" then
        local side, kw = arg:match("^(%S+)%s+(.+)")
        if side and kw and (side == "sell" or side == "buy") then
            local kwUpper = kw:upper():gsub("%s+", "")
            table.insert(self.db.keywords[side], kwUpper)
            print(string.format("|cFF00CCFFTradeScanner|r Keyword [%s] added: |cFFFFFF00%s|r", side, kwUpper))
        else
            print("|cFF00CCFFTradeScanner|r Usage: /ts add sell <WORD> or /ts add buy <WORD>")
        end

    elseif cmd == "remove" then
        local side, kw = arg:match("^(%S+)%s+(.+)")
        if side and kw and (side == "sell" or side == "buy") then
            local kwUpper = kw:upper():gsub("%s+", "")
            local list = self.db.keywords[side]
            for i = #list, 1, -1 do
                if list[i] == kwUpper then
                    table.remove(list, i)
                    print(string.format("|cFF00CCFFTradeScanner|r Keyword [%s] removed: |cFFFF4444%s|r", side, kwUpper))
                    return
                end
            end
            print("|cFF00CCFFTradeScanner|r Keyword not found: " .. kwUpper)
        else
            print("|cFF00CCFFTradeScanner|r Usage: /ts remove sell <WORD> or /ts remove buy <WORD>")
        end

    elseif cmd == "alert" then
        self.db.alertSound = not self.db.alertSound
        local state = self.db.alertSound and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
        print("|cFF00CCFFTradeScanner|r Craft alert sound: " .. state)

    elseif cmd == "debug" then
        self.db.debugLog = not self.db.debugLog
        local state = self.db.debugLog and "|cFF33DD33ON|r" or "|cFFFF4444OFF|r"
        print("|cFF00CCFFTradeScanner|r Debug log: " .. state .. " (chaque message du canal affiché)")

    elseif cmd == "log" then
        local n       = tonumber(arg) or 30
        local entries = (self.log and self.log.entries) or {}
        local shown   = math.min(n, #entries)
        print(string.format("|cFF00CCFFTradeScanner|r — %d derniers messages (%d total):", shown, #entries))
        for i = 1, shown do
            local e   = entries[i]
            local age = time() - e.ts
            local col = e.r == "sell"      and "|cFF33DD33"
                     or e.r == "buy"       and "|cFF33AAFF"
                     or e.r == "skip_kw"   and "|cFFFF9900"
                     or e.r == "skip_chan" and "|cFF666666"
                     or "|cFFAAAAAA"
            local txt = e.m or ""
            if #txt > 70 then txt = txt:sub(1, 70) .. "…" end
            print(string.format("  %s[%s]|r %ds [%s] %s: %s",
                col, e.r, age, e.ch or "?", e.p or "?", txt))
        end

    elseif cmd == "logclear" then
        if self.log then self.log.entries = {} end
        print("|cFF00CCFFTradeScanner|r Log effacé.")

    elseif cmd == "guild" then
        self.db.scanGuild = not self.db.scanGuild
        local state = self.db.scanGuild and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
        print("|cFF00CCFFTradeScanner|r Guild chat scan (GreenWall): " .. state)

    elseif cmd == "keywords" or cmd == "kw" then
        print("|cFF00CCFFTradeScanner|r Sell keywords: " .. table.concat(self.db.keywords.sell, ", "))
        print("|cFF00CCFFTradeScanner|r Buy keywords:  " .. table.concat(self.db.keywords.buy,  ", "))

    elseif cmd == "help" then
        print("|cFF00CCFFTradeScanner|r --- Help ---")
        print("  /ts                       - open/close window")
        print("  /ts clear                 - clear all offers")
        print("  /ts scan                  - scan open profession window")
        print("  /ts channel <name>        - set channel (default: freshtrade)")
        print("  /ts guild                 - toggle /g scan (GreenWall)")
        print("  /ts alert                 - toggle craft alert sound")
        print("  /ts debug                 - toggle affichage temps réel du canal")
        print("  /ts log [N]               - afficher les N derniers messages (défaut: 30)")
        print("  /ts logclear              - vider le log")
        print("  /ts add sell <WORD>       - add a sell keyword")
        print("  /ts add buy <WORD>        - add a buy keyword")
        print("  /ts remove sell <WORD>    - remove a sell keyword")
        print("  /ts keywords              - list active keywords")

    else
        if self.UI then self.UI:Toggle() end
    end
end
