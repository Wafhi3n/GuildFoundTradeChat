# Changelog — Guild Economy (TradeScanner)

## v1.7.0

**New: single-window profession UI (mono-bloc).** Opening a profession now replaces the
default Blizzard window with a unified **3-column** panel — searchable recipe list (colored
by difficulty) · reagents with have/need and **Create / Create All** · a live **Guild wants**
column (craft orders to Accept/Validate, disenchant mats, sellable items and wanted enchants
for that profession), with a *needed* badge on recipes the guild is asking for. The native
frame is hidden but its session is kept alive so crafting still works. Don't like it?
Uncheck **Replace profession window** in `/ts settings`.

**Fix: co-guild chat offers were invisible.** Offers (WTS/WTB) posted in **sister guilds**
are relayed by GreenWall without firing a normal guild-chat event, so they were never parsed.
They now show up in the offer list like your own guild's.

**New: sell shortcuts.**
- A **basket button** on the main window opens the multi-item sell composer directly.
- The composer now has a **destination selector** — post to any watched channel or to `/g`.

**New: per-channel confederation filter.** Mark a noisy public channel (e.g. Trade) with
`/ts channel confed <name>` to keep only offers from known confederation members.

---

### Earlier

- **v1.6.0** — tavern-themed UI reskin.
- **v1.5.0** — auction-house browse (categories / quality / level / sortable columns),
  multi-channel watching, multi-item sell composer, WTG gifts tab, new-version alert.
