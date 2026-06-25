# Intégration GreenWall — guide pour Guild Economy (TradeScanner)

> Référence interne. Source analysée : `GreenWall/API.lua`, `Channel.lua`, `Constants.lua`,
> `Globals.lua`, `Utility.lua` (version GreenWall avec `GreenWallAPI.version == 1`).
> Voir aussi `GreenWall/API.md` (doc officielle, courte) et le module `TradeScanner_Network.lua`.

GreenWall relie plusieurs guildes (« co-guildes » d'une *confédération*) en pontant leur
chat de guilde sur un **canal de chat caché partagé**. Depuis la v1.7, il expose une petite
API (`GreenWallAPI`) qui permet à un addon tiers d'utiliser ce pont comme **transport
cross-guilde / cross-serveur** pour ses propres messages.

C'est exactement ce dont Guild Economy se sert pour propager les commandes de craft
(`CO`/`CC`/`CA`) à toute la confédération, là où `C_ChatInfo.SendAddonMessage("GUILD")`
ne touche que notre propre guilde.

---

## 1. Le modèle en une image

```
  Guild Economy (moi)                    GreenWall                 Guild Economy (co-guilde)
  ───────────────────                    ─────────                 ────────────────────────
  NET:SendConfederation(payload)
        │
        └─ GreenWallAPI.SendMessage("TradeScanner", payload)
                 │  base64 + entête, 1 segment ≤ 255 c.
                 └─ SendChatMessage(..., "CHANNEL", canal caché)  ──►  canal confédération
                                                                            │
                              gw.APIDispatcher(addon, sender, guild_id, msg)│ (à la réception)
                                                                            ▼
                                          handler(addon, sender, message, echo, guild)
                                                                            │
                                          NET:HandleMessage(sender, message)│
```

Points structurants à retenir :

- **Le transport, c'est du chat.** GreenWall encode le message et l'envoie via
  `SendChatMessage(segment, "CHANNEL", nil, number)` sur le canal caché de la confédération.
- **`SendChatMessage` est une fonction protégée** (partiellement protégée depuis le patch 8.2.5,
  cf. `GreenWall/CHANGELOG.md`). ⇒ **un envoi ne réussit que dans la pile d'un *hardware event*.**
- Côté réception, **le trafic API est dispatché quel que soit l'expéditeur** — y compris
  *nos propres messages* (echo) et ceux de *notre propre guilde* (guild). À nous de filtrer.

---

## 2. L'API publique (`GreenWallAPI`)

| Fonction | Signature | Rôle |
|---|---|---|
| `version` | champ (== `1`) | version de l'API |
| `SendMessage` | `(addon, message)` | envoie un message à toute la confédération |
| `AddMessageHandler` | `(handler, addon, priority) → id` | enregistre un callback de réception |
| `RemoveMessageHandler` | `(id) → bool` | retire un handler par son id |
| `ClearMessageHandlers` | `(addon?)` | vide les handlers (d'un addon, de `'*'`, ou tous si `nil`) |
| `GetChannelNumbers` | `() → { number, … }` | numéros des canaux cachés (guild + officer) |

- **`addon`** doit être **exactement** le nom du `.toc` (ici `"TradeScanner"`).
  `SendMessage`/`AddMessageHandler` valident via `assert(addon == GetAddOnInfo(addon))` :
  un mauvais nom **lève une erreur Lua** (d'où l'usage de `pcall` côté Guild Economy).
- **`message`** accepte des données 8-bit (encodage base64 interne) → notre protocole
  pipe-délimité passe sans souci, mais attention à la **taille** (cf. §5).

### Détection / disponibilité (à faire AVANT tout appel)

```lua
local function GreenWallReady()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded("GreenWall")) then return false end
    return type(GreenWallAPI) == "table"
       and (GreenWallAPI.version or 0) >= 1
       and type(GreenWallAPI.SendMessage) == "function"
end
```

⚠️ **L'API n'est pas prête au `PLAYER_LOGIN`.** GreenWall doit d'abord rejoindre le canal
caché et charger sa config — ça prend plusieurs secondes après l'entrée en jeu. Il faut donc
**réessayer l'enregistrement du handler** jusqu'à ce que l'API réponde (Guild Economy
réessaie toutes les 5 s, ~12 fois ≈ 1 min : voir `NET:RegisterGreenWall`).

---

## 3. Envoyer — `GreenWallAPI.SendMessage(addon, message)`

```lua
GreenWallAPI.SendMessage("TradeScanner", payload)   -- toujours sous pcall
```

### ⛔ La contrainte n°1 : *hardware event*

Comme l'envoi finit en `SendChatMessage` (protégé), **on ne peut l'appeler que pendant le
traitement d'une action matérielle du joueur** : clic souris, appui touche. Sinon le client
refuse et déclenche `ADDON_ACTION_BLOCKED` (popup « Interface action failed because of an
AddOn »).

**Conséquence de design (déjà appliquée dans Guild Economy) :**

| Trafic | Déclencheur | Transport |
|---|---|---|
| `HI`, `OF`, `DN`, `PR`, `IM` | timer / event / réception réseau | **guilde locale uniquement** (`SendAddonMessage`) |
| `WHO` (présence) | clic, **mais gardé local** | **guilde locale uniquement** (cf. §8) |
| `CO` (placement) | clic sur *Order* | local **+** confédération |
| `CC` / `CA` | clic sur *Cancel* / *Accept* | local **+** confédération |
| `CF` (livraison) | clic / auto-trade | local **+** confédération (sauf `localOnly`) |

> Règle pratique : **ne jamais router vers `SendConfederation` un message issu d'un timer,
> d'un `OnEvent` ou d'un handler de réception réseau.** Si l'envoi cross-guilde doit suivre une
> réception (ex. répondre à un `HI` ou à un `WHO`), il restera bloqué — c'est pourquoi
> `HI`/`OF`/`DN`/`PR`/`IM` ne partent qu'en local.
>
> **`WHO` est lui aussi gardé local** alors qu'il part d'un clic : sa réponse `IM` ne pouvant
> pas traverser GreenWall (émise depuis un handler de réception), un `WHO` confédéral ne ferait
> qu'amplifier le trafic des guildes sœurs sans bénéfice pour l'émetteur (cf. §8). Le seul push
> cross-guilde provient donc des **commandes** (`CO`/`CC`/`CA`/`CF`), toutes déclenchées par un clic.

### Pas d'envoi fiable hors-combat non plus

Même dans un *hardware event*, `SendChatMessage` peut être restreint en combat. Pour du trafic
non critique, ne pas s'acharner : encapsuler dans `pcall` (déjà fait) et accepter la perte.

---

## 4. Recevoir — `AddMessageHandler(handler, addon, priority)`

```lua
local id = GreenWallAPI.AddMessageHandler(function(addon, sender, message, echo, guild)
    if echo or guild then return end          -- (voir ci-dessous)
    NET:HandleMessage(sender, message)
end, "TradeScanner", 0)
```

Le handler reçoit **5 arguments** :

| Arg | Contenu | Remarque |
|---|---|---|
| `addon` | nom de l'addon émetteur | filtré en amont (on s'abonne à `"TradeScanner"`) |
| `sender` | **`Nom-Royaume`** (qualifié royaume, via `gw.GlobalName`) | ⚠️ pas juste `Nom` |
| `message` | le payload tel qu'envoyé | notre chaîne pipe-délimitée |
| `echo` | `true` si **c'est mon propre message** (`sender == gw.player`) | à ignorer |
| `guild` | `true` si le message vient de **ma propre co-guilde** | à ignorer |

