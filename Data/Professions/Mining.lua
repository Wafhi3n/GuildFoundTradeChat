-- Data/Professions/Mining.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local DATA = TradeScannerData
if not DATA then return end

DATA:Register("Mining", {
    aliases = { "Mining", "Minage", "Bergbau", "Minería" },

    sellable = {
        [2840] = "Smelt Copper",
        [2841] = "Smelt Bronze",
        [2842] = "Smelt Silver",
        [3575] = "Smelt Iron",
        [3576] = "Smelt Tin",
        [3577] = "Smelt Gold",
        [3859] = "Smelt Steel",
        [3860] = "Smelt Mithril",
        [6037] = "Smelt Truesilver",
        [11371] = "Smelt Dark Iron",
        [12359] = "Smelt Thorium",
        [17771] = "Smelt Elementium",
    },
})
