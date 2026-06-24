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
        sell = { "WTS", "VDS", "S>", "VEND", "SELL", "LFW" },          -- LFW = looking for work (services)
        buy  = { "WTB", "ACH", "B>", "ACHAT", "BUY", "CHERCHE", "ISO", "WTT", "TROC" },  -- WTT/TROC = troc → traité comme demande
    },
}

-- Mots-clés ajoutés après coup : à ré-injecter dans les DB existantes (cf. migration Init).
local KEYWORD_MIGRATIONS = {
    sell = { "LFW" },
    buy  = { "WTT", "TROC" },
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
    if not db.offers         then db.offers         = {} end
    if not db.craftedItems   then db.craftedItems   = {} end
    if not db.craftedNames   then db.craftedNames   = {} end
    if not db.manualSellable then db.manualSellable = {} end  -- [itemID] = nom (ajout dropdown)
    if not db.excludedItems  then db.excludedItems  = {} end  -- [itemID] = true (retirés du scan)
    if not db.doneOffers     then db.doneOffers     = {} end  -- ["player_itemID"] = true (traités)
    if not db.guildRoster    then db.guildRoster    = {} end  -- [player] = { professions={}, lastSeen }
    if not db.craftOrders    then db.craftOrders    = {} end  -- commandes de craft (cf. Guild)
    if db.scanGuild == nil   then db.scanGuild      = true end
    if db.alertSound == nil  then db.alertSound     = true end
    if db.debugLog == nil    then db.debugLog       = false end

    self.db           = db
    self.craftedItems = db.craftedItems
    self.craftedNames = db.craftedNames

    -- Charger les bdd statiques (Data/Professions/*.lua) dans les tables de recherche
    if self.LoadStaticData then self:LoadStaticData() end

    -- Migration : purger les entrées de scan erronées ("UNKNOWN", venant de
    -- l'Enchantement scanné via la mauvaise API avant le support Craft)
    for id, prof in pairs(self.craftedItems) do
        if prof == "UNKNOWN" then self.craftedItems[id] = nil end
    end
    for name, info in pairs(self.craftedNames) do
        if type(info) == "table" and info.profession == "UNKNOWN" then
            self.craftedNames[name] = nil
        end
    end

    -- Migration : ré-injecter les mots-clés ajoutés après coup (WTT/TROC/LFW) dans les
    -- listes déjà sauvegardées, sinon les défauts ne s'appliquent jamais aux DB existantes.
    for side, words in pairs(KEYWORD_MIGRATIONS) do
        local list = db.keywords[side]
        for _, kw in ipairs(words) do
            local present = false
            for _, existing in ipairs(list) do
                if existing == kw then present = true break end
            end
            if not present then table.insert(list, kw) end
        end
    end

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

-- Retire le markup de chat (liens d'objet + codes couleur) pour fiabiliser le scan
-- numérique (prix/quantité) : sans ça, les itemID (|Hitem:2205…) ou les codes
-- couleur (|cff1eff00) pourraient fournir de faux chiffres.
local function StripMarkup(msg)
    msg = msg:gsub("|H.-|h%[.-%]|h", " ")     -- lien d'objet complet -> espace
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")  -- ouverture couleur |cAARRGGBB
    msg = msg:gsub("|r", "")                   -- fermeture couleur
    return msg
end

-- Détecte un modificateur de quantité/unité dans un fragment de texte.
-- Best-effort, sans normaliser le prix (trop ambigu) : on renvoie juste un libellé
-- à afficher à côté du prix ("x5", "/stack", "ea"), ou nil.
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
    -- On enregistre aussi la position (startPos/endPos) pour pouvoir associer
    -- à chaque item le prix qui le suit (cf. ExtractPrice par segment).
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

    -- Cuivre seul : "50c" (en dernier, pour ne pas primer sur g/s)
    c = msg:match("(%d+)%s*[cC]")
    if c then
        return string.format("%sc", c), tonumber(c)
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

-- Analyse PURE d'un message (aucun effet de bord, n'écrit pas dans db.offers).
-- Partagée par ParseMessage (production) et /ts retest (rejeu du log).
-- Retourne :
--   { offerType = "sell"|"buy"|nil,   -- type global (fallback)
--     priceText, priceValue,          -- prix global (fallback)
--     isService = bool,               -- service/LFW sans item
--     items = { { itemID, name, link, offerType, priceText, priceValue, qtyText }, … } }
function TS:Classify(msg)
    local keywords = self.db.keywords
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
        -- Type par item : le mot-clé PRÉCÈDE l'item → on lit le texte AVANT le lien
        -- (depuis la fin de l'item précédent, ou le début du message). Gère les
        -- messages mixtes : "WTS [A] WTB [B]". Fallback sur le type global.
        local typeStart = (i > 1) and (items[i - 1].endPos + 1) or 1
        local typeSeg   = msg:sub(typeStart, item.startPos - 1)
        local itemType  = DetectOfferType(typeSeg, keywords) or globalType

        -- Prix par item : le prix SUIT l'item → on lit le texte APRÈS le lien,
        -- jusqu'au lien suivant (ou la fin). Gère les prix distincts :
        --   "WTB [Greater Astral Essence] 60s OR/AND [Lesser Astral Essence] 20s"
        -- Fallback sur le prix global.
        local segEnd   = items[i + 1] and (items[i + 1].startPos - 1) or #msg
        local priceSeg = msg:sub(item.endPos + 1, segEnd)
        local pText, pValue = ExtractPrice(priceSeg)
        if not pText then
            pText, pValue = priceText, priceValue
        end

        -- Quantité/unité : cherchée après l'item d'abord, puis avant.
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

    local cls = self:Classify(msg)
    if not cls.offerType then
        self:LogRaw(player, channelName, msg, "skip_kw")
        return
    end

    self:LogRaw(player, channelName, msg, cls.offerType)

    if #cls.items == 0 then
        self:AddOffer({
            offerType  = cls.offerType,
            player     = player,
            itemID     = nil,
            itemName   = nil,
            itemLink   = nil,
            priceText  = cls.priceText,
            priceValue = cls.priceValue,
            qtyText    = nil,
            isService  = cls.isService,
            rawMsg     = msg,
            timestamp  = time(),
            canCraft   = false,
            profession = nil,
            source     = source,
        })
    else
        for _, it in ipairs(cls.items) do
            local cat, prof = self:GetProducible(it.itemID)
            self:AddOffer({
                offerType   = it.offerType,
                player      = player,
                itemID      = it.itemID,
                itemName    = it.name,
                itemLink    = it.link,
                priceText   = it.priceText,
                priceValue  = it.priceValue,
                qtyText     = it.qtyText,
                rawMsg      = msg,
                timestamp   = time(),
                canCraft    = cat ~= nil,
                sellCategory = cat,
                profession  = prof,
                source      = source,
            })
        end
    end
end

-- ============================================================
-- BASE D'OFFRES
-- ============================================================

function TS:IsDone(player, itemID)
    if not player or not itemID then return false end
    local key = player .. "_" .. tostring(itemID)
    return (self.db.doneOffers and self.db.doneOffers[key]) == true
end

function TS:MarkDone(player, itemID, fromNetwork)
    if not player or not itemID then return end
    self.db.doneOffers[player.."_"..tostring(itemID)] = true
    if self.UI then self.UI:Refresh() end
    if self.ProfPanel and self.ProfPanel.Refresh then self.ProfPanel:Refresh() end
    if not fromNetwork and self.Net then
        self.Net:BroadcastDone(player, itemID)
    end
end

function TS:AddOffer(offer)
    local db  = self.db

    -- Déduplication: même joueur + même item (sans limite de temps)
    -- On met à jour l'entrée existante et on la remonte en tête
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
                -- Nouvelle demande du même joueur : clear le done flag
                if db.doneOffers then
                    db.doneOffers[existing.player.."_"..tostring(existing.itemID)] = nil
                end
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

    -- Broadcaster la nouvelle offre (via réseau), sauf si elle vient du réseau
    if self.Net and offer.source ~= "network" then
        self.Net:BroadcastOffer(offer)
    end
end

function TS:GetOffers(filterType, craftOnly)
    local now    = time()
    local result = {}
    for _, offer in ipairs(self.db.offers) do
        if (now - offer.timestamp) <= OFFER_EXPIRY then
            local typeOk  = (filterType == nil or offer.offerType == filterType)
            local craftOk = (not craftOnly) or offer.canCraft
            local doneOk  = not (offer.itemID and self:IsDone(offer.player, offer.itemID))
            if typeOk and craftOk and doneOk then
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

-- Nom localisé d'un item (multilingue via l'API). Fallback = label de secours.
function TS:GetItemName(itemID, fallback)
    if not itemID then return fallback end
    local name = GetItemInfo(itemID)
    return name or fallback or ("item:" .. itemID)
end

-- Parse public d'un texte de prix (utilisé par l'UI des commandes).
-- Retourne priceText, priceValue(cuivre). Délègue au parseur interne ExtractPrice.
function TS:ParsePrice(text)
    return ExtractPrice(text or "")
end

-- Détermine si un itemID est "fournissable" par le joueur, et comment.
-- Retourne category, profession :
--   "manual"     = ajouté à la main via le dropdown
--   "scan"       = recette scannée sur un perso
--   "sellable"   = produit listé dans une bdd métier
--   "disenchant" = mat de désenchantement listé dans une bdd
-- Retourne nil si inconnu ou explicitement exclu du scan.
--
-- Ordre de priorité :
--   1. "manual"  : le joueur l'a ajouté explicitement → prime sur tout
--   2. "scan"    : recette indexée lors d'un scan de métier
--   3. statique  : entrée "sellable" ou "disenchant" dans Data/Professions/*.lua
--      → les items statiques qui sont AUSSI craftables (baguettes, tiges, huiles)
--        servent de repli tant que le joueur n'a pas encore scanné ; la bdd statique
--        couvre surtout les mats de désenchantement qui n'apparaissent pas dans la
--        liste de crafts (poussières, essences, éclats).
-- Retourne nil si l'item est dans excludedItems.
function TS:GetProducible(itemID)
    if not itemID then return nil end
    if self.db and self.db.excludedItems and self.db.excludedItems[itemID] then
        return nil
    end
    if self.db and self.db.manualSellable and self.db.manualSellable[itemID] then
        return "manual", "Manuel"
    end
    local scanned = self.craftedItems[itemID]
    if scanned then
        return "scan", scanned
    end
    local s = self.staticItems and self.staticItems[itemID]
    if s then
        return s.category, s.profession
    end
    return nil
end

-- Vrai si le joueur peut fournir cet item (toutes catégories confondues)
function TS:CanSell(itemID)
    return (self:GetProducible(itemID)) ~= nil
end

-- Bascule l'exclusion d'un item du scan (bouton filtre du panneau métier)
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

-- Ajoute un item à la liste vendable manuelle (dropdown)
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

-- Enregistre un produit scanné dans les tables de recherche (clé canonique)
function TS:RecordCraftedItem(itemID, itemName, canonicalProf)
    self.craftedItems[itemID] = canonicalProf
    if itemName then
        self.craftedNames[itemName:lower()] = {
            itemID     = itemID,
            profession = canonicalProf,
        }
    end
end

-- Vrai si le CraftFrame (Enchantement/Dressage) est affiché.
function TS:IsCraftOpen()
    return CraftFrame and CraftFrame:IsShown()
end

-- Retourne itemID, link de la recette actuellement sélectionnée
-- (fonctionne pour l'API Craft comme pour l'API TradeSkill).
function TS:GetSelectedRecipe()
    if self:IsCraftOpen() then
        local idx = GetCraftSelectionIndex and GetCraftSelectionIndex()
        if idx and idx > 0 and GetCraftItemLink then
            local link = GetCraftItemLink(idx)
            if link then return tonumber(link:match("|Hitem:(%d+)")), link end
        end
        return nil
    end
    local idx = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()
    if not idx or idx < 1 then return nil end
    local link = GetTradeSkillItemLink and GetTradeSkillItemLink(idx)
    if not link then return nil end
    return tonumber(link:match("|Hitem:(%d+)")), link
end

-- Lecteur unifié du métier ouvert.
-- En Classic Era, l'Enchantement (et le Dressage) passent par l'API CRAFT,
-- pas TradeSkill : GetTradeSkillLine() y renvoie "UNKNOWN".
-- Retourne nom_localisé, isCraft.
function TS:GetOpenProfessionInfo()
    -- API Craft (Enchantement, Dressage)
    if CraftFrame and CraftFrame:IsShown() then
        local name = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()
                  or (GetCraftName and GetCraftName())
        if name and name ~= "" and name ~= "UNKNOWN" then
            return name, true
        end
    end
    -- API TradeSkill (autres métiers)
    if GetTradeSkillLine then
        local name = GetTradeSkillLine()
        if name and name ~= "" and name ~= "UNKNOWN" then
            return name, false
        end
    end
    return nil, nil
end

-- Tables décrivant chaque API métier — injectées dans ScanRecipes
local TRADESKILL_API = {
    getNum      = function() return (GetNumTradeSkills and GetNumTradeSkills()) or 0 end,
    getInfo     = function(i) return GetTradeSkillInfo(i) end,           -- name, skillType
    getLink     = function(i) return GetTradeSkillItemLink(i) end,
    getSkillName= function() return GetTradeSkillLine and GetTradeSkillLine() end,
    isHeader    = function(t) return t == "header" or t == "subheader" end,
}
local CRAFT_API = {
    getNum      = function() return (GetNumCrafts and GetNumCrafts()) or 0 end,
    getInfo     = function(i) return GetCraftInfo(i) end,                -- name, sub, craftType
    getLink     = function(i) return GetCraftItemLink and GetCraftItemLink(i) end,
    getSkillName= function() return (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
                                  or (GetCraftName and GetCraftName()) end,
    isHeader    = function(t) return t == "header" end,
}

-- Boucle de scan commune, paramétrée par une table d'API (TRADESKILL_API ou CRAFT_API).
-- Retourne count, canonical (0, nil si le métier est indisponible ou UNKNOWN).
-- Ne déclenche PAS RefreshCraftStatus — c'est ScanOpenProfession qui le fait une seule fois.
function TS:ScanRecipes(api)
    local skillName = api.getSkillName()
    if not skillName or skillName == "" or skillName == "UNKNOWN" then return 0, nil end
    local canonical = self:ResolveProfession(skillName)

    local num   = api.getNum()
    local count = 0

    for i = 1, num do
        -- TradeSkill renvoie (name, skillType) ; Craft renvoie (name, sub, craftType).
        -- On extraie le type en 2e ou 3e position selon l'API via les wrappers ci-dessus.
        local name, skillType
        if api == TRADESKILL_API then
            name, skillType = api.getInfo(i)
        else
            name, _, skillType = api.getInfo(i)
        end
        if name and not api.isHeader(skillType) then
            local link = api.getLink(i)
            if link then
                local itemID = tonumber(link:match("|Hitem:(%d+)"))
                if itemID then
                    self:RecordCraftedItem(itemID, link:match("|h%[(.-)%]|h"), canonical)
                    count = count + 1
                end
            end
        end
    end

    return count, canonical
end

-- Scan du métier ouvert, quel que soit l'API (TradeSkill ou Craft).
-- Appelle RefreshCraftStatus une seule fois après le scan (point 5).
function TS:ScanOpenProfession()
    local _, isCraft = self:GetOpenProfessionInfo()
    local count, canonical = self:ScanRecipes(isCraft and CRAFT_API or TRADESKILL_API)
    if count > 0 then self:RefreshCraftStatus() end
    return count, canonical
end

function TS:RefreshCraftStatus()
    for _, offer in ipairs(self.db.offers) do
        if offer.itemID then
            local cat, prof = self:GetProducible(offer.itemID)
            offer.canCraft     = cat ~= nil
            offer.sellCategory = cat
            offer.profession   = prof
        end
    end
    if self.UI then self.UI:Refresh() end
    if self.ProfPanel and self.ProfPanel.Refresh then self.ProfPanel:Refresh() end
end

function TS:GetCraftedProfessions()
    -- Retourne un résumé: { profName = count }
    local profs = {}
    for _, profName in pairs(self.craftedItems) do
        profs[profName] = (profs[profName] or 0) + 1
    end
    return profs
end

-- Offres WTB que le joueur peut fournir (= onglet "Sellable")
function TS:GetSellableOffers()
    local now    = time()
    local result = {}
    for _, offer in ipairs(self.db.offers) do
        if offer.offerType == "buy"
           and (now - offer.timestamp) <= OFFER_EXPIRY
           and offer.itemID and self:CanSell(offer.itemID) then
            table.insert(result, offer)
        end
    end
    return result
end

-- ------------------------------------------------------------------
-- "Qui veut quoi" pour un métier donné (panneau latéral)
-- profName = clé canonique ("Enchanting")
-- Retourne { disenchant = {entry...}, sellable = {entry...}, enchants = {entry...} }
-- entry = { itemID=, name=, link=, players={nom...}, count=N }
-- ------------------------------------------------------------------
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
    if offer and offer.itemLink and not entry.link then
        entry.link = offer.itemLink
    end
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
                -- Enchantements (services sans item) : matching texte best-effort
                local low = offer.rawMsg:lower()
                for _, ench in ipairs(self.staticEnchants or {}) do
                    if self:ResolveProfession(ench.profession) == profName then
                        local needle = ench.name:lower()
                        if low:find(needle, 1, true) then
                            AddWant(result.enchants, idxEnch, ench.name, offer, ench.name)
                        end
                    end
                end
            end
        end
    end

    return result
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
eventFrame:RegisterEvent("TRADE_SKILL_CLOSE")
eventFrame:RegisterEvent("CRAFT_SHOW")            -- Enchantement (API Craft)
eventFrame:RegisterEvent("CRAFT_UPDATE")
eventFrame:RegisterEvent("CRAFT_CLOSE")

-- Scan (protégé) + affichage du panneau, commun TradeSkill et Craft.
-- Anti-rebond : un seul scan en vol à la fois (évite d'empiler les C_Timer.After
-- lors des rafales d'events TRADE_SKILL_LIST_UPDATE / CRAFT_UPDATE).
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
        -- Réseau inter-addon
        if TS.Net then TS.Net:Init() end
        -- Registre guilde + commandes de craft
        if TS.Guild then TS.Guild:Init() end
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

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
        or event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        HandleProfessionShow()

    elseif event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        if TS.ProfPanel then TS.ProfPanel:OnTradeSkillClose() end
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

    elseif cmd == "order" or cmd == "orders" then
        if self.OrderPanel then self.OrderPanel:Toggle() end

    elseif cmd == "profs" or cmd == "professions" then
        -- Diagnostic : mes métiers détectés + roster guilde
        if self.Guild then
            local mine = self.Guild.myProfessions or self.Guild:DetectMyProfessions()
            print("|cFF00CCFFTradeScanner|r Mes métiers : " ..
                (#mine > 0 and table.concat(mine, ", ") or "|cFF888888aucun|r"))
            local n = 0
            for player, info in pairs(self.db.guildRoster) do
                n = n + 1
                print(string.format("  |cFFCCCCCC%s|r : %s", player, table.concat(info.professions or {}, ", ")))
            end
            if n == 0 then print("  |cFF888888(aucun autre membre connu pour l'instant)|r") end
        end

    elseif cmd == "clear" then
        self.db.offers = {}
        if self.UI then self.UI:Refresh() end
        print("|cFF00CCFFTradeScanner|r Offers cleared.")

    elseif cmd == "scan" then
        local count, prof = self:ScanOpenProfession()
        if prof then
            print(string.format("|cFF00CCFFTradeScanner|r %s: %d recipes indexed.", prof, count))
        else
            print("|cFF00CCFFTradeScanner|r Open a profession window first.")
        end

    elseif cmd == "panel" then
        -- Force / diagnostique le panneau métier
        if not self.ProfPanel then
            print("|cFF00CCFFTradeScanner|r ProfPanel non chargé.")
            return
        end
        local name, isCraft = self:GetOpenProfessionInfo()
        if not name then
            print("|cFF00CCFFTradeScanner|r Aucune fenêtre de métier ouverte (ni TradeSkill ni Craft).")
            return
        end
        print(string.format("|cFF00CCFFTradeScanner|r Métier: '%s' (%s) → canonique: '%s'",
            name, isCraft and "Craft" or "TradeSkill", tostring(self:ResolveProfession(name))))
        local ok, err = pcall(function() self.ProfPanel:OnTradeSkillShow() end)
        if not ok then print("|cFFFF4444Panel error:|r " .. tostring(err)) end

    elseif cmd == "sell" then
        -- /ts sell <lien d'objet>  → ajoute/retire de la liste vendable manuelle
        -- (msg déjà en minuscules : on matche "item:" présent dans les deux casses)
        local itemID = tonumber((arg or ""):match("item:(%d+)")) or tonumber(arg)
        if itemID then
            if self.db.manualSellable[itemID] then
                self:RemoveManualSellable(itemID)
                print("|cFF00CCFFTradeScanner|r Retiré du vendable: " .. self:GetItemName(itemID))
            else
                self:AddManualSellable(itemID)
                print("|cFF00CCFFTradeScanner|r Ajouté au vendable: " .. self:GetItemName(itemID))
            end
        else
            print("|cFF00CCFFTradeScanner|r Usage: /ts sell <shift-clic d'un objet>")
        end

    elseif cmd == "exclude" then
        -- /ts exclude <lien d'objet>  → retire/réintègre un item du scan
        local itemID = tonumber((arg or ""):match("item:(%d+)")) or tonumber(arg)
        if itemID then
            local excluded = self:ToggleExcluded(itemID)
            local state = excluded and "|cFFFF4444exclu|r" or "|cFF33DD33réintégré|r"
            print("|cFF00CCFFTradeScanner|r " .. self:GetItemName(itemID) .. " " .. state)
        else
            print("|cFF00CCFFTradeScanner|r Usage: /ts exclude <shift-clic d'un objet>")
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

    elseif cmd == "retest" then
        -- Rejoue le parseur courant sur les messages déjà capturés (dry-run :
        -- aucune écriture d'offre). Valide les évolutions du parseur sur des cas réels.
        local entries    = (self.log and self.log.entries) or {}
        local limit      = tonumber(arg) or 30
        local counts     = { sell = 0, buy = 0, skip_kw = 0 }
        local changes    = {}
        local considered = 0
        for _, e in ipairs(entries) do
            if e.r ~= "skip_chan" then          -- on ignore le hors-canal (non pertinent)
                considered = considered + 1
                local cls    = self:Classify(e.m or "")
                local newCat = cls.offerType or "skip_kw"
                counts[newCat] = (counts[newCat] or 0) + 1
                if newCat ~= e.r then
                    table.insert(changes, { e = e, from = e.r, to = newCat, cls = cls })
                end
            end
        end
        print(string.format("|cFF00CCFFTradeScanner retest|r — %d messages rejoués (hors skip_chan)", considered))
        print(string.format("  bilan : |cFF33DD33sell=%d|r |cFF33AAFFbuy=%d|r |cFFFF9900skip_kw=%d|r — |cFFFFFF00%d changements|r",
            counts.sell or 0, counts.buy or 0, counts.skip_kw or 0, #changes))
        local shown = math.min(limit, #changes)
        for i = 1, shown do
            local ch  = changes[i]
            local txt = ch.e.m or ""
            if #txt > 55 then txt = txt:sub(1, 55) .. "…" end
            local extra = ""
            if #ch.cls.items > 0 then
                local parts = {}
                for _, it in ipairs(ch.cls.items) do
                    parts[#parts + 1] = string.format("%s%s",
                        it.priceText or "—", it.qtyText and (" " .. it.qtyText) or "")
                end
                extra = " |cFF888888{" .. table.concat(parts, ", ") .. "}|r"
            elseif ch.cls.priceText then
                extra = " |cFF888888{" .. ch.cls.priceText .. "}|r"
            end
            print(string.format("  |cFFFFFF00%s→%s|r %s%s", tostring(ch.from), ch.to, txt, extra))
        end
        if #changes > shown then
            print(string.format("  … (+%d autres ; /ts retest %d pour tout voir)", #changes - shown, #changes))
        end

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
        print("  /ts order                 - ouvre le panneau de commandes de craft (guilde)")
        print("  /ts profs                 - mes métiers + roster guilde connu")
        print("  /ts clear                 - clear all offers")
        print("  /ts scan                  - scan open profession window")
        print("  /ts sell <shift-clic>     - ajoute/retire un item vendable (manuel)")
        print("  /ts exclude <shift-clic>  - exclut/réintègre un item du scan")
        print("  /ts channel <name>        - set channel (default: freshtrade)")
        print("  /ts guild                 - toggle /g scan (GreenWall)")
        print("  /ts alert                 - toggle craft alert sound")
        print("  /ts debug                 - toggle affichage temps réel du canal")
        print("  /ts log [N]               - afficher les N derniers messages (défaut: 30)")
        print("  /ts retest [N]            - rejouer le parseur sur le log (valide les évolutions)")
        print("  /ts logclear              - vider le log")
        print("  /ts add sell <WORD>       - add a sell keyword")
        print("  /ts add buy <WORD>        - add a buy keyword")
        print("  /ts remove sell <WORD>    - remove a sell keyword")
        print("  /ts keywords              - list active keywords")

    else
        if self.UI then self.UI:Toggle() end
    end
end
