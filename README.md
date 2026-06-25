# Guild Economy (TradeScanner)

WoW Classic Era addon that monitors a dedicated trade channel (and guild chat via GreenWall) for WTS/WTB/WTT offers, with profession integration to alert you when someone is looking for something you can craft — plus an out-of-band **Guild Craft Orders** system that propagates across a GreenWall confederation.

Built for international Fresh servers where trade happens in a custom channel like `#freshtrade` instead of the Auction House.

---

## Installation

Copy the `TradeScanner/` folder into:
```
World of Warcraft\_classic_era_\Interface\AddOns\
```

---

## Features

- **Monitors multiple trade channels** (default: `freshtrade`) and **/g guild chat** (GreenWall-compatible) — add as many watched channels as you like
- **Detects WTS / WTB / WTT / WTG** messages with fully configurable keywords (EN + FR by default), including **gifts/giveaways** (WTG, FREE, GRATUIT…)
- **Auction-house-style browse** — a category sidebar (item class → subclass → armor slot) plus **quality** and **required-level** filters and **sortable columns** (Type / Item / Price / Player / Age)
- **Profession integration** — open any profession window and the addon indexes your recipes; chat requests you can fulfill are highlighted in gold (Enchanting / Beast Training supported via the Classic **Craft** API, not just TradeSkill)
- **Static profession database** — 10 professions, ~1100 craftable items + ~130 enchants, so the addon knows who can make what even before anyone scans
- **Guild Craft Orders** (`/ts order`) — order an item or enchant from the guild out-of-band; crafters of the right profession get an alert and can Accept (auto-whisper to the buyer). Online crafters of the selected profession are listed at the top
- **Order validation & delivery tracking** — once accepted, a **Validate** button lets the crafter or buyer mark an order delivered, which removes it for everyone. If the buyer also runs the addon, **completing the trade auto-validates** it; a **partial hand-over decrements the remaining quantity** network-wide instead of closing the order
- **Cross-realm sync via GreenWall** — offers stay guild-local, but craft orders **and professions** propagate across the whole confederation (sister guilds, cross-server). See [Documentation/GreenWall-Integration.md](Documentation/GreenWall-Integration.md)
- **Multi-item sell from your bags** — Alt + right-click bag items to stack them in a **mail-style composer** (price / qty per item), then post them all at once. The chat message auto-splits under the 255-character limit and is tagged `[Guild Economy]`; selling an item also flags it as sellable
- **Settings panel** — a gear button (or `/ts settings`) to manage watched channels, the send channel, toggles, and your sellable list
- **New-version alert** — get notified once per session when a guildmate runs a newer version
- **Craft alerts** — sound + minimap icon pulse when a new request matches something you can make
- **Deduplication** — each player appears only once per item; entries update if they repost
- **Draggable minimap button**, **click-to-whisper**, **decimal price parsing** (`1.5g`, `1,5g`, `1.50g`…), and a **persistent message log** for debugging

---

## Interface

6 tabs:

| Tab | Content |
|---|---|
| **All** | Every offer from the last 30 minutes |
| **Sales (WTS)** | Sellers only |
| **Wanted (WTB)** | Buyers only |
| **Gifts (WTG)** | Free giveaways (Want To Give) |
| **Sellable (N)** | WTB requests for items **you** can personally supply (counter updates in real time) |
| **Orders** | Guild Craft Orders + online crafters of the selected profession + chat requests |

The offer tabs feature an **auction-house-style left sidebar**: pick an item category (e.g. Armor → Cloth → Head) to filter the list, narrow by **quality** and **required level**, and click any column header to **sort** (▲▼). A **Filter** box (top-right) and a **gear button** (settings) round out the window.

The minimap button pulses gold and shows a tooltip with the pending count when new requests you can fulfill come in. Opening the **Sellable** tab resets the alert.

**Craft order lifecycle:** `open` → **Accept** (auto-whispers the buyer) → **Validate** (delivered). Validating removes the order for everyone. If the buyer runs the addon, completing the trade validates automatically — a partial hand-over just lowers the remaining quantity network-wide.

---

## Slash Commands

| Command | Effect |
|---|---|
| `/ts` | Open / close the main window |
| `/ts settings` | Open the settings panel (channels, toggles, sellable list) |
| `/ts order` | Open the Guild Craft Orders panel |
| `/ts profs` | Show my professions + known guild roster |
| `/ts scan` | Manually scan the currently open profession window |
| `/ts sell <shift-click>` | Add / remove a manual "sellable" item |
| `/ts exclude <shift-click>` | Exclude / include an item from scan results |
| `/ts channel <name>` | Set the default **send** channel (default: `freshtrade`) |
| `/ts channel add\|remove\|list <name>` | Manage the **watched** channels |
| `/ts guild` | Toggle guild chat scanning (GreenWall) |
| `/ts wts` | Toggle the bag Alt-right-click WTS shortcut |
| `/ts confed` | Toggle cross-realm sync (GreenWall confederation) |
| `/ts gwdebug` | Toggle GreenWall send / receive debug prints |
| `/ts alert` | Toggle craft alert sound |
| `/ts add sell\|buy\|gift <WORD>` | Add a keyword |
| `/ts remove sell\|buy\|gift <WORD>` | Remove a keyword |
| `/ts keywords` | List active keywords |
| `/ts clear` | Clear all stored offers |
| `/ts debug` | Toggle real-time channel message output in chat |
| `/ts log [N]` | Print the last N channel messages with parse result (default: 30) |
| `/ts retest [N]` | Replay the parser on the captured log (validate parsing changes) |
| `/ts logclear` | Clear the message log |
| `/ts errors [clear]` | Show / clear recent TradeScanner Lua errors |
| `/ts help` | Show help |

---

## Profession Integration

The addon scans your recipes automatically whenever you open a profession window. Recipes are cached in SavedVariables — you only need to open each profession once per character.

WTB offers matching one of your recipes are displayed with:
- A **gold left-side bar** on the row
- The **profession name** in the Craft column
- An extended tooltip confirming you can craft the item
- A **sound alert** (Ready Check bell) and **minimap icon pulse** on new matches

---

## Message Log & Debugging

All messages from the watched channel are logged to a separate SavedVariable (`TradeScannerLog.lua`) with their parse result:

| Result | Meaning |
|---|---|
| `sell` | Captured as a sale offer |
| `buy` | Captured as a buy request |
| `gift` | Captured as a gift / giveaway (WTG) |
| `skip_kw` | Channel matched but no keyword found |
| `skip_chan` | Not a watched channel, ignored |

Use `/ts debug` to see results in real time, or `/ts log 50` to review recent history.

---

## Default Keywords

| Type | Keywords |
|---|---|
| Sell | `WTS`, `VDS`, `S>`, `VEND`, `SELL`, `LFW` |
| Buy | `WTB`, `ACH`, `B>`, `ACHAT`, `BUY`, `CHERCHE`, `ISO`, `WTT`, `TROC` |
| Gift | `WTG`, `GIFT`, `FREE`, `GRATUIT`, `DON` |

`LFW` (looking for work) is treated as a **sell** (service offer); `WTT` / `TROC` (trade) are treated as **buy** (the poster wants to obtain an item); `WTG` / `FREE` / `GRATUIT` mark a **gift** (free giveaway). Sell and buy are matched first, so "WTS … free" stays a sale. All keywords are **case-insensitive**. Add your own with `/ts add sell|buy|gift <WORD>`.
