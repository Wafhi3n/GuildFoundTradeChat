-- TradeScanner_Offers.lua
-- Parsing chat messages, offer database, sellable/guild wants, craft alerts.

local TS = TradeScanner

local OFFER_EXPIRY = 1800
local MAX_OFFERS   = 300

-- ============================================================
-- CHAT PARSING HELPERS (file-local)
-- ============================================================

local function StripChannelNumber(channelName)
    return channelName:gsub("^%d+%.%s*", ""):lower()
end

-- Strips item links and color codes before numeric scanning to avoid false matches.
local function StripMarkup(msg)
    msg = msg:gsub("|H.-|h%[.-%]|h", " ")
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
    return msg
end

local function ExtractQuantity(text)
    text = StripMarkup(text)
    local low = text:lower()
    local n = text:match("(%d+)%s*[xX]%f[%s%p%z]") or text:match("[xX]%s*(%d+)")
    if n then return "x" .. n end
    if low:find("/stack", 1, true) or low:find("per stack", 1, true)
       or low:find("/stk", 1, true) or low:find("%f[%a]stack%f[%A]") then
        return "/stack"
    end
    if low:find("%f[%a]each%f[%A]") or low:find("%f[%a]ea%f[%A]")
       or low:find("%f[%a]piece%f[%A]") or low:find("/u", 1, true) then
        return "ea"
    end
    return nil
end

local function DetectOfferType(msg, keywords)
    local upper = msg:upper()
    -- sell/buy d'abord (un "WTS ... free" reste une vente), puis gift (WTG/don).
    for _, kw in ipairs(keywords.sell) do
        if upper:find(kw, 1, true) then return "sell" end
    end
    for _, kw in ipairs(keywords.buy) do
        if upper:find(kw, 1, true) then return "buy" end
    end
    for _, kw in ipairs(keywords.gift or {}) do
        if upper:find(kw, 1, true) then return "gift" end
    end
    return nil
end

local function ExtractItemLinks(msg)
    local items       = {}
    local pattern     = "|H(item:%d+[^|]*)|h%[([^%]]+)%]|h"
    local searchStart = 1
    while true do
        local s, e, itemKey, itemName = msg:find(pattern, searchStart)
        if not s then break end
        local itemID = tonumber(itemKey:match("item:(%d+)"))
        if itemID then
            table.insert(items, {
                itemID   = itemID,
                name     = itemName,
                link     = "|H" .. itemKey .. "|h[" .. itemName .. "]|h",
                startPos = s,
                endPos   = e,
            })
        end
        searchStart = e + 1
    end
    return items
end

local function ExtractPrice(msg)
    msg = StripMarkup(msg)
    local g, s, c

    g, s, c = msg:match("(%d+)%s*[gG]%s*(%d+)%s*[sS]%s*(%d+)%s*[cC]")
    if g then
        return string.format("%sg %ss %sc", g, s, c),
               tonumber(g) * 10000 + tonumber(s) * 100 + tonumber(c)
    end
    g, s = msg:match("(%d+)%s*[gG]%s*(%d+)%s*[sS]")
    if g then
        return string.format("%sg %ss", g, s),
               tonumber(g) * 10000 + tonumber(s) * 100
    end
    local dg = msg:match("(%d+[%.,]%d+)%s*[gG]")
    if dg then
        local norm = dg:gsub(",", ".")
        return norm .. "g", math.floor(tonumber(norm) * 10000)
    end
    g = msg:match("(%d+)%s*[gG]")
    if g then return string.format("%sg", g), tonumber(g) * 10000 end
    local ds = msg:match("(%d+[%.,]%d+)%s*[sS]")
    if ds then
        local norm = ds:gsub(",", ".")
        return norm .. "s", math.floor(tonumber(norm) * 100)
    end
    s = msg:match("(%d+)%s*[sS]")
    if s then return string.format("%ss", s), tonumber(s) * 100 end
    c = msg:match("(%d+)%s*[cC]")
    if c then return string.format("%sc", c), tonumber(c) end
    return nil, 0
end

-- ============================================================
-- MESSAGE LOG
-- ============================================================

local LOG_MAX = 300

function TS:LogRaw(player, channelName, msg, result)
    local entry = { ts = time(), p = player, ch = channelName, m = msg, r = result }
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

-- Pure analysis (no side effects). Shared by ParseMessage and /ts retest.
function TS:Classify(msg)
    local keywords   = self.db.keywords
    local globalType = DetectOfferType(msg, keywords)
    local priceText, priceValue = ExtractPrice(msg)
    local items = ExtractItemLinks(msg)
    local result = {
        offerType  = globalType,
        priceText  = priceText,
        priceValue = priceValue,
        isService  = (globalType == "sell" and #items == 0
                      and msg:upper():find("LFW", 1, true) ~= nil),
        items      = {},
    }
    for i, item in ipairs(items) do
        local typeStart = (i > 1) and (items[i - 1].endPos + 1) or 1
        local typeSeg   = msg:sub(typeStart, item.startPos - 1)
        local itemType  = DetectOfferType(typeSeg, keywords) or globalType
        local segEnd    = items[i + 1] and (items[i + 1].startPos - 1) or #msg
        local priceSeg  = msg:sub(item.endPos + 1, segEnd)
        local pText, pValue = ExtractPrice(priceSeg)
        if not pText then pText, pValue = priceText, priceValue end
        local qtyText = ExtractQuantity(priceSeg) or ExtractQuantity(typeSeg)
        table.insert(result.items, {
            itemID     = item.itemID,
            name       = item.name,
            link       = item.link,
            offerType  = itemType,
            priceText  = pText,
            priceValue = pValue,
            qtyText    = qtyText,
        })
    end
    return result
