---
sidebar_label: Docker
---

# Rainbow Six 3: Raven Shield Docker Container

This Docker container runs a Tom Clancy's Rainbow Six 3: Raven Shield dedicated server. It is built on the WINE image and runs the retail game's Unreal Engine 2 server, `UCC.exe server`, for the base game or the Athena Sword or Iron Wrath add-on. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  ravenshield:
    image: lancommander/ravenshield:latest
    container_name: ravenshield

    ports:
      - 7777:7777/udp
      - 8777:8777/udp

    volumes:
      - "/data/Servers/Raven Shield/Adversarial:/config"

    environment:
      RVS_SERVER_NAME: "My Raven Shield Server"
      RVS_MOD: "RavenShield"
      RVS_MAPS: "Bank:bomb,Airport:teamsurvival,Peaks:survival"
      RVS_ADMIN_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy a Raven Shield **1.60** install (the folder with `system/UCC.exe`, `system/R6Game.u`, `maps/` and `Mods/`) into `Server/` before the first start. You can instead set `RVS_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallRavenShield.ps1` checks for `Server/system/UCC.exe`. If it's missing and `RVS_ARCHIVE_URL` is set, the hook downloads the archive, extracts the folder that holds `system/R6Game.u` and `system/UCC.exe` (without `Videos/` and `Uninstall/`), and remounts the overlay.
3. `PostInitialization/30-ConfigureRavenShield.ps1` reads `Mods/<RVS_MOD>.mod` to find the mod's server ini and copies it to `system/LANCommander-<RVS_MOD>.ini` (`RVS_SERVER_INI`) if that doesn't exist yet. It does this through `Merged/`, so the file lands in `Overlay/system/`. It then writes the non-empty `RVS_*` settings and the map rotation into it.
4. `START_EXE` (`/usr/local/bin/ravenshield-server`) runs `UCC.exe server [-mod=<RVS_MOD>] -servercfg=<ini> -port=<RVS_PORT> log=server.log` from `system/` under Wine. The server starts on the first map of the rotation.

A successful start ends with:

```
Raven Shield engine initialized
...
Game class is 'R6TeamBomb'
...
TcpNetDriver on port 7777
Spawning: IpDrv.UdpBeacon
Level is Level Bank.MyLevel
...
Game engine initialized
```

## Configuration Options

### Ports

- **7777/udp**: Game (`RVS_PORT`)
- **8777/udp**: LAN beacon (`[IpDrv.UdpBeacon] ServerBeaconPort` in `RavenShield.ini`). The in-game LAN browser sends `REPORT` here, and the server replies with its name, map, game type, player count, version and rotation.
- **5777/udp**, **10777/udp**: opened by the game's ubi.com service layer at fixed ports, whatever `RVS_PORT` is. The LAN browser doesn't use them.

### Mods

`RVS_MOD` picks the mod by its `Mods/<name>.mod` file. Each mod has its own server ini template and its own generated ini (`LANCommander-RavenShield.ini`, `LANCommander-AthenaSword.ini`, `LANCommander-IronWrath.ini`), so switching mods doesn't mix their settings. Clients must have the same mod; the beacon reports it (`RavenShield`, `PATCH 1.60`; `AthenaSword`, `PATCH 1.10`; Iron Wrath `RETAIL 1.00`).

| `RVS_MOD` | Template |
|-----------|----------|
| `RavenShield` | `system/Server.ini` |
| `AthenaSword` | `Mods/AthenaSword/System/ServerAthenaSword.ini` |
| `IronWrath` | `Mods/IronWrath/System/ServerIronWrath.ini` |

### Environment Variables

See the [README](../README.md#environment-variables) for the full table and the game type names.

### Server ini

`Overlay/system/LANCommander-<RVS_MOD>.ini` is yours to edit. Only the keys that have a non-empty `RVS_*` variable are rewritten on start. Delete the file to regenerate it from the template.

- `[Engine.R6ServerInfo]` holds the server settings: `ServerName`, `MaxPlayers`, `GamePassword`/`UsePassword`, `AdminPassword`/`UseAdminPassword`, `MOTD`, `RoundTime`, `RoundsPerMatch`, `BetweenRoundTime`, `BombTime`, `NbTerro`, `DiffLevel`, `FriendlyFire`, `Autobalance`, `TeamKillerPenalty`, `AllowRadar`, `ShowNames`, `AIBkp`, `InternetServer`, the spectator camera options (`CamFirstPerson`, `CamThirdPerson`, `CamFreeThirdP`, `CamGhost`, `CamFadeToBlack`, `CamTeamOnly`) and others without a variable (`RotateMap`, `ForceFPersonWeapon`, `AllowArmPatch`, `LoudFoot`, the chat spam limits).
- `[Engine.R6MapList]` holds the rotation: `Maps[0]`..`Maps[31]` and `GameType[0]`..`GameType[31]` (game classes). `RVS_MAPS` rewrites both lists on every start; without it they're left as they are.
- Clearing `RVS_GAME_PASSWORD` or `RVS_ADMIN_PASSWORD` doesn't remove the password from the ini; set `UsePassword`/`UseAdminPassword` to `False` there.

The engine also saves its current settings back into the mod's own server ini (e.g. `system/Server.ini`) through the overlay. The server never reads that copy while `-servercfg` points at the generated ini.

### Game types

Adversarial and co-op game types can both be in a rotation. Co-op types (`mission`, `terroristhunt`, `hostagerescue`) cap the server at 8 players and spawn `NbTerro` terrorists at `DiffLevel`. Athena Sword game types need `RVS_MOD=AthenaSword` and Iron Wrath ones `RVS_MOD=IronWrath`; the hook warns otherwise.

### Hooks

| Hook | When |
|------|------|
| `PreInstallRavenShield` / `PostInstallRavenShield` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to 8777, so the container needs its own LAN address (macvlan/ipvlan) or host networking. Joining by IP works through port mapping.
- **`try again time ...` every 15 seconds**: `InternetServer=True` in the server ini, so the server keeps trying to log in to ubi.com, which no longer exists. `RVS_INTERNET_SERVER=false` (the default) turns it off.
- **Clients can't join / version mismatch**: server and clients must both run patch 1.60 and the same mod.
- **Settings ignored**: they go into the generated ini (`RVS_SERVER_INI`), not `Server.ini` or the client's `RavenShield.ini`. Check `Overlay/system/LANCommander-<RVS_MOD>.ini`.
- **`Map ... is not installed; left out of the rotation`**: the map isn't a `.rsm` file in `maps/` or `Mods/*/Maps/`. Names are case-insensitive; the `.rsm` extension is optional.
- **`Mod ... not found`**: `RVS_MOD` must match a `Mods/<name>.mod` file; the error lists the installed ones.
- **`docker stop` takes 10 seconds**: UCC ignores SIGTERM, so Docker kills it after the timeout. Nothing is lost; the server keeps no state between maps.
- **`system/UCC.exe not found`**: `Server/` must contain the game folder itself (`Server/system/UCC.exe`), not a folder that contains it.
