Config = {}

-- Kill tracking
Config.KILL_THRESHOLD = 10
Config.WINDOW_SECONDS = 600 -- time window to count ped kills (seconds)
Config.HIT_COOLDOWN = 900 -- seconds between hit dispatches per player

-- Spawn behavior
-- Preferred models for hitmen (tunable)
Config.HITMAN_MODELS = {
    's_m_m_highsec_01',
    's_m_m_highsec_02',
    's_m_m_highsec_03',
    's_m_m_highsec_04',
    's_m_m_highsec_05'
}
Config.HITMAN_DISTANCE = 1609.34 -- distance from player to spawn hitmen (~1 mile)
Config.SPAWN_NEAR_ROADS = true -- try to spawn near roads
Config.MAX_SPAWN_ATTEMPTS = 20

-- Vehicle vs foot spawn
-- Vehicle list for hitmen (FBI vehicles by default, tunable)
Config.VEHICLE_LIST = {
    'fbi',
    'fbi2',
    'fbi3'
}
-- Default vehicle color (primary, secondary) as RGB or native color index
-- We'll use black via native color indices (0 = black). Adjust if desired.
Config.VEHICLE_COLOR_PRIMARY = 0
Config.VEHICLE_COLOR_SECONDARY = 0
-- License plate text for hitman vehicles
Config.HITMAN_VEHICLE_PLATE = 'HITMAN'

-- Weapon choices for hitmen (lists of GTA V weapon names)
Config.WEAPON_PISTOLS = {
    "weapon_pistol",
    "weapon_pistol_mk2",
    "weapon_combatpistol",
    "weapon_appistol",
    "weapon_pistol50",
    "weapon_snspistol",
    "weapon_heavypistol",
}

Config.WEAPON_MELEES = {
    "weapon_hammer",
    "weapon_bat",
    "weapon_crowbar",
    "weapon_dagger",
    "weapon_bottle",
    "weapon_machete",
}

-- Backwards-compatible single-choice defaults (randomly picked in code if lists present)
Config.WEAPON_PISTOL = Config.WEAPON_PISTOLS[1]
Config.WEAPON_MELEE = Config.WEAPON_MELEES[1]
Config.MELEE_CHANCE = 0.5 -- chance of melee vs pistol when not forced by spawn type

-- Hitman strength/tuning
Config.HITMAN_HEALTH = 600 -- max health for hitman peds (triple strength)
Config.HITMAN_ARMOR = 300 -- armor value applied to hitmen (triple)
Config.HITMAN_ACCURACY_MIN = 95 -- minimum accuracy value (raised for strength)
Config.HITMAN_ACCURACY_MAX = 100 -- maximum accuracy value (cap at 100)
Config.HITMAN_SHOOT_RATE = 60 -- shoot rate for hitmen (45-75; lower = faster)

-- Blip settings
Config.SHOW_BLIP = false
Config.BLIP_SPRITE = 280 -- default blip sprite
Config.BLIP_COLOR = 1
Config.BLIP_TIMEOUT = 120000 -- blip lifetime in ms

-- Logging and admin notify
Config.ENABLE_LOGGING = true
Config.ENABLE_ADMIN_NOTIFY = true
Config.ADMIN_NOTIFY_RANK = 'admin'

return Config