### Pourquoi filtrer `echo` et `guild`

- `echo` : la confédération me **renvoie mes propres envois** (l'API dispatche « regardless of
  the sender »). Sans filtre → je traiterais mes propres commandes en double.
- `guild` : un membre de **ma** guilde qui poste une commande, je le reçois **deux fois** :
  une fois par le canal addon local (`CHAT_MSG_ADDON` "GUILD") **et** une fois par GreenWall
  (`guild == true`). On garde la version locale (plus fiable, pas de troncature) et on jette
  la copie GreenWall.
- ⇒ **Le handler GreenWall ne traite donc QUE les guildes *sœurs*** (autres co-guildes).
  C'est exactement ce que fait `NET:RegisterGreenWall`.

### `sender` est qualifié royaume

`sender` vaut p.ex. `"Tartempion-Sulfuron"`. Tout matching par nom de joueur doit retirer le
royaume. Guild Economy le fait déjà via `GetPlayerShort` :

```lua
local function GetPlayerShort(fullName)
    return fullName and (fullName:match("^([^%-]+)") or fullName)
end
```

### Cycle de vie du handler

- `AddMessageHandler` renvoie un **id** (string) à conserver si on veut le retirer plus tard.
- Ne l'enregistrer **qu'une seule fois** (Guild Economy garde un flag `self.gwRegistered`).
  Un re-`/reload` recrée tout l'environnement Lua, donc pas de fuite entre sessions ; mais
  dans une même session, éviter les doublons d'enregistrement.
- `priority` : entier signé, **plus petit = traité en premier**. `0` convient.

---

## 5. Taille des messages — **plafond bas + troncature silencieuse**

C'est le piège le moins visible. Détail du format on-wire d'un message API :

