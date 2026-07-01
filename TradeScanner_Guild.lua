-- TradeScanner_Guild.lua
-- Présence confédération (Étape F, 2026-06-30) : le craft-social (registre de métiers,
-- commandes de craft) a migré vers « Crafting Order - Classic ». Il ne reste ici que le
-- strict nécessaire pour le filtre « canal confédération seule » (#5) et l'alerte de
-- version : savoir QUI fait tourner l'addon (présence), pas ce qu'il sait crafter.

local TS    = TradeScanner
local Guild = {}
TS.Guild    = Guild

-- Marque un membre comme vu maintenant (présence passive). Appelé pour tout message
-- réseau reçu (HI/WHO/IM/OF/DN). `version`, si fourni, déclenche l'alerte de mise à jour.
function Guild:MarkSeen(player, version)
    if not player then return end
    local r = TS.db.guildRoster[player] or {}
    r.lastSeen = time()
    if version then
        r.version = version
        TS:NotifyIfNewerVersion(version)  -- alerte 1×/session si maj dispo
    end
    TS.db.guildRoster[player] = r
end

-- True si le joueur est un membre CONNU de la confédération : soi-même, ou présent dans
-- le roster Guild Economy (alimenté par tout message reçu via /g local + GreenWall).
-- Heuristique assumée : on ne "connaît" que les membres qui font tourner l'addon — c'est
-- le seul signal fiable de confédération (WoW n'expose pas la guilde d'un joueur
-- arbitraire d'un canal). Utilisé par le filtre confed des canaux surveillés (#5).
function Guild:IsConfederate(player)
    if not player or player == "" then return false end
    if player == (UnitName("player") or "") then return true end
    return (TS.db and TS.db.guildRoster and TS.db.guildRoster[player]) ~= nil
end
