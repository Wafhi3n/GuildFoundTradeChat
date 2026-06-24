# tools/ — outils de build (NON packagés)

Ce dossier contient la chaîne de génération de la base de métiers statique
(`Data/Professions/*.lua`). **Rien ici n'est chargé en jeu** — c'est exclu du package
CurseForge via `.pkgmeta`.

## Fichiers

- `gen_professions.lua` — convertisseur hors-ligne. Lit la base de
  [MissingTradeSkillsList](https://www.curseforge.com/wow/addons/missing-tradeskills-list)
  (déjà installée dans le dossier AddOns) + `wowhead_map.lua`, et écrit les
  `Data/Professions/<Métier>.lua` au format `TradeScannerData:Register(...)`.
- `wowhead_map.lua` — table `[spellID] = itemID produit`, extraite de Wowhead Classic.
  C'est la pièce qui manque dans MTSL (MTSL liste toutes les recettes par spellID mais ne
  donne l'itemID produit que pour une partie d'entre elles).

## Régénérer la base

```powershell
cd f:\AddonDevellopement\TradeScanner
& "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_professions.lua
```

Vérifier le résultat : `.\deploy.ps1` n'est pas nécessaire ; lancer la validation Lua via
le skill `ts-deploy` (qui fait `luac -p` sur tout).

## Régénérer `wowhead_map.lua` (rare — seulement si de nouvelles recettes Classic)

La map vient des pages Wowhead Classic « spells/professions » (le tableau JS embarqué
contient `"creates":[itemID,_,_],"id":spellID`) :

1. Récupérer chaque page :
   `https://www.wowhead.com/classic/spells/professions/{alchemy,blacksmithing,enchanting,engineering,leatherworking,tailoring,mining}`
   (cooking / first-aid / poisons n'ont pas de page filtrée → utiliser les pages de sort
   individuelles `https://www.wowhead.com/classic/spell=<id>` pour les recettes manquantes).
2. Extraire les paires `"creates":\[(\d+),\d+,\d+\],"id":(\d+)` (adjacence fiable).
3. Fusionner en `[spellID]=itemID` triés.

## Sources / attribution

Données = faits de jeu (recette → objet produit). Merci à **MissingTradeSkillsList**
(Thumbkin) pour la liste exhaustive des recettes, et à **Wowhead Classic** pour le
mapping spellID → itemID.
