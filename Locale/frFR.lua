-- Locale/frFR.lua — Traduction française de Guild Economy (TradeScanner)
if GetLocale() ~= "frFR" then return end
local L = TradeScanner.L

-- Migration des commandes (Étape E)
L["The craft ORDER system has moved to a dedicated addon:"] = "Le système de COMMANDES de craft a déménagé dans un addon dédié :"
L["Guild Economy stays your /trade + /guild offer scanner."] = "Guild Economy reste ton scanner d'offres /commerce + /guilde."

-- Chrome scanner (minimap / filtres / lignes / tooltips)
L["Filter"]                          = "Filtre"
L["Sellable"]                        = "Vendable"
L["No offers match your filters."]   = "Aucune offre ne correspond à tes filtres."
L["Left-click: open/close"]          = "Clic gauche : ouvrir/fermer"
L["Right-drag: move button"]         = "Clic droit glissé : déplacer le bouton"
L["%d craftable request(s)!"]        = "%d demande(s) réalisable(s) !"
L["Sale"]                            = "Vente"
L["Gift"]                            = "Don"
L["Wanted"]                          = "Recherche"
L[" by "]                            = " par "
L["Price: "]                         = "Prix : "
L["You can craft this item!"]        = "Tu peux fabriquer cet objet !"
L["Profession: "]                    = "Métier : "
L["Whisper "]                        = "Chuchoter à "

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
L["Validate"]                                           = "Valider"
L["Order received: %s"]                                 = "Commande reçue : %s"
L["Order delivered: %s to %s"]                          = "Commande livrée : %s à %s"
L["Partial delivery received: %s (x%d left)"]           = "Livraison partielle reçue : %s (x%d restant)"
L["Partial delivery: %s to %s (x%d left)"]              = "Livraison partielle : %s à %s (x%d restant)"
L["Validate = delivered (removes the order for everyone)"] = "Valider = livré (retire la commande pour tout le monde)"

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

-- v1.5 — Réglages (TradeScanner_Settings)
L["Settings"]                                            = "Réglages"
L["Watched channels"]                                    = "Canaux surveillés"
L["Add"]                                                 = "Ajouter"
L["Send channel:"]                                       = "Canal d'envoi :"
L["Update-notification sound"]                           = "Son d'alerte de mise à jour"
L["Scan guild chat (/g)"]                                = "Scanner le canal de guilde (/g)"
L["Cross-realm sync (GreenWall)"]                        = "Sync inter-royaume (GreenWall)"
L["Bag Alt-right-click to sell"]                         = "Alt+clic droit du sac pour vendre"
L["Debug log (chat)"]                                    = "Journal de debug (chat)"
L["Show GuildFoundMarket sales"]                         = "Afficher les ventes GuildFoundMarket"

-- v1.5 — Composeur de vente multi-item (TradeScanner_SellComposer)
L["Item"]                                                = "Objet"
L["Sell all"]                                            = "Tout vendre"
L["Clear"]                                               = "Vider"
L["Alt+right-click bag items to add them here."]         = "Alt+clic droit sur un objet du sac pour l'ajouter ici."

-- v1.5 — Tooltip sac
L["Alt + right-click: sell on the trade channel"]        = "Alt + clic droit : vendre sur le canal de commerce"

-- v1.5 — Alerte de version (TradeScanner.lua)
L["A newer version (%s) is available — you have %s."]    = "Une nouvelle version (%s) est disponible — tu as %s."

-- v1.5 — Filtres HdV (TradeScanner_UI_Categories)
L["All"]                                                 = "Toutes"
L["Any"]                                                 = "Toutes"
L["Quality"]                                             = "Qualité"
L["Level"]                                               = "Niveau"

-- v1.5 — Onglet Orders : crafters en ligne du métier (TradeScanner_OrderPanel_Rows)
L["— %s online (%d) —"]                                  = "— %s en ligne (%d) —"

-- v1.6 — Bouton/panier de vente + sélecteur de canal (UI / SellComposer)
L["Open the sell basket"]                                = "Ouvrir le panier de vente"
L["Post to:"]                                            = "Poster dans :"
L["Guild"]                                               = "Guilde"

-- v1.6 — Filtre confédération + fenêtre métier mono-bloc (Settings / ProfWindow)
L["Replace profession window"]                           = "Remplacer la fenêtre de métier"
L["Reagents:"]                                           = "Composants :"
L["Makes %s"]                                            = "Produit %s"
L["Not enough reagents."]                                = "Composants insuffisants."
L["Only show needed items"]                              = "N'afficher que les objets demandés"
L["Craft orders"]                                        = "Commandes de craft"
L["Disenchant"]                                          = "Désenchantement"
L["Sellable"]                                            = "Vendable"
L["Enchants"]                                            = "Enchantements"
L["Enchantment (service)"]                               = "Enchantement (service)"
L["Player who want this:"]                               = "Qui demande ça :"
L["Validate"]                                            = "Valider"
