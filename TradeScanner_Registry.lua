-- TradeScanner_Registry.lua
-- Glue mince : le registre « MES recettes » (scan, état, codec RK) vit dans CraftLink
-- (CraftLink_Recipes.lua) → Guild Economy et Crafting Order le partagent. Ce module ne garde
-- que ce qui est SPÉCIFIQUE à Guild Economy :
--   * persistance de mon registre dans TradeScannerDB (Load/Save union via la lib) ;
--   * le ROSTER des AUTRES (qui sait quoi), couplé au guildRoster (présence/métiers) — c'est de
--     l'annuaire, il migrera dans le transport/Directory à l'étape B ;
--   * la porte d'alerte de commande (ShouldAlertForOrder, logique guilde) ;
--   * la diffusion RK via le transport guilde existant (TS.Net).

local TS  = TradeScanner
local Reg = {}
TS.Registry = Reg

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

-- ------------------------------------------------------------------
-- Init : charge mon registre persistant dans la lib (union)
-- ------------------------------------------------------------------
function Reg:Init()
    if not CraftLink then
        print("|cFFFF4444Guild Economy|r CraftLink introuvable — registre de recettes désactivé.")
        return
    end
    TS.db.knownRecipes = TS.db.knownRecipes or {}   -- [prof] = { [spellID] = true } (le mien, miroir SV)
    TS.db.guildRoster  = TS.db.guildRoster  or {}   -- [player] = { recipes={prof=hex}, recipeDV, professions }
    CraftLink:LoadMyRecipes(TS.db.knownRecipes)
end

-- Scan de la fenêtre ouverte → union dans la lib ; si nouveauté : miroir SV + diffusion.
function Reg:ScanOpen()
    if not CraftLink then return end
    local prof, changed = CraftLink:ScanOpenKnown()
    if changed and prof then
        CraftLink:SaveMyRecipes(TS.db.knownRecipes)
        self:BroadcastProf(prof)
    end
end

-- ------------------------------------------------------------------
-- Requêtes (moi) — délèguent à la lib
-- ------------------------------------------------------------------
function Reg:Summary()           return CraftLink and CraftLink:RecipeSummary() or {} end
function Reg:MyKnownSet(prof)    return CraftLink and CraftLink:MyKnownSet(prof) end
function Reg:MyHex(prof)         return CraftLink and CraftLink:MyHex(prof) end

-- Faut-il m'alerter pour une commande reçue ? Précision #2 : si j'ai déjà scanné ce métier,
-- on n'alerte que si je connais LA recette ; sinon (jamais scanné) comportement historique large.
function Reg:ShouldAlertForOrder(prof, itemID, enchantID)
    if not (TS.Guild and TS.Guild:IHaveProfession(prof)) then return false end
    if not (CraftLink and CraftLink:MyKnownSet(prof)) then return true end
    if enchantID then return CraftLink:IKnowRecipeBySpell(prof, enchantID) end
    if itemID    then return CraftLink:IKnowRecipeForItem(prof, itemID) end
    return true
end

-- ------------------------------------------------------------------
-- Roster (AUTRES) : stockage compact (hex) + requêtes single-bit. Lit guildRoster.
-- ------------------------------------------------------------------
function Reg:StoreRemote(player, prof, hex, dataVersion)
    if not player or not prof then return end
    local r = TS.db.guildRoster[player]
    if not r then r = {}; TS.db.guildRoster[player] = r end
    r.recipes       = r.recipes or {}
    r.recipes[prof] = hex
    r.recipeDV      = dataVersion
end

-- État tri-état d'une recette chez un membre : true / false / nil (RK absent ou index de bits
-- incompatible). On ne déduit JAMAIS « ne connaît pas » d'une dataVersion divergente → nil.
local function remoteState(r, prof, spellID, myDV)
    if not (r and r.recipes and r.recipes[prof]) then return nil end
    if r.recipeDV ~= myDV then return nil end
    return CraftLink:HasBit(prof, r.recipes[prof], spellID)
end

function Reg:WhoKnowsRecipe(prof, spellID)
    if not CraftLink then return {} end
    local out, me, myDV = {}, UnitName("player") or "?", CraftLink:DataVersion()
    if CraftLink:IKnowRecipeBySpell(prof, spellID) then out[#out + 1] = me end
    for player, r in pairs(TS.db.guildRoster or {}) do
        if player ~= me and remoteState(r, prof, spellID, myDV) == true then out[#out + 1] = player end
    end
    table.sort(out)
    return out
end

-- Qui connaît la recette produisant cet itemID (via repli itemToSpell) ? nil si non mappé.
function Reg:WhoKnowsItem(prof, itemID)
    if not CraftLink then return nil end
    local i2s = CraftLink:ItemToSpell(prof)
    local sid = i2s and i2s[itemID]
    if not sid then return nil end
    return self:WhoKnowsRecipe(prof, sid)
end

-- Détenteurs du métier dont on est SÛR qu'ils n'ont pas la recette (drop de plan #1).
function Reg:WhoIsMissingRecipe(prof, spellID)
    if not CraftLink then return {} end
    local out, me, myDV = {}, UnitName("player") or "?", CraftLink:DataVersion()
    if TS.Guild and TS.Guild:IHaveProfession(prof) and not CraftLink:IKnowRecipeBySpell(prof, spellID) then
        out[#out + 1] = me
    end
    for player, r in pairs(TS.db.guildRoster or {}) do
        if player ~= me then
            local hasProf = false
            for _, p in ipairs(r.professions or {}) do if p == prof then hasProf = true; break end end
            if hasProf and remoteState(r, prof, spellID, myDV) == false then out[#out + 1] = player end
        end
    end
    table.sort(out)
    return out
end

-- ------------------------------------------------------------------
-- Diffusion (RK) — délègue le format à la lib, l'envoi au transport guilde existant
-- ------------------------------------------------------------------
function Reg:BroadcastProf(prof)
    if not (CraftLink and TS.Net) then return end
    local msg = CraftLink:BuildRK(prof)
    if msg then TS.Net:Send(msg) end
end

function Reg:BroadcastAll()
    if not CraftLink then return end
    for _, prof in ipairs(CraftLink:MyProfessions()) do self:BroadcastProf(prof) end
end

-- Réception (délégué par TradeScanner_Network) : parse via la lib + stockage roster local.
function Reg:OnNetwork(player, message)
    if not CraftLink then return end
    local prof, hex, dv = CraftLink:ParseRK(message)
    if prof then self:StoreRemote(player, prof, hex, dv) end
end