```
segment = "E" .. "#" .. guild_id .. "#" .. "" .. "#" .. ( addon .. ":" .. base64(payload) )
segment = strsub(segment, 1, GW_MAX_MESSAGE_LENGTH)      -- GW_MAX_MESSAGE_LENGTH = 255
```

Deux faits importants :

1. **Les messages API ne sont PAS fragmentés.** Contrairement au chat ponté, un message
   `EXTERNAL` part en **un seul segment** et est **tronqué brutalement à 255 caractères**.
   Au-delà → la fin est perdue **sans erreur ni avertissement** (le base64 tronqué se décodera
   en données corrompues côté réception).
2. **base64 gonfle le payload de ~33 %** et l'entête consomme déjà :
   `"E#" + guild_id + "##" + "TradeScanner" + ":"` ≈ **20 à 60 caractères** selon la longueur
   de `guild_id` (dépend de la config de la confédération).

**Budget utile approximatif :**

```
payload_max ≈ ( 255 − 5 − len(guild_id) − len("TradeScanner") ) × 3/4
            ≈ 130 à 165 octets de payload réel
```

> 👉 **Règle de sécurité : garder chaque payload cross-guilde ≤ 128 octets.** Nos commandes
> (`CO|buyer|kind|id|qty|pv|ptext|prof|name`) tiennent largement, **sauf** si `name` (libellé
> d'enchant) ou `ptext` sont longs. Un `Enchant Weapon - Crusader` + prix verbeux peut
> approcher la limite une fois base64-é. Si on ajoute des champs au protocole, **mesurer**.
> Ne jamais compter sur les « 255 caractères » bruts : le budget réel est ~moitié.

---

## 6. Récapitulatif des pièges (checklist d'intégration)

- [ ] **Détecter l'API** avant tout appel (`IsAddOnLoaded` + `GreenWallAPI` + `version >= 1`).
- [ ] **Réessayer l'enregistrement** du handler après login (l'API met du temps à être prête).
- [ ] **`pcall`** autour de `SendMessage`/`AddMessageHandler` (asserts internes + protection).
- [ ] **N'envoyer que dans un *hardware event*** (clic/touche), jamais depuis timer/OnEvent/réception.
- [ ] **Filtrer `echo` ET `guild`** dans le handler (sinon doublons).
- [ ] **Déqualifier `sender`** (`Nom-Royaume` → `Nom`) pour tout matching joueur.
- [ ] **Payload ≤ ~128 octets** (troncature silencieuse à 255 c. après base64 + entête).
- [ ] Nom d'addon **identique au `.toc`** dans `SendMessage` et `AddMessageHandler`.
- [ ] Prévoir le **mode dégradé** : GreenWall absent ou désactivé ⇒ l'addon doit fonctionner
      en guilde locale seule (option `db.useGreenWall`, commande `/ts confed`).

---

## 7. Comment Guild Economy l'utilise aujourd'hui (mapping)

| Besoin | Code | Conforme ? |
|---|---|---|
| Détection + retry d'enregistrement | `NET:RegisterGreenWall(attempt)` | ✅ retry 5 s × 12 |
| Envoi cross-guilde | `NET:SendConfederation(payload)` | ✅ `pcall`, garde `useGreenWall`, n'est appelé que sur clics (CO/CC/CA/CF) |
| Filtrage echo/guild | handler dans `RegisterGreenWall` | ✅ `if echo or guild then return end` |
| Déqualification royaume | `GetPlayerShort` | ✅ |
| Mode dégradé | `db.useGreenWall`, `/ts confed` | ✅ |
| Debug | `db.gwDebug`, `/ts gwdebug` → `[GW→]` / `[GW←]` | ✅ |

### Pistes d'amélioration (optionnelles)

- **Vérifier `GreenWallAPI.version >= 1`** explicitement dans `RegisterGreenWall`/`SendConfederation`
  (actuellement on teste seulement la présence des fonctions — suffisant en pratique, mais la
  version protège contre une future API incompatible).
- **Garde de taille** avant `SendConfederation` : si `#payload` (après base64 ≈ `#payload*4/3`)
  risque de dépasser ~200 c., tronquer proprement ou logguer plutôt que laisser GreenWall couper
  au milieu d'un champ. Pertinent surtout pour les `CO` avec long `enchantName`.
- **Retirer le handler** via `RemoveMessageHandler(id)` n'est pas nécessaire (durée de vie =
  session), mais conserver l'`id` retourné ne coûte rien si un jour on veut un *toggle* à chaud.

---

## 8. Charge à l'échelle (confédération de plusieurs guildes de ~1000)

Contexte cible : **~12 co-guildes de ~1000 membres**. Le point clé tient en une phrase :

