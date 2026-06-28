-- TradeScanner_Data.lua
-- Glue mince : les données de métiers vivent désormais dans la lib CraftLink (self-contained,
-- embarquée). Ce module ne fait QUE dériver les tables de recherche du scanner Guild Economy
-- (staticItems / staticEnchants / catalogues par métier) depuis CraftLink.professions, et
-- déléguer la résolution de nom + les mats de désenchantement à la lib.
--
-- (Avant l'étape A2, ces données étaient enregistrées ici via TradeScannerData:Register ; elles
-- sont maintenant enregistrées par les fichiers Data embarqués de CraftLink via
-- CraftLink:RegisterProfession. Cf. Libs/CraftLink-1.0/Data/.)

local TS = TradeScanner
local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

local function professions()
    return (CraftLink and CraftLink.professions) or {}
end

-- ------------------------------------------------------------------
-- Fusion dans les tables de recherche du core (inchangé, source = CraftLink)
-- ------------------------------------------------------------------
--   TS.staticItems[itemID]  = { profession=, category="sellable"|"disenchant", name= }
--   TS.staticEnchants       = { { profession=, name=, id= }, ... }  (matching texte)
--   TS.profAliases[loweralias] = profName
--   TS.staticByProfession[prof][itemID]   = name
--   TS.enchantsByProfession[prof]         = { { id=, name= }, ... } (trié)
function TS:LoadStaticData()
    self.staticItems          = {}
    self.staticEnchants       = {}
    self.profAliases          = {}
    self.staticByProfession   = {}
    self.enchantsByProfession = {}
    local function indexByProf(profName, itemID, name)
        local bucket = self.staticByProfession[profName]
        if not bucket then bucket = {}; self.staticByProfession[profName] = bucket end
        bucket[itemID] = name
    end

    for profName, def in pairs(professions()) do
        self.profAliases[profName:lower()] = profName
        if def.aliases then
            for _, alias in ipairs(def.aliases) do
                self.profAliases[alias:lower()] = profName
            end
        end

        if def.sellable then
            for itemID, name in pairs(def.sellable) do
                self.staticItems[itemID] = { profession = profName, category = "sellable", name = name }
                indexByProf(profName, itemID, name)
            end
        end

        if def.disenchant then
            for itemID, name in pairs(def.disenchant) do
                self.staticItems[itemID] = { profession = profName, category = "disenchant", name = name }
            end
        end

        if def.enchants then
            local bucket = self.enchantsByProfession[profName]
            if not bucket then bucket = {}; self.enchantsByProfession[profName] = bucket end
            for _, ench in ipairs(def.enchants) do
                local id   = (type(ench) == "table") and ench.id   or nil
                local name = (type(ench) == "table") and ench.name or ench
                table.insert(self.staticEnchants, { profession = profName, name = name, id = id })
                table.insert(bucket, { id = id, name = name })
            end
            table.sort(bucket, function(a, b) return a.name < b.name end)
        end
    end
end

-- Résout un nom de métier ouvert ("Enchantement") vers la clé canonique ("Enchanting").
-- Délègue à CraftLink (source unique) ; repli sur le nom brut si la lib n'est pas chargée.
function TS:ResolveProfession(openName)
    if CraftLink then return CraftLink:ResolveProfession(openName) end
    return openName
end

-- Mats de désenchantement connus pour un métier -> { [itemID] = name }. Délègue à CraftLink.
function TS:GetDisenchantMats(profName)
    if CraftLink then return CraftLink:GetDisenchantMats(profName) end
    return {}
end
