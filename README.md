# TradeScanner

WoW Classic Era addon that monitors a dedicated trade channel (and guild chat via GreenWall) for WTS/WTB offers, with profession integration to alert you when someone is looking for something you can craft.

Built for international Fresh servers where trade happens in a custom channel like `#freshtrade` instead of the Auction House.

---

## Installation

Copy the `TradeScanner/` folder into:
```
World of Warcraft\_classic_era_\Interface\AddOns\
```

---

## Features

- **Monitors a configurable trade channel** (default: `freshtrade`) and **/g guild chat** (GreenWall-compatible)
- **Detects WTS / WTB** messages with fully configurable keywords (supports EN + FR by default)
- **Profession integration** — open any profession window and the addon indexes your recipes; WTB requests you can fulfill are highlighted in gold
- **Craft alerts** — sound + minimap icon pulse when a new WTB is detected for an item you know how to make
- **Deduplication** — each player appears only once per item; entries are updated if they repost
- **Draggable minimap button** — right-drag to reposition, left-click to open
- **Click-to-whisper** — click any row to open a whisper to that player
- **Decimal price parsing** — handles `1.5g`, `1,5g`, `1.50g`, etc. (international separators)
- **Channel message log** — persistent log of all channel traffic for debugging

---

## Interface

4 tabs:

| Tab | Content |
|---|---|
| **All** | Every offer from the last 30 minutes |
| **Sales (WTS)** | Sellers only |
| **Wanted (WTB)** | Buyers only |
| **Craftable (N)** | WTB requests matching your known recipes |

The **Craftable** tab counter updates in real time. The minimap button pulses gold and shows a tooltip with the pending count when new craftable WTB offers come in. Opening the Craftable tab resets the alert.

---

## Slash Commands

| Command | Effect |
|---|---|
| `/ts` | Open / close the window |
| `/ts channel <name>` | Set the watched channel (default: `freshtrade`) |
| `/ts guild` | Toggle guild chat scanning (GreenWall) |
| `/ts alert` | Toggle craft alert sound |
| `/ts scan` | Manually scan the currently open profession window |
| `/ts add sell <WORD>` | Add a sell keyword |
| `/ts add buy <WORD>` | Add a buy keyword |
| `/ts remove sell <WORD>` | Remove a keyword |
| `/ts keywords` | List active keywords |
| `/ts clear` | Clear all stored offers |
| `/ts debug` | Toggle real-time channel message output in chat |
| `/ts log [N]` | Print the last N channel messages with parse result (default: 30) |
| `/ts logclear` | Clear the message log |
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
| `skip_kw` | Channel matched but no keyword found |
| `skip_chan` | Wrong channel, ignored |

Use `/ts debug` to see results in real time, or `/ts log 50` to review recent history.

---

## Default Keywords

| Type | Keywords |
|---|---|
| Sell | `WTS`, `VDS`, `S>`, `VEND`, `SELL` |
| Buy | `WTB`, `ACH`, `B>`, `ACHAT`, `BUY`, `CHERCHE`, `ISO` |

All keywords are **case-insensitive**. Add your own with `/ts add sell <WORD>`.
