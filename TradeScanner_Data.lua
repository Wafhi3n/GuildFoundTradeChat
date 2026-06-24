-- TradeScanner_Data.lua
-- Agrégateur des "bdd" métiers (Data/Professions/*.lua).
--
-- Chaque fichier de données s'enregistre dans le namespace global
-- TradeScannerData via TradeScannerData:Register("NomMétier", { ... }).
-- Ce module fusionne tout dans des tables de recherche utilisées par le core.

local TS = TradeScanner

-- Namespace global rempli par les fichiers Data/Professions/*.lua
-- (déclaré ici pour qu'il existe même si aucun fichier de données n'est chargé)
TradeScannerData = TradeScannerData or {}
local DATA = TradeScannerData

DATA.professions = DATA.professions or {}

-- ------------------------------------------------------------------
-- API d'enregistrement appelée par les fichiers de données
-- ------------------------------------------------------------------
-- def = {
--   aliases    = { "Enchanting", "Enchantement" },  -- noms localisés du métier
--   sellable   = { [itemID] = "Nom" },              -- produits vendables (craft)
--   disenchant = { [itemID] = "Nom" },              -- mats de désenchantement
--   enchants   = { "Enchant Bracer - ...", ... },   -- services (matching par texte)
-- }
function DATA:Register(profName, def)
    self.professions = self.professions or {}
    self.professions[profName] = def
end

-- ------------------------------------------------------------------
-- Fusion dans les tables de recherche du core
-- ------------------------------------------------------------------
-- Construit, à partir des fichiers de données :
--   TS.staticItems[itemID]  = { profession=, category="sellable"|"disenchant", name= }
--   TS.staticEnchants       = { { profession=, name= }, ... }  (matching texte)
--   TS.profAliases[loweralias] = profName  (résolution du métier ouvert)
function TS:LoadStaticData()
    self.staticItems        = {}
    self.staticEnchants     = {}
    self.profAliases        = {}
    self.staticByProfession = {}  -- [profCanonical] = { [itemID] = name }  (catalogue items /ts order)
    self.enchantsByProfession = {}  -- [profCanonical] = { { id=spellID, name= } }  (catalogue enchants)
    local function indexByProf(profName, itemID, name)
        local bucket = self.staticByProfession[profName]
        if not bucket then bucket = {}; self.staticByProfession[profName] = bucket end
        bucket[itemID] = name
    end

    for profName, def in pairs(DATA.professions or {}) do
        -- Alias de noms de métier (pour reconnaître la fenêtre ouverte)
        self.profAliases[profName:lower()] = profName
        if def.aliases then
            for _, alias in ipairs(def.aliases) do
                self.profAliases[alias:lower()] = profName
            end
        end

        if def.sellable then
            for itemID, name in pairs(def.sellable) do
                self.staticItems[itemID] = {
                    profession = profName,
                    category   = "sellable",
                    name       = name,
                }
                indexByProf(profName, itemID, name)
            end
        end

        if def.disenchant then
            for itemID, name in pairs(def.disenchant) do
                self.staticItems[itemID] = {
                    profession = profName,
                    category   = "disenchant",
                    name       = name,
                }
            end
        end

        if def.enchants then
            local bucket = self.enchantsByProfession[profName]
            if not bucket then bucket = {}; self.enchantsByProfession[profName] = bucket end
            for _, ench in ipairs(def.enchants) do
                -- Rétro-compat : ench peut être une chaîne (ancien format) ou { id, name }.
                local id   = (type(ench) == "table") and ench.id   or nil
                local name = (type(ench) == "table") and ench.name or ench
                table.insert(self.staticEnchants, {
                    profession = profName,
                    name       = name,
                    id         = id,
                })
                table.insert(bucket, { id = id, name = name })
            end
            table.sort(bucket, function(a, b) return a.name < b.name end)
        end
    end
end

-- Résout un nom de métier ouvert ("Enchantement") vers la clé canonique ("Enchanting")
function TS:ResolveProfession(openName)
    if not openName then return nil end
    return self.profAliases and self.profAliases[openName:lower()] or openName
end

-- Liste les mats de désenchantement connus pour un métier (clé canonique)
-- Retourne { [itemID] = name }
function TS:GetDisenchantMats(profName)
    local out = {}
    local def = DATA.professions and DATA.professions[profName]
    if def and def.disenchant then
        for itemID, name in pairs(def.disenchant) do
            out[itemID] = name
        end
    end
    return out
end