end

-- source: "channel" | "guild"
function TS:ParseMessage(msg, player, channelName, source)
    source = source or "channel"
    if source == "channel" then
        local chanClean = StripChannelNumber(channelName)
        if not self:ChannelIsWatched(chanClean) then
            self:LogRaw(player, channelName, msg, "skip_chan")
            return
        end
        -- Filtre "confédération seule" (#5) : canal public bruyant (ex. Trade) → ne garder
        -- que les expéditeurs connus de la confédération.
        if self:ChannelConfedOnly(chanClean)
           and not (self.Guild and self.Guild:IsConfederate(player)) then
            self:LogRaw(player, channelName, msg, "skip_confed")
            return
        end
    end
    local cls = self:Classify(msg)
    if not cls.offerType then
        self:LogRaw(player, channelName, msg, "skip_kw")
        return
    end
    self:LogRaw(player, channelName, msg, cls.offerType)
    if #cls.items == 0 then
        self:AddOffer({
            offerType  = cls.offerType, player = player,
            itemID     = nil, itemName = nil, itemLink = nil,
            priceText  = cls.priceText, priceValue = cls.priceValue,
            qtyText    = nil, isService = cls.isService, rawMsg = msg,
            timestamp  = time(), canCraft = false, profession = nil,
            source     = source,
        })
    else
        for _, it in ipairs(cls.items) do
            local cat, prof = self:GetProducible(it.itemID)
            self:AddOffer({
                offerType    = it.offerType, player = player,
                itemID       = it.itemID, itemName = it.name, itemLink = it.link,
                priceText    = it.priceText, priceValue = it.priceValue,
                qtyText      = it.qtyText, rawMsg = msg, timestamp = time(),
                canCraft     = cat ~= nil, sellCategory = cat, profession = prof,
                source       = source,
            })
        end
    end
end

-- ============================================================
-- OFFER DATABASE
-- ============================================================

function TS:IsDone(player, itemID)
    if not player or not itemID then return false end
    local key = player .. "_" .. tostring(itemID)
    return (self.db.doneOffers and self.db.doneOffers[key]) == true
end

function TS:MarkDone(player, itemID, fromNetwork)
    if not player or not itemID then return end
    self.db.doneOffers[player.."_"..tostring(itemID)] = true
    self:RequestRefresh()
    if not fromNetwork and self.Net then self.Net:BroadcastDone(player, itemID) end
end

function TS:AddOffer(offer)
    local db = self.db
    -- Dedup by player+item: update existing entry and move to top
    if offer.itemID then
        for i, existing in ipairs(db.offers) do
            if existing.player == offer.player
               and existing.itemID == offer.itemID then
                existing.timestamp    = offer.timestamp
                existing.offerType    = offer.offerType
                existing.priceText    = offer.priceText
                existing.priceValue   = offer.priceValue
                existing.qtyText      = offer.qtyText
                existing.canCraft     = offer.canCraft
                existing.sellCategory = offer.sellCategory
                existing.profession   = offer.profession
                existing.source       = offer.source
                -- New post from same player clears "done" status
                if db.doneOffers then
                    db.doneOffers[existing.player.."_"..tostring(existing.itemID)] = nil
                end
                table.remove(db.offers, i)
                table.insert(db.offers, 1, existing)
                self:RequestRefresh()
                return
            end
        end
    else
        -- No item link: dedup by player + raw message
        for i, existing in ipairs(db.offers) do
            if existing.player == offer.player
               and existing.rawMsg == offer.rawMsg then
                existing.timestamp = offer.timestamp
                table.remove(db.offers, i)
                table.insert(db.offers, 1, existing)
                self:RequestRefresh()
                return
            end
        end
    end

    table.insert(db.offers, 1, offer)
    if #db.offers > MAX_OFFERS then table.remove(db.offers) end
    if offer.offerType == "buy" and offer.canCraft
       and self:CanFulfill(offer.sellCategory, offer.profession) then
        self:AlertCraftable(offer)
    end
    self:RequestRefresh()
    if self.Net and offer.source ~= "network" then self.Net:BroadcastOffer(offer) end
end

-- Public wrapper for the order UI price input box.
function TS:ParsePrice(text)
    return ExtractPrice(text or "")
end

-- Creates a WTS offer for the local player (bag Alt-right-click → WTS popup).
-- source="self" (≠ "network") → AddOffer broadcasts OF and refreshes the UI,
-- so the offer reaches addon users even if the chat post fails. The later chat
-- echo dedups by player+itemID. Note (rawMsg) and qtyText are local-only: the
-- OF protocol carries neither, but the chat message does.
function TS:CreateLocalOffer(itemID, itemLink, itemName, priceText, priceValue, qtyText, note)
    if not itemID then return end
    local me = UnitName("player") or "?"
    local cat, prof = self:GetProducible(itemID)
    self:AddOffer({
        offerType    = "sell", player = me,
        itemID       = itemID, itemName = itemName or self:GetItemName(itemID),
        itemLink     = itemLink,
        priceText    = priceText, priceValue = priceValue or 0,
        qtyText      = qtyText, rawMsg = (note ~= "" and note) or nil,
        timestamp    = time(),
        canCraft     = cat ~= nil, sellCategory = cat, profession = prof,
        source       = "self",
    })
end

-- ============================================================
-- SELLABLE + GUILD WANTS + CRAFT ALERTS
-- ============================================================

-- True if the local player can personally fulfil a producible item:
-- manually flagged, a scanned recipe, or a profession actually learned.
-- (≠ "someone in the guild can craft it" — that's just GetProducible.)
function TS:CanFulfill(cat, prof)
    if not cat then return false end
    if cat == "manual" or cat == "scan" then return true end
    return (self.Guild and self.Guild:IHaveProfession(prof)) == true
end

function TS:GetSellableOffers()
    local now, result = time(), {}
    for _, offer in ipairs(self.db.offers) do
        if offer.offerType == "buy"
           and (now - offer.timestamp) <= OFFER_EXPIRY
           and offer.itemID then
            local cat, prof = self:GetProducible(offer.itemID)
            if self:CanFulfill(cat, prof) then
                table.insert(result, offer)
            end
        end
    end
    return result
end

-- Flat list of chat WTB offers whose item is craftable in profCanonical.
-- Feeds the "Chat requests" section of the Orders tab (one row per offer).
function TS:GetCraftableWantsFor(profCanonical)
    local now, out = time(), {}
    if not profCanonical then return out end
    local me = UnitName("player") or "?"
    for _, offer in ipairs(self.db.offers) do
        if offer.offerType == "buy" and offer.itemID and offer.player ~= me
           and (now - offer.timestamp) <= OFFER_EXPIRY then
            local cat, prof = self:GetProducible(offer.itemID)
            if cat and self:ResolveProfession(prof) == profCanonical then
                out[#out + 1] = offer
            end
        end
    end
    return out
end

local function AddWant(bucket, index, key, offer, name)
    local entry = index[key]
    if not entry then
        entry = {
            itemID  = offer and offer.itemID,
            name    = name,
            link    = offer and offer.itemLink,
            players = {},
            seen    = {},
            count   = 0,
        }
        index[key] = entry
        table.insert(bucket, entry)
    end
    local p = offer and offer.player
    if p and not entry.seen[p] then
        entry.seen[p] = true
        table.insert(entry.players, p)
        entry.count = entry.count + 1
    end
    if offer and offer.itemLink and not entry.link then entry.link = offer.itemLink end
end

function TS:GetGuildWants(profName)
    local result = { disenchant = {}, sellable = {}, enchants = {} }
    if not profName then return result end
    local idxDis, idxSell, idxEnch = {}, {}, {}
    local disMats = self:GetDisenchantMats(profName)
    local now = time()
    for _, offer in ipairs(self.db.offers) do
        if offer.offerType == "buy" and (now - offer.timestamp) <= OFFER_EXPIRY then
            if offer.itemID then
                if disMats[offer.itemID] then
                    AddWant(result.disenchant, idxDis, offer.itemID, offer,
                            self:GetItemName(offer.itemID, disMats[offer.itemID]))
                else
                    local cat, prof = self:GetProducible(offer.itemID)
                    if cat then
                        local canonical = self:ResolveProfession(prof)
                        if cat == "manual" or canonical == profName then
                            AddWant(result.sellable, idxSell, offer.itemID, offer,
                                    self:GetItemName(offer.itemID, offer.itemName))
                        end
                    end
                end
            elseif offer.rawMsg then
                local low = offer.rawMsg:lower()
                for _, ench in ipairs(self.staticEnchants or {}) do
                    if self:ResolveProfession(ench.profession) == profName then
                        if low:find(ench.name:lower(), 1, true) then
                            AddWant(result.enchants, idxEnch, ench.name, offer, ench.name)
                        end
                    end
                end
            end
        end
    end
    return result
end

function TS:AlertCraftable(offer)
    local itemStr = offer.itemLink or offer.itemName or "?"
    local prof    = offer.profession or "?"
    print(string.format(
        "|cFF00CCFFGuild Economy|r |cFFFFCC00>> CRAFT|r [%s] %s wants %s  — |cFFFFFFFF/w %s|r",
        prof, offer.player, itemStr, offer.player
    ))
    if self.db.alertSound then PlaySound(1191) end
    if self.Minimap then self.Minimap:SetAlert(true) end
end
