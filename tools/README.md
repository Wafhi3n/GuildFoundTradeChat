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

## Multi-versions (Vanilla / SOD / TBC / WotLK) — à générer

Les données vivent désormais dans la lib **CraftLink** : `CraftLink-1.0/Data/<flavor>/*.lua`
(+ un `Data/<flavor>.xml` par saveur, inclus par le `.toc` flavor de chaque addon).

- **Vanilla** = `Data/Vanilla/` — **FIGÉ, source MTSL** (dataVersion `1792301894` déjà déployée).
  NE PAS régénérer autrement : changer le set/ordre des recettes change la dataVersion et
  **invalide les bitfields de registre** déjà diffusés chez les joueurs.
- **SOD / TBC / WotLK** = à générer depuis **Wowhead par métier** (meilleure source multi-versions :
  spellID **et** itemID produit sur la même page, + tag SOD sur la colonne « saison ») :

  | Saveur | Domaine Wowhead | Cap | URL type (Alchimie `skill=171`) |
  |---|---|---|---|
  | Vanilla | `classic` (lignes SANS tag Season) | 300 | `wowhead.com/classic/fr/skill=171/...#recipes` |
  | SOD     | `classic` (lignes avec colonne **Season** = `SoD`) | 300 | même page `classic` |
  | TBC     | `tbc`   | 375 | `wowhead.com/tbc/fr/skill=171/...#crafted-items`  |
  | WotLK   | `wotlk` | 450 | `wowhead.com/wotlk/fr/skill=171/...#crafted-items` |

  Sur la page `classic`, l'onglet **Recipes** a une colonne **Season** : vide = vanilla de base,
  `SoD` (+ `Phase N`) = recette SoD. Ex. Alchimie : 133 recettes (vanilla 111 + ~22 SoD).
  NB : la colonne **Skill** peut afficher des paliers > 300 (315/322/330) — c'est Wowhead qui montre
  les valeurs cross-version (TBC) ; **le cap réel en Classic/SoD reste 300**.

  IDs de métier (`skill=`) : Alchemy 171, Blacksmithing 164, Enchanting 333, Engineering 202,
  Leatherworking 165, Tailoring 197, Cooking 185, First Aid 129, Mining 186, Poisons 40,
  Jewelcrafting 755 (TBC+), Inscription 773 (WotLK+).

  Méthode (VÉRIFIÉE 2026-06-27) : pour chaque `(domaine, skillID)`, récupérer le **HTML brut** via
  `curl -A "<UA navigateur>" "https://www.wowhead.com/<domaine>/skill=<id>/<prof>"` (PAS WebFetch :
  il convertit en markdown et jette la table JS). La page contient un `new Listview({...id:'spells'
  /'crafted-items'...})` dont le tableau `data:[...]` liste les recettes :
  `{"id":spellID, "creates":[itemID,_,_], "reagents":[[itemID,qty],...], "skill":[171],
    "learnedat":N, "seasonId":2?, "phaseId":N?}`.
  - `creates[1]` = itemID produit ; `id` = spellID → `recipes` + `itemToSpell`.
  - **SoD** : recette taggée `"seasonId":2` (+ `"phaseId":N`). Vanilla = SANS `seasonId`.
    (Alchimie : 133 recettes, dont 48 `seasonId:2` réparties P1/2/3/6/8.)
  - ⚠️ Réconciliation : Wowhead « non-SoD » (85 pour Alchimie) ≠ MTSL vanilla (111) — périmètres
    différents (transmutes, recettes sans item, etc.). Au moment de générer, croiser les sources
    et **ne pas écraser le Vanilla MTSL figé** (dataVersion 1792301894) ; n'ajouter que les couches
    SoD/TBC/WotLK. Format de sortie : `CraftLink:RegisterProfession(<prof>, { recipes={...},
    itemToSpell={...}, ... })`, un fichier par `(flavor, métier)`.

## Sources / attribution

Données = faits de jeu (recette → objet produit). Merci à **MissingTradeSkillsList**
(Thumbkin) pour la liste exhaustive des recettes Vanilla, et à **Wowhead** (Classic/TBC/WotLK)
pour le mapping spellID → itemID et les jeux de recettes par version.