> **Le trafic de présence/sync ne dépend PAS de la population totale de la confédération,
> mais du nombre d'utilisateurs de l'addon dans UNE guilde.** `HI`, `OF`, `DN`, `PR`, `IM`,
> `WHO` sont tous **guilde-locaux** ; seules les **commandes** (`CO`/`CC`/`CA`/`CF`) traversent
> GreenWall. Garder la présence locale est la décision qui évite l'explosion en O(12 000).

### Là où ça peut quand même chauffer

| Risque | Mécanisme | Échelle |
|---|---|---|
| **Tempête de resync au login** | À chaque `HI` (login), **chaque** membre répondait en rebroadcastant **toute** la liste de commandes connue (jusqu'à `MAX_OFFERS`=50). | O(k_guilde × liste) par login ; logins quasi continus dans une guilde de 1000 |
| **Amplification `WHO`** | Un `WHO` confédéral faisait répondre les 11 autres guildes en `IM`… dans **leur** propre canal, invisibles pour l'émetteur. | O(guildes × k) d'`IM` inutiles par clic |
| **Rebuild UI par message** | `UI:Refresh()` (fenêtre d'offres) ne testait pas `IsShown` → rebuild complet à **chaque** `OF`/`DN` reçu, même fenêtre fermée. | O(messages) de rebuilds pendant un burst |

### Correctifs appliqués

1. **Resync `HI` = mes commandes seulement.** `NET:SendAllOrdersDelayed` ne rebroadcast plus que
   les commandes dont je suis l'auteur (`o.buyer == moi`), à l'image de `BroadcastOffer` qui
   ignore déjà les offres `source=="network"`. La réponse à un `HI` passe de O(k×50) à
   O(k×mes_commandes). *Contrepartie : une commande dont l'auteur est hors-ligne ne resync qu'à
   son prochain login — acceptable, le statut n'était de toute façon pas porté par le resync `CO`.*
2. **`WHO` gardé local.** Suppression du `SendConfederation("WHO")` dans `NET:BroadcastWho`.
   La présence cross-guilde via `WHO` était structurellement inutile (l'`IM` ne revient pas).
3. **Refresh d'UI coalescé + gardé.** `TS:RequestRefresh()` (core) regroupe les rafales en **un
   seul** rebuild après 0,2 s et ne touche la fenêtre d'offres **que si visible**. Tous les
   chemins de réception réseau (`AddOffer`, `MarkDone`, `AddOrder`, `UpdateRoster`,
   `Cancel`/`Accept`/`FulfillOrder`) passent désormais par lui : un burst de N messages = 1 rebuild.

### Leviers restants (non appliqués — à discuter)

- **TTL sur les commandes.** `db.craftOrders` n'expire pas (contrairement aux offres,
  `OFFER_EXPIRY`=30 min). La livraison `CF` en retire, mais une commande jamais livrée reste
  indéfiniment et regonfle la resync. → purger au-delà de X jours au chargement.
- **ChatThrottleLib.** Les envois staggered utilisent `C_ChatInfo.SendAddonMessage` brut à
  `OFFER_TICK`=0,1 s (10 msg/s). À forte charge, le throttle interne de Blizzard peut **dropper
  silencieusement** des messages (resync incomplète) — coopérer via CTL serait plus sûr.
- **Jitter des réponses.** Tous les répondeurs à un `HI` démarrent leur ticker au même instant
  avec la même cadence → réponses alignées en burst. Un délai initial aléatoire (ex.
  `math.random()*2` s) étalerait la charge ; idem, déduper des `HI` rapprochés éviterait des
  tickers de resync concurrents.

---

## 9. Annexe — chemin de code GreenWall (pour référence)

- **Envoi** : `GreenWallAPI.SendMessage` → `gw.config.channel.guild:send(GW_MTYPE_EXTERNAL, addon, message)`
  → `al_encode` (`addon .. ":" .. base64(message)`) → `tl_send` (préfixe `E#guild_id##…`, **strsub 255**)
  → `tl_flush` → `SendChatMessage(segment, "CHANNEL", nil, number)`.  *(Channel.lua:266-367)*
- **Réception** : event chat sur le canal caché → `GwChannel:receive` → `sender = gw.GlobalName(sender)`
  → si `GW_MTYPE_EXTERNAL` : `al_decode` (base64) → `gw.APIDispatcher(addon, sender, guild_id, api_message)`
  → `echo = (sender == gw.player)`, `guild = (guild_id == gw.config.guild_id)` → appelle chaque
  handler `e[4](addon, sender, message, echo, guild)`.  *(Channel.lua:380-392, API.lua:152-161)*
- **Constantes** : `GW_MTYPE_EXTERNAL = 8`, `GW_MAX_MESSAGE_LENGTH = 255`.  *(Constants.lua)*
- **Identité** : `gw.player = UnitName("player") .. "-" .. realm`.  *(Globals.lua:44)*
