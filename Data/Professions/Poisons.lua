-- Data/Professions/Poisons.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local DATA = TradeScannerData
if not DATA then return end

DATA:Register("Poisons", {
    aliases = { "Poisons", "Gifte", "Venenos" },

    sellable = {
        [2892] = "Deadly Poison",
        [2893] = "Deadly Poison II",
        [3775] = "Crippling Poison",
        [3776] = "Crippling Poison II",
        [5237] = "Mind-numbing Poison",
        [5530] = "Blinding Powder",
        [6947] = "Instant Poison",
        [6949] = "Instant Poison II",
        [6950] = "Instant Poison III",
        [6951] = "Mind-numbing Poison II",
        [8926] = "Instant Poison IV",
        [8927] = "Instant Poison V",
        [8928] = "Instant Poison VI",
        [8984] = "Deadly Poison III",
        [8985] = "Deadly Poison IV",
        [9186] = "Mind-numbing Poison III",
        [10918] = "Wound Poison",
        [10920] = "Wound Poison II",
        [10921] = "Wound Poison III",
        [10922] = "Wound Poison IV",
        [21302] = "Deadly Poison V",
    },
})
