-- TradeScanner_Guild.lua
-- Registre des métiers de guilde + système de commandes de craft (Craft Orders).
--
-- Registre : chaque membre annonce SES métiers (PR) ; on garde qui peut crafter quoi.
-- Commandes : un membre poste une commande d'objet (CO) → diffusée à la guilde ; les
-- crafters du bon métier la voient et l'acceptent (CA, whisper auto). Persiste jusqu'à
-- annulation (CC) ou acceptation. Resync au login via le HELLO (HI) existant.

local TS    = TradeScanner
local Guild = {}
TS.Guild    = Guild
local L     = TS.L

-- ============================================================
-- DÉTECTION DE MES MÉTIERS (≠ scan de recettes)
-- ============================================================

-- Lit les skill lines du perso (Alchimie, Forge, …) et les résout en clés canoniques.
-- Ne garde que les métiers présents dans la base statique (TS.staticByProfession).
function Guild:DetectMyProfessions()
    local found = {}
    if GetNumSkillLines then
        -- Déplier les en-têtes pour ne rien manquer (sans état : on relit ensuite)
        if ExpandSkillHeader then pcall(ExpandSkillHeader, 0) end
        for i = 1, (GetNumSkillLines() or 0) do
            local name, isHeader = GetSkillLineInfo(i)
            if name and not isHeader then
                local canon = TS:ResolveProfession(name)
                if canon and TS.staticByProfession and TS.staticByProfession[canon] then
                    found[canon] = true
                end
            end
        end
    end
    local list = {}
    for c in pairs(found) do list[#list + 1] = c end
    table.sort(list)
    self.myProfessions = list
    return list
end

function Guild:IHaveProfession(profCanonical)
    if not profCanonical or not self.myProfessions then return false end
    for _, p in ipairs(self.myProfessions) do
        if p == profCanonical then return true end
    end
    return false
end

-- ============================================================
-- REGISTRE DE GUILDE
-- ============================================================

local ONLINE_WINDOW = 90  -- secondes : vu plus récemment que ça ⇒ "en ligne"

-- Marque un membre comme vu maintenant (présence passive), sans Refresh ni
-- écraser ses métiers connus. Appelé pour tout message reçu.
function Guild:MarkSeen(player, professions, version)
    if not player then return end
    local r = TS.db.guildRoster[player] or {}
    r.lastSeen = time()
    if professions then r.professions = professions end
    if version then
        r.version = version
        TS:NotifyIfNewerVersion(version)  -- alerte 1×/session si maj dispo
    end
    TS.db.guildRoster[player] = r
end

function Guild:UpdateRoster(player, professions, version)
    if not player then return end
    self:MarkSeen(player, professions or {}, version)
    TS:RequestRefresh()
end

-- Membres en ligne avec Guild Economy (vus dans la fenêtre récente), moi inclus en tête.
function Guild:GetOnlineUsers()
    local now, me = time(), UnitName("player") or "?"
    local out = {}
    for player, info in pairs(TS.db.guildRoster or {}) do
        if player ~= me and info.lastSeen and (now - info.lastSeen) <= ONLINE_WINDOW then
            out[#out + 1] = { player = player, professions = info.professions or {},
                              lastSeen = info.lastSeen, version = info.version }
        end
    end
    table.sort(out, function(a, b) return a.player < b.player end)
    table.insert(out, 1, { player = me, professions = self.myProfessions or {}, isSelf = true })
    return out
end

-- Liste des membres connus possédant un métier donné
function Guild:GetCraftersFor(profCanonical)
    local out = {}
    for player, info in pairs(TS.db.guildRoster or {}) do
        for _, p in ipairs(info.professions or {}) do
            if p == profCanonical then out[#out + 1] = player break end
        end
    end
    table.sort(out)
    return out
end

-- Tous les métiers connus dans la guilde (pour les onglets du panneau)
function Guild:GetKnownProfessions()
    local set = {}
    for _, info in pairs(TS.db.guildRoster or {}) do
        for _, p in ipairs(info.professions or {}) do set[p] = true end
    end
    for _, p in ipairs(self.myProfessions or {}) do set[p] = true end
    local list = {}
    for p in pairs(set) do list[#list + 1] = p end
    table.sort(list)
    return list
end

-- ============================================================
-- COMMANDES DE CRAFT
-- Deux types d'objet de commande :
--   item    : produit avec itemID (o.itemID). Nom résolu via GetItemInfo.
--   enchant : service sans objet (o.enchantID = spellID, o.enchantName = libellé).
-- Clé d'identité = "i<itemID>" ou "e<enchantID>" (dédup + matching réseau).
-- ============================================================

function Guild:OrderKey(o)
    if o.enchantID then return "e" .. o.enchantID end
    return "i" .. tostring(o.itemID or 0)
end

-- Clé à partir d'un type réseau ("I"/"E") + id
local function KeyFromKind(kind, id)
    return (kind == "E" and "e" or "i") .. tostring(id)
end

-- Nom affichable d'une commande (item localisé ou libellé d'enchant)
function Guild:OrderName(o)
    if o.enchantID then return o.enchantName or "?" end
    return TS:GetItemName(o.itemID, o.itemName or "?")
end

function Guild:FindOrder(buyer, key)
    for i, o in ipairs(TS.db.craftOrders) do
        if o.buyer == buyer and self:OrderKey(o) == key then return o, i end
    end
    return nil
end

-- Ajoute/maj une commande. fromNetwork = reçue d'un autre membre (pas de rebroadcast).
function Guild:AddOrder(o, fromNetwork)
    local existing = self:FindOrder(o.buyer, self:OrderKey(o))
    local isNew    = not existing
    if existing then
        existing.qty        = o.qty
        existing.priceValue = o.priceValue
        existing.priceText  = o.priceText
        existing.profession = o.profession
        existing.timestamp  = o.timestamp
        -- Resync CO ne transporte pas le statut : ne pas écraser "accepted" sur HI
        if not fromNetwork or existing.status ~= "accepted" then
            existing.status     = "open"
            existing.acceptedBy = nil
        end
    else
        table.insert(TS.db.craftOrders, o)
    end
    -- fromNetwork=false ⇒ commande placée par le joueur (pile de clic) ⇒ propage cross-guilde
    if not fromNetwork and TS.Net then TS.Net:BroadcastOrder(o, true) end
    -- Alerter seulement pour les nouvelles commandes, pas les resyncs HI
    if fromNetwork and isNew and self:IHaveProfession(o.profession) then self:AlertOrder(o) end
    TS:RequestRefresh()
end

-- Poste une commande d'OBJET (appelé par l'UI)
function Guild:PlaceItemOrder(itemID, qty, priceValue, priceText)
    if not itemID then return end
    local info = TS.staticItems and TS.staticItems[itemID]
    self:AddOrder({
        buyer      = UnitName("player") or "?",
        itemID     = itemID,
        qty        = qty or 1,
        priceValue = priceValue or 0,
        priceText  = priceText,
        profession = info and info.profession,
        status     = "open",
        timestamp  = time(),
    }, false)
    print("|cFF00CCFFGuild Economy|r " .. string.format(L["Order placed: %s x%d"],
        TS:GetItemName(itemID), qty or 1))
end

-- Poste une commande d'ENCHANTEMENT (service)
function Guild:PlaceEnchantOrder(enchantID, enchantName, profession, qty, priceValue, priceText)
    if not enchantID then return end
    self:AddOrder({
        buyer       = UnitName("player") or "?",
        enchantID   = enchantID,
        enchantName = enchantName,
        qty         = qty or 1,
        priceValue  = priceValue or 0,
        priceText   = priceText,
        profession  = profession,
        status      = "open",
        timestamp   = time(),
    }, false)
    print("|cFF00CCFFGuild Economy|r " .. string.format(L["Enchantment order placed: %s x%d"],
        enchantName or "?", qty or 1))
end

function Guild:CancelOrder(buyer, key, fromNetwork)
    local o, i = self:FindOrder(buyer, key)
    if i then table.remove(TS.db.craftOrders, i) end
    if not fromNetwork and TS.Net and o then
        TS.Net:BroadcastCancel(buyer, o.enchantID and "E" or "I", o.enchantID or o.itemID)
    end
    TS:RequestRefresh()
end

-- Accepte une commande : marque acceptedBy + whisper auto à l'acheteur.
function Guild:AcceptOrder(buyer, key, fromNetwork, crafter)
    local o = self:FindOrder(buyer, key)
    if not o then return end
    o.status     = "accepted"
    o.acceptedBy = crafter or (UnitName("player") or "?")
    if not fromNetwork then
        local me = UnitName("player") or "?"
        if TS.Net then
            TS.Net:BroadcastAccept(me, buyer, o.enchantID and "E" or "I", o.enchantID or o.itemID)
        end
        if buyer and buyer ~= me and ChatFrame_OpenChat then
            ChatFrame_OpenChat("/w " .. buyer .. " " .. self:OrderName(o) .. " : ")
        end
    elseif o.buyer == (UnitName("player") or "?") then
        -- C'est MA commande qu'un crafter vient d'accepter
        print("|cFF00CCFFGuild Economy|r " .. string.format(
            L["|cFF33DD33%s|r is going to fulfill your order: %s"],
            o.acceptedBy or "?", self:OrderName(o)))
        if TS.db.alertSound then PlaySound(1191) end
    end
    TS:RequestRefresh()
end

-- Valide (= livre) une commande. `delivered` = quantité livrée (nil = tout le reste,
-- ex. clic « Valider »). Si la quantité restante tombe à 0 → commande retirée PARTOUT ;
-- sinon sa quantité est décrémentée et propagée. Broadcast CF dans les deux cas.
-- localOnly = true ⇒ pas de relais GreenWall (appel hors hardware event, ex. trade auto).
function Guild:FulfillOrder(buyer, key, delivered, fromNetwork, localOnly)
    local o, i = self:FindOrder(buyer, key)
    if not o then return end
    local want = o.qty or 1
    delivered  = delivered or want      -- nil ⇒ livraison complète
    if delivered < 1 then return end
    local remaining = want - delivered
    local name = self:OrderName(o)
    if remaining > 0 then o.qty = remaining
    elseif i then table.remove(TS.db.craftOrders, i) end
    if not fromNetwork and TS.Net then
        TS.Net:BroadcastFulfill(buyer, o.enchantID and "E" or "I", o.enchantID or o.itemID, delivered, localOnly)
    end
    self:_PrintFulfill(o, buyer, name, remaining)
    TS:RequestRefresh()
end

-- Message de feedback pour les parties concernées (acheteur / crafter).
function Guild:_PrintFulfill(o, buyer, name, remaining)
    local me, p = UnitName("player") or "?", "|cFF00CCFFGuild Economy|r "
    if o.buyer == me then
        if remaining > 0 then
            print(p .. string.format(L["Partial delivery received: %s (x%d left)"], name, remaining))
        else
            print(p .. string.format(L["Order received: %s"], name))
            if TS.db.alertSound then PlaySound(1191) end
        end
    elseif o.acceptedBy == me then
        if remaining > 0 then
            print(p .. string.format(L["Partial delivery: %s to %s (x%d left)"], name, buyer, remaining))
        else
            print(p .. string.format(L["Order delivered: %s to %s"], name, buyer))
        end
    end
end

-- Ma commande ouverte correspondant à un itemID reçu (auto-validation au trade).
-- Les enchantements (services) n'ont pas d'itemID → jamais retournés.
function Guild:MyOrderForItem(itemID)
    if not itemID then return nil end
    local me = UnitName("player") or "?"
    for _, o in ipairs(TS.db.craftOrders) do
        if o.buyer == me and o.itemID == itemID then return o end
    end
    return nil
end

-- ------------------------------------------------------------------
-- Lecteurs pour l'UI
-- ------------------------------------------------------------------
function Guild:GetMyOrders()
    local me, out = UnitName("player") or "?", {}
    for _, o in ipairs(TS.db.craftOrders) do
        if o.buyer == me then out[#out + 1] = o end
    end
    return out
end

function Guild:GetOpenOrders(profCanonical)
    local out = {}
    for _, o in ipairs(TS.db.craftOrders) do
        if not profCanonical or o.profession == profCanonical then
            out[#out + 1] = o
        end
    end
    return out
end

-- ============================================================
-- ALERTE & REFRESH
-- ============================================================

function Guild:AlertOrder(o)
    print("|cFF00CCFFGuild Economy|r |cFFFFCC00>> ORDER|r " .. string.format(
        L["%s wants %s x%d (%s) — /w %s"],
        o.buyer, self:OrderName(o), o.qty or 1, o.priceText or "?", o.buyer))
    if TS.db.alertSound then PlaySound(1191) end
    if TS.Minimap then TS.Minimap:SetAlert(true) end
end

function Guild:Refresh()
    if TS.OrderPanel and TS.OrderPanel.Refresh then TS.OrderPanel:Refresh() end
    if TS.UI and TS.UI.activeTab == "orders" and TS.OrderPanel then
        TS.OrderPanel:RefreshEmbed()
    end
    if TS.ProfPanel and TS.ProfPanel.Refresh then TS.ProfPanel:Refresh() end
end

-- ============================================================
-- INIT
-- ============================================================

function Guild:Init()
    -- Scan des métiers à la connexion. Les skill lines ne sont pas toujours peuplées
    -- juste après PLAYER_LOGIN (en particulier en confédération) → on retente quelques
    -- fois tant que le scan revient vide, puis on annonce (guilde locale).
    local function tryDetect(attempt)
        self:DetectMyProfessions()
        if #(self.myProfessions or {}) == 0 and attempt < 5 then
            C_Timer.After(3, function() tryDetect(attempt + 1) end)
        elseif TS.Net then
            TS.Net:BroadcastProfessions(self.myProfessions)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function() tryDetect(1) end)
    else
        self:DetectMyProfessions()
    end
end
