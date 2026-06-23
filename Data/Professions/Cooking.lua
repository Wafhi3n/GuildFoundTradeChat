-- Data/Professions/Cooking.lua
-- bdd Cuisine (Classic Era / Fresh).
-- Modèle plus léger : pas de désenchantement, uniquement des produits vendables.

local DATA = TradeScannerData
if not DATA then return end

DATA:Register("Cooking", {
    aliases = { "Cooking", "Cuisine", "Cocina", "Kochkunst" },

    -- Plats les plus demandés / vendables (buffs de raid surtout)
    sellable = {
        [13931]  = "Nightfin Soup",
        [13928]  = "Grilled Squid",
        [13927]  = "Hot Wolf Ribs",
        [13934]  = "Sagefish Delight",
        [13933]  = "Mightfish Steak",
        [18045]  = "Tender Wolf Steak",
        [20452]  = "Smoked Desert Dumplings",
        [21023]  = "Dirge's Kickin' Chimaerok Chops",
        [13813]  = "Blessed Sunfruit Juice",
        [13810]  = "Blessed Sunfruit",
        [13923]  = "Spotted Yellowtail",
        [13930]  = "Spiced Chili Crab",
        [21072]  = "Skin of Dwarven Stout",
        [12217]  = "Dragonbreath Chili",
        [12218]  = "Monster Omelet",
        [8932]   = "Alterac Swiss",
    },
})
