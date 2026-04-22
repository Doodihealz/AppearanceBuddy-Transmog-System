<h1 align="center">AppearanceBuddy</h1>
<p align="center"><strong>Transmog System for AzerothCore</strong></p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/684b1a04-f3b9-4b0d-8eec-8ff7e1e76bb5" width="120" alt="AppearanceBuddy Logo" />
</p>

<p align="center">
  AppearanceBuddy is a fully-featured, account-wide transmog system for AzerothCore private servers.
</p>

<p align="center">
  <strong>Requires:</strong> AzerothCore, ALE, and AIO (client + server). Built on AIO 1.75.
</p>

<p align="center">
  Open it anywhere with <code>/ab</code> or click the character page button — no NPC interaction required.
</p>

<p align="center">
  If this project has been useful to you, please ⭐ it.
</p>

---

## Overview

AppearanceBuddy is a fully-featured, account-wide transmog system for AzerothCore private servers.

Open it anywhere with `/ab` or click the character page button — no NPC interaction required. The database creates itself on first run. Every item that enters your inventory is automatically collected. There is nothing to configure to get started.

## Features

### Appearance Collection

- Items are automatically collected from looting, equipping, inventory scans, and quest rewards — including all choice reward options, not just the one you picked.
- Retroactive scan on first login unlocks appearances for all previously completed quests.
- **Provisional unlocks:** items looted during group play are tracked in a 2-hour window and permanently unlocked once confirmed as yours — preventing buy → collect → refund and loot-trading exploits.
- `Ctrl+Shift+Click` an item in the UI to permanently remove an appearance from your account.
- Full account wipe option in settings.

### Browsing & Search

- Browse appearances per equipment slot with a paged item grid — each item rendered as a mini 3D preview on your actual character model in full transmog context.
- Text search by item name or display ID.
- Rarity filter (Grey through Artifact, multi-select).
- Armor/weapon type filter per slot, dynamically shown only when relevant.
- Item cards show collection status (border highlight if not yet collected).
- Wowhead URL dialog (`Ctrl+Click` any item) — toggle between Classic and Retail domains.
- Chat link any item with `Shift+Click`.
- Page navigation with automatic adjacent-page prefetching for near-instant browsing.

### Applying Transmogs

- Apply, hide, or restore individual slots or all 14 visible slots at once.
- **Set system:** save your current outfit as a named set, load it back, edit it, and delete it.
- **Catalog:** server-generated item sets grouped from the game's item templates (for example, all *Cyclone* pieces as one set) — shows unlock completion per set and applies only pieces you've collected.
- **Pending changes system:** stage multiple slots in preview before committing anything to the server.
- **Apply All** commits all staged changes in one round-trip.
- **Revert All** stages your active transmogs for removal.

### Dressing Room

- Full 3D character preview with:
  - left-drag rotation
  - right-drag pan
  - scroll-wheel zoom
  - middle-click reset
- Momentum: rotation continues with friction decay after releasing the mouse.
- Supports inspecting nearby players — load their appearance with **Use Target**.
- Shadowform simulation for Shadow Priests.
- Configurable race backgrounds (Orc → Durotar, Tauren → Mulgore, etc.) or solid color.
- **Bare character** mode to preview items on an undressed model in the grid.

### Costs

Optional gold cost with scaling by player level, item level, and rarity:

- Grey/Common: `0.25×`
- Uncommon: `0.5×`
- Rare: `1×`
- Epic: `3×`
- Legendary: `30×`

Additional notes:

- New characters pay a small fraction; max-level characters pay the full rate.
- Live cost display in the status bar shows total gold for all pending changes before you commit.
- GMs can toggle free transmogs at runtime with `.transmog free` / `.transmog cost`.

### Restrictions (Blizzlike Mode)

- Toggleable enforcement of WoW's armor type, weapon type, class, and level restrictions.
- No plate on priests, no 2H dual-wield unless Warrior with Titan's Grip, etc.
- All restrictions are validated server-side on apply — the client cannot bypass them.

### Settings

- Preview model quality (classic / modern)
- Race-specific dressing room background
- Grid cell background texture
- Show/hide the **Appearance** button in the character panel
- Show/hide shortcut hints in tooltips
- UI scale override (fixes 3D model rendering at non-default scales)
- Lock window position
- Bare character / item-only view in the grid
- Toggle `Ctrl+Shift+Click` removal
- Show item display ID in tooltip
- Uncollected appearance border (bag and loot items)
- **Not yet collected!** tooltip text
- Show transmog cost in status bar
- Hide placeholder items (items with no required level and item level ≤ 1)

## Slash Commands

| Command | Effect |
|---|---|
| `/ab` or `/appearancebuddy` | Toggle main window |
| `/appearancebuddy debug` | Show model position/facing/Z debug overlay |
| `/appearancebuddy scan` | Frame overlap diagnostic |
| `.transmog free` *(GM rank 3+)* | Toggle free transmogs server-wide |
| `.transmog cost` *(GM rank 3+)* | Re-enable gold cost |

## Performance

- Server-side bulk item template queries (500-item chunks) — one round-trip for entire appearance catalogs.
- Client-side item blacklist prevents repeated failed queries (persisted across sessions).
- Page cap persistence skips ghost pages of invalid items permanently.
- Mini dressing room frames are recycled between pages — never created or destroyed during browsing.
- Set list builds incrementally in coroutine batches so the UI stays responsive on large catalogs.
- Server-to-client data transfer is approximately **97% faster** than the original iteration.

## Database Tables (auto-created)

| Table | Purpose |
|---|---|
| `account_transmog` | Permanently unlocked appearances per account |
| `character_transmog` | Active transmog overrides per character slot |
| `transmog_settings` | Server configuration key-value store |
| `provisional_transmog` | Temporary unlock tracking during 2-hour loot window |

## Installation

1. Place `transmog.lua` in your AzerothCore Lua scripts folder.
2. Unzip the addon into your client's `Interface/AddOns/` folder.
3. Restart your server and log in.

> On a completely fresh install the server may crash once while creating its database tables. Restart it once more and it will load cleanly from then on.

## Credits

- **TransmogByDan** — original server-side script used as a foundation:  
  `https://github.com/DanieltheDeveloper/azerothcore-transmog-3.3.5a`
- **GetLocalPlayer / DressMe** — original addon used as a baseline for the client side:  
  `https://github.com/GetLocalPlayer/DressMe`

## License & Usage

Provided as-is.

Custom races and other custom content are out of scope and will not be supported.

Please do not sell this. Credit is required if you share, modify, or use this on your server — **Doodihealz / Corey**.

## Preview

<img width="1746" height="836" alt="image" src="https://github.com/user-attachments/assets/6d0d7d33-b39b-4e90-ba10-1664093916ae" />
<img width="1752" height="835" alt="image" src="https://github.com/user-attachments/assets/5479819f-1706-497d-84d1-1bd285abb72d" />
<img width="1751" height="845" alt="image" src="https://github.com/user-attachments/assets/d2b6cdd8-d8ff-4944-9ad6-2ade4c760df7" />
<img width="657" height="592" alt="image" src="https://github.com/user-attachments/assets/a0746957-0ba9-4a40-bc93-77a2b70d6887" />
