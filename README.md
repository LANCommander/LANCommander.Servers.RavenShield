# Rainbow Six 3: Raven Shield Server (Docker)

This repository provides a Dockerized **Tom Clancy's Rainbow Six 3: Raven Shield** dedicated server. Raven Shield is a 2003 tactical shooter by Red Storm Entertainment and Ubisoft Montreal, built on Unreal Engine 2. Patch 1.60 runs the base game and its two add-ons, Athena Sword and Iron Wrath. The image runs the retail Windows game's `UCC.exe server` under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs the retail game's `UCC.exe server` (headless; no X display, graphics or sound)
- Base game, Athena Sword or Iron Wrath (`RVS_MOD`)
- A separate server ini is created from the mod's own server ini, and the common settings are environment variables
- Map rotation with a game type per map, adversarial or co-op, with short names for every game type
- The ubi.com internet listing is off by default, so the server doesn't retry the dead ubi.com service
- UCC's console log goes to `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  ravenshield:
    image: lancommander/ravenshield:latest
    container_name: ravenshield

    ports:
      - "7777:7777/udp"
      - "8777:8777/udp"

    volumes:
      - ./config:/config

    environment:
      RVS_SERVER_NAME: "My Raven Shield Server"
      RVS_MAPS: "Bank:bomb,Airport:teamsurvival,Peaks:survival"
      RVS_MAX_PLAYERS: "16"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser finds servers by broadcast. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`). With port mapping, clients join by IP.

---

## Game Files

Raven Shield is retail software with no public download. You must provide a **Raven Shield 1.60** install (the folder with `system/UCC.exe`, `system/R6Game.u`, `maps/` and `Mods/`). Clients must run the same patch.

- copy that folder's contents (`system/`, `maps/`, `Mods/`, `textures/` ...) to `config/Server/`, **or**
- set `RVS_ARCHIVE_URL` to a zip of it, e.g. a LANCommander archive. It is downloaded and extracted on first start, if `Server/system/UCC.exe` doesn't exist yet.

The server doesn't need `Videos/`, `Mods/*/Videos/` or `Uninstall/` (about 340 MB); the archive install leaves them out. A full 1.60 install with both add-ons is about 2.5 GB without them.

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # Raven Shield install (system/, maps/, Mods/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (the server ini lands in system/ here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The ini settings are written into the server ini on every start. Settings left empty are not touched, so you can set them in the ini instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `RVS_MOD` | `RavenShield`, `AthenaSword` or `IronWrath` (a `Mods/<name>.mod` file) | `RavenShield` |
| `RVS_MAPS` | Map rotation, `map[:gametype]` comma separated; the server starts on the first map. Empty: the list in the ini is left alone | |
| `RVS_GAME_TYPE` | Game type for `RVS_MAPS` entries without one; a short name (see below) or a game class | `teamsurvival` |
| `RVS_SERVER_INI` | Server ini in `system/`, created from the mod's server ini if missing | `LANCommander-<RVS_MOD>.ini` |
| `RVS_PORT` | Game port (`-port=`) | `7777` |
| `RVS_SERVER_NAME` | `ServerName` | `Raven Shield Server` |
| `RVS_MOTD` | `MOTD` | |
| `RVS_MAX_PLAYERS` | `MaxPlayers`. Co-op game types are capped at 8 by the game | `16` |
| `RVS_GAME_PASSWORD` | `GamePassword`, and sets `UsePassword=True` | |
| `RVS_ADMIN_PASSWORD` | `AdminPassword`, and sets `UseAdminPassword=True` | |
| `RVS_ROUND_TIME` | `RoundTime` in seconds | |
| `RVS_ROUNDS_PER_MATCH` | `RoundsPerMatch` | |
| `RVS_BETWEEN_ROUND_TIME` | `BetweenRoundTime` in seconds | |
| `RVS_BOMB_TIME` | `BombTime` in seconds | |
| `RVS_TERRORISTS` | `NbTerro`, terrorists in co-op game types | |
| `RVS_DIFFICULTY` | `DiffLevel`: `recruit`/`veteran`/`elite` or 1-3 | |
| `RVS_FRIENDLY_FIRE` | `true`/`false`: `FriendlyFire` | |
| `RVS_AUTOBALANCE` | `true`/`false`: `Autobalance` | |
| `RVS_TEAM_KILLER_PENALTY` | `true`/`false`: `TeamKillerPenalty` | |
| `RVS_ALLOW_RADAR` | `true`/`false`: `AllowRadar` | |
| `RVS_SHOW_NAMES` | `true`/`false`: `ShowNames` | |
| `RVS_AI_BACKUP` | `true`/`false`: `AIBkp`, AI backup in co-op | |
| `RVS_INTERNET_SERVER` | `true`/`false`: `InternetServer`. `true` makes the server log in to ubi.com, which is offline | `false` |
| `RVS_ARCHIVE_URL` | Zip of the game folder, used if `Server/system/UCC.exe` is missing | |
| `WINE_XVFB` | UCC needs no display | `false` |
| `START_EXE` | Launcher | `/usr/local/bin/ravenshield-server` |
| `START_ARGS` | Appended to the UCC command line | |

All the ini keys are in `[Engine.R6ServerInfo]`. `DedicatedServer=True` is always set.

Game types:

| Short name | Game class | Game type (in game) | Mod |
|------------|------------|---------------------|-----|
| `survival`, `dm` | `R6Game.R6DeathMatch` | Survival | all |
| `teamsurvival`, `tdm` | `R6Game.R6TeamDeathMatchGame` | Team Survival | all |
| `bomb` | `R6Game.R6TeamBomb` | Bomb | all |
| `hostage` | `R6Game.R6HostageRescueAdvGame` | Hostage | all |
| `pilot`, `escort` | `R6Game.R6EscortPilotGame` | Pilot | all |
| `mission` | `R6Game.R6MissionGame` | Mission (co-op) | all |
| `terroristhunt`, `th` | `R6Game.R6TerroristHuntCoopGame` | Terrorist Hunt (co-op) | all |
| `hostagerescue` | `R6Game.R6HostageRescueCoopGame` | Hostage Rescue (co-op) | all |
| `capturetheenemy`, `cte` | `ASGame.R6CaptureTheEnemyAdvGame` | Capture the Enemy | AthenaSword |
| `kamikaze` | `ASGame.R6KamikazeGame` | Kamikaze | AthenaSword |
| `scatteredhunt` | `ASGame.R6ScatteredHuntAdvGame` | Scattered Hunt | AthenaSword |
| `terroristhuntadv` | `ASGame.R6TerroristHuntAdvGame` | Terrorist Hunt (adversarial) | AthenaSword |
| `countdown` | `ASGame.R6CountDownGame` | Countdown | AthenaSword |
| `limitseats` | `MP2Game.MP2LimitSeatsAdvGame` | Limit Seats | IronWrath |
| `freebackup` | `MP2Game.MP2FreeBackupAdvGame` | Free Backup | IronWrath |
| `gasalert` | `MP2Game.MP2GazAlertAdvGame` | Gas Alert | IronWrath |
| `virusupload` | `MP2Game.MP2VirusUploadAdvGame` | Virus Upload | IronWrath |
| `intruder` | `MP2Game.MP2IntruderAdvGame` | Intruder | IronWrath |

Maps are the `.rsm` files in `maps/` and `Mods/*/Maps/` (e.g. `Bank`, `Airport`, `Peaks`; Athena Sword `MP_Castle`, `MP_Agora`; Iron Wrath `GhostTown`, `Docks`).

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/ravenshield:local .
```

---

## License

Raven Shield and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
