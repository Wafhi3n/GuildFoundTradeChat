-- Data/Professions/FirstAid.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local DATA = TradeScannerData
if not DATA then return end

DATA:Register("First Aid", {
    aliases = { "First Aid", "Secourisme", "Erste Hilfe", "Primeros auxilios" },

    sellable = {
        [1251] = "Linen Bandage",
        [2581] = "Heavy Linen Bandage",
        [3530] = "Wool Bandage",
        [3531] = "Heavy Wool Bandage",
        [6450] = "Silk Bandage",
        [6452] = "Anti-Venom",
        [6454] = "Strong Anti-Venom",
        [8545] = "Heavy Mageweave Bandage",
        [14529] = "Runecloth Bandage",
        [14530] = "Heavy Runecloth Bandage",
        [16112] = "Heavy Silk Bandage",
        [16113] = "Mageweave Bandage",
        [19442] = "Powerful Anti-Venom",
    },
})
