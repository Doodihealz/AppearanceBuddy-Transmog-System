# AppearanceBuddy — Transmog System

**Requires:** AzerothCore, ALE, and AIO (client + server). Built on AIO 1.75.

If this project has been useful to you, please ⭐ it to show your support.

---

## Overview

AppearanceBuddy is a fully-featured transmog system for AzerothCore private servers. It provides an intuitive, in-game UI accessible from anywhere — no NPC interaction required. The system silently handles all database setup on first run, so there is nothing to configure manually.

**Key features:**

- Browse, search, and apply transmogrifications directly from the UI
- Save and load custom transmog sets
- Track which appearances and in-game sets you have collected (e.g., Relentless Gladiator 8/9)
- Any item that enters your inventory is automatically collected — no notifications, no bloat
- Customizable backgrounds per race (Orc → Durotar background, Tauren → Mulgore, etc.)
- Items show if you have unlocked the display appearance or not yet with a border and/or a tooltip message
- Rotate your character preview with click-drag, zoom with the mousewheel, and scroll through transmog pages with the mousewheel on the item panel

**Performance:** The script has been significantly optimized since its first release. Server-to-client communication is approximately **94% faster** than the original iteration, resulting in a smooth, responsive experience even when browsing large sets catalogs.

---

## Installation

1. Place the Lua script in your AzerothCore Eluna scripts folder.
2. Unzip the addon and place it in your client's `Interface/AddOns` folder.
3. Restart your server and log in.

> If the server crashes on first load, restart it once more. The script creates its own database tables automatically and may need a second pass on a fresh install.

---

## Credits

- **TransmogByDan** — original server-side transmog script used as a foundation: https://github.com/DanieltheDeveloper/azerothcore-transmog-3.3.5a
- **GetLocalPlayer / DressMe** — original addon used as a baseline for the client side: https://github.com/GetLocalPlayer/DressMe

---

## License & Usage

This script and addon are provided as-is. I will not be adding support for custom races or other custom content. Please do not sell this. **Credit is required if you use or redistribute this project.** — Doodihealz / Corey

---

## Preview

![AppearanceBuddy UI](https://github.com/user-attachments/assets/9a94d82a-4baa-420f-9943-766a63e26449)
