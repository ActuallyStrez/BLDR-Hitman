Hitman Ped System for QBCore FiveM (Entirely Built by BLDR-AI)

What this resource does
- Spawns a single AI "Hitman" ped when a player crosses configured ped-kill thresholds.
- Hitmen spawn in vehicles, chase the targeted player relentlessly until either the player or the hitman dies, and use police-like driving during pursuits.
- Blips track the hitman while active and are removed on death/cleanup.
- Includes server-side ped kill counting and a `/pedkills` command to view your count.

Dependencies
- `qb-core` (resource must be present and started)

Installation
1. Place the resource folder in your server's `resources` directory.
2. Ensure the resource name is added to `server.cfg` and started after `qb-core`, for example:
   - `ensure qb-core`
   - `ensure your-hitman-resource`
3. Restart the server or start the resource.

Configuration
- `config.lua` contains all tunables, including:
  - `HITMAN_DISTANCE` — spawn distance from player (meters)
  - `HITMAN_RETURN_DISTANCE` — distance at which hitman returns to vehicle and resumes chase
  - `HITMAN_HEALTH`, `HITMAN_ARMOR` — hitman durability
  - `HITMAN_DRIVE_SPEED`, driver ability/aggressiveness and driving style values
  - `HITMAN_MODELS` — ped model list used for hitmen
  - `VEHICLE_LIST` — vehicles used for hitman spawns
  - Weapon lists and other spawn/pursuit options

Usage & Commands
- `/pedkills` — shows the player's current ped kill count via QBCore notification.

Notifications
- When a hitman starts targeting you: QBCore notify with message: "You think you can get away with killing locals?"
- When you kill the hitman: QBCore notify with message: "Hitman Killed"

Behavior Notes
- Hitmen are configured to pursue until either the hitman or the player dies.
- If the player moves beyond `HITMAN_RETURN_DISTANCE`, the hitman will return to (or spawn) their vehicle and resume pursuit.
- The script includes retry/wrap logic to ensure the ped enters their vehicle reliably.

Testing
- Start the resource and provoke an NPC kill to trigger hitman logic (or trigger the event if available).
- Move away from the hitman to verify vehicle return and resumed chase.
- Kill the hitman to verify the "Hitman Killed" notification and cleanup.

Security & Best Practices
- All client-side actions are driven by server events; server-side validation exists for ped-kill thresholds.
- Tweak distances, health, and driving style values in `config.lua` to fit your server's balance and performance needs.

Need help?
- Tell me which behavior you'd like adjusted (spawn distance, vehicle choices, notification text, pursuit rules) and I will update the resource.
