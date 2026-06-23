-- Data/Professions/Enchanting.lua
-- bdd Enchantement (Classic Era / Fresh).
--
-- Pour étendre : ajoute simplement des lignes [itemID] = "Nom".
-- Les noms ne sont qu'indicatifs : l'addon résout le vrai nom localisé
-- via GetItemInfo en jeu. Garde l'itemID juste, c'est lui qui compte.

local DATA = TradeScannerData
if not DATA then return end

DATA:Register("Enchanting", {
    -- Noms du métier tels qu'affichés par GetTradeSkillLine (toutes langues utiles)
    aliases = { "Enchanting", "Enchantement", "Encantamiento", "Verzauberkunst" },

    -- ------------------------------------------------------------------
    -- MATS DE DÉSENCHANTEMENT
    -- Ce que produit le désenchantement. Quand un membre WTB l'un de ces
    -- items, l'enchanteur peut le fournir en désenchantant du stuff.
    -- ------------------------------------------------------------------
    disenchant = {
        -- Poussières
        [10940] = "Strange Dust",
        [11083] = "Soul Dust",
        [11137] = "Vision Dust",
        [11176] = "Dream Dust",
        [16204] = "Illusion Dust",
        -- Essences
        [10938] = "Lesser Magic Essence",
        [10939] = "Greater Magic Essence",
        [10998] = "Lesser Astral Essence",
        [11082] = "Greater Astral Essence",
        [11134] = "Lesser Mystic Essence",
        [11135] = "Greater Mystic Essence",
        [11174] = "Lesser Nether Essence",
        [11175] = "Greater Nether Essence",
        [16202] = "Lesser Eternal Essence",
        [16203] = "Greater Eternal Essence",
        -- Éclats
        [10978] = "Small Glimmering Shard",
        [11084] = "Large Glimmering Shard",
        [11138] = "Small Glowing Shard",
        [11139] = "Large Glowing Shard",
        [11177] = "Small Radiant Shard",
        [11178] = "Large Radiant Shard",
        [14343] = "Small Brilliant Shard",
        [14344] = "Large Brilliant Shard",
        -- Cristal
        [20725] = "Nexus Crystal",
    },

    -- ------------------------------------------------------------------
    -- PRODUITS VENDABLES (objets craftés par l'enchanteur)
    -- Complète ce que le scan trouve sur tes persos. Les enchantements purs
    -- (sans item) sont gérés via `enchants` ci-dessous (matching par texte).
    -- ------------------------------------------------------------------
    sellable = {
        -- Baguettes
        [14293] = "Lesser Magic Wand",
        [14807] = "Greater Magic Wand",
        [14809] = "Lesser Mystic Wand",
        [14810] = "Greater Mystic Wand",
        -- Tiges enchantées
        [7421]  = "Runed Copper Rod",
        [7795]  = "Runed Silver Rod",
        [13628] = "Runed Golden Rod",
        [13702] = "Runed Truesilver Rod",
        [20051] = "Runed Arcanite Rod",
        -- Huiles
        [20748] = "Brilliant Mana Oil",
        [20749] = "Brilliant Wizard Oil",
        [20750] = "Wizard Oil",
        [20747] = "Lesser Mana Oil",
        [20746] = "Lesser Wizard Oil",
        [20745] = "Minor Wizard Oil",
        [20744] = "Minor Mana Oil",
        -- Matériaux enchantés
        [17181] = "Enchanted Leather",
        [17180] = "Enchanted Thorium",
        [16207] = "Runed Arcanite Rod (mat)",
        -- Divers
        [15596] = "Smoking Heart of the Mountain",
    },

    -- ------------------------------------------------------------------
    -- ENCHANTEMENTS (services sans item)
    -- Matchés par texte dans les messages WTB (un membre tape souvent
    -- "WTB enchant 2H lesser intellect" sans lien d'objet).
    -- ------------------------------------------------------------------
    enchants = {
        "Enchant Weapon - Crusader",
        "Enchant Weapon - Lifestealing",
        "Enchant Weapon - Unholy",
        "Enchant Weapon - Mighty Intellect",
        "Enchant Weapon - Mighty Spirit",
        "Enchant Weapon - Healing Power",
        "Enchant Weapon - Spell Power",
        "Enchant Weapon - Strength",
        "Enchant Weapon - Agility",
        "Enchant 2H Weapon - Greater Impact",
        "Enchant 2H Weapon - Major Intellect",
        "Enchant 2H Weapon - Agility",
        "Enchant Chest - Greater Stats",
        "Enchant Chest - Major Health",
        "Enchant Chest - Major Mana",
        "Enchant Cloak - Greater Resistance",
        "Enchant Cloak - Superior Defense",
        "Enchant Bracer - Greater Strength",
        "Enchant Bracer - Greater Agility",
        "Enchant Bracer - Superior Stamina",
        "Enchant Bracer - Healing Power",
        "Enchant Bracer - Intellect",
        "Enchant Gloves - Greater Agility",
        "Enchant Gloves - Greater Strength",
        "Enchant Gloves - Healing Power",
        "Enchant Gloves - Fire Power",
        "Enchant Gloves - Frost Power",
        "Enchant Gloves - Shadow Power",
        "Enchant Boots - Greater Agility",
        "Enchant Boots - Greater Stamina",
        "Enchant Boots - Spirit",
        "Enchant Shield - Greater Stamina",
        "Enchant Shield - Frost Resistance",
    },
})
