-- Locale/frFR.lua — Traduction française de Guild Economy (TradeScanner)
if GetLocale() ~= "frFR" then return end
local L = TradeScanner.L

-- TradeScanner_ProfPanel
L["Re-index recipes for the open profession"]            = "Réindexer les recettes du métier ouvert"
L["Include/exclude the selected recipe"]                 = "Inclure/exclure la recette sélectionnée"
L["An excluded item will no longer appear as sellable."] = "Un item exclu ne sera plus proposé comme vendable."
L["Select a recipe first."]                              = "Sélectionne d'abord une recette."
L["%s: %d recipes indexed."]                             = "%s : %d recettes indexées."
L["Accepted by "]                                        = "Accepté par "
L["Your order — click to cancel"]                        = "Ta commande — clic = annuler"
L["Click to accept (whisper %s)"]                        = "Clic = accepter (whisper %s)"
L["No one is asking for this (yet)"]                     = "Personne ne le demande (encore)"
L["Click to whisper "]                                   = "Clic = whisper "
L["No matching requests"]                                = "Aucune demande correspondante"

-- TradeScanner_OrderPanel
L["Select an item..."]                                   = "Sélectionne un item…"
L["Qty"]                                                 = "Qté"
L["Price"]                                               = "Prix"
L["Selected: "]                                          = "Sélectionné : "
L["Select an item from the catalogue first."]            = "Sélectionne d'abord un item dans le catalogue."
L["Orders"]                                              = "Commandes"
L["— My orders —"]                                       = "— Mes commandes —"
L["— Open (%s) —"]                                       = "— Ouvertes (%s) —"
L["— Chat requests (%s) —"]                              = "— Demandes chat (%s) —"
L["— Online (%d) —"]                                     = "— En ligne (%d) —"
L["Enchantment (service)"]                               = "Enchantement (service)"

-- TradeScanner_Guild (chat messages)
L["Order placed: %s x%d"]                               = "Commande postée : %s x%d"
L["Enchantment order placed: %s x%d"]                   = "Commande d'enchantement postée : %s x%d"
L["%s wants %s x%d (%s) — /w %s"]                       = "%s veut %s x%d (%s) — /w %s"
L["|cFF33DD33%s|r is going to fulfill your order: %s"]  = "|cFF33DD33%s|r va honorer ta commande : %s"

-- TradeScanner_BagSell (popup WTS depuis le sac)
L["Sell to Guild Economy"]                               = "Vendre sur Guild Economy"
L["Note"]                                                = "Note"
L["Sell"]                                                = "Vendre"
L["Cancel"]                                              = "Annuler"
L["Not connected to the trade channel. Channel to join:"] = "Pas connecté au canal de commerce. Canal à rejoindre :"
L["Join"]                                                = "Rejoindre"
L["Could not join channel '%s'."]                        = "Impossible de rejoindre le canal « %s »."

-- TradeScanner_UI
L["Manual sellable (click to remove)"]                   = "Vendable manuel (clic = retirer)"
L["(empty)"]                                             = "(vide)"
L["Shift-click an item or enter an item ID."]            = "Shift-clic un objet dans le champ, ou tape un itemID."
L["Sellable+: "]                                         = "Vendable + : "
