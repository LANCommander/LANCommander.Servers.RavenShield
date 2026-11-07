# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="Rainbow Six 3: Raven Shield Game Server" \
      org.opencontainers.image.description="Dedicated server for Tom Clancy's Rainbow Six 3: Raven Shield (1.60, with Athena Sword and Iron Wrath), running the retail Windows UCC server under Wine" \
      app.lancommander.server.kind="game" \
      app.lancommander.server.game.title="Tom Clancy's Rainbow Six 3: Raven Shield" \
      app.lancommander.server.external-id.hq="5776eb7c-11bc-4625-bd1c-8dced3c4d0e4" \
      app.lancommander.server.external-id.igdb="908" \
      app.lancommander.server.external-id.steam="19830"

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Raven Shield 1.60 install in /config/Server, or
#     set RVS_ARCHIVE_URL to a zip of one
#   - RVS_MOD picks the mod: RavenShield, AthenaSword or IronWrath
#   - RVS_SERVER_INI (in system/) is created from the mod's own server ini on first start; the
#     RVS_* settings below are written into it on every start (empty settings are left alone)
#   - RVS_MAPS is the rotation, "map[:gametype],..."; the server starts on the first entry
#   - UCC is a console program and needs no X display, so Xvfb is off
# ----------------------------
ENV RVS_ARCHIVE_URL="" \
    RVS_MOD="RavenShield" \
    RVS_SERVER_INI="" \
    RVS_PORT="7777" \
    RVS_MAPS="" \
    RVS_GAME_TYPE="teamsurvival" \
    RVS_SERVER_NAME="Raven Shield Server" \
    RVS_MOTD="" \
    RVS_MAX_PLAYERS="16" \
    RVS_GAME_PASSWORD="" \
    RVS_ADMIN_PASSWORD="" \
    RVS_ROUND_TIME="" \
    RVS_ROUNDS_PER_MATCH="" \
    RVS_BETWEEN_ROUND_TIME="" \
    RVS_BOMB_TIME="" \
    RVS_TERRORISTS="" \
    RVS_DIFFICULTY="" \
    RVS_FRIENDLY_FIRE="" \
    RVS_AUTOBALANCE="" \
    RVS_TEAM_KILLER_PENALTY="" \
    RVS_ALLOW_RADAR="" \
    RVS_SHOW_NAMES="" \
    RVS_AI_BACKUP="" \
    RVS_INTERNET_SERVER="false" \
    WINE_XVFB="false" \
    START_EXE="/usr/local/bin/ravenshield-server" \
    START_ARGS=""

COPY Scripts/ravenshield-server /usr/local/bin/ravenshield-server
RUN chmod +x /usr/local/bin/ravenshield-server

COPY Hooks/ "${BASE_HOOKS}/"

# 7777/udp: game (RVS_PORT). 8777/udp: LAN beacon; the in-game LAN browser sends REPORT there
# and gets the full server info back. 5777/udp and 10777/udp: opened by the game's ubi.com
# service layer at fixed ports; not used by the LAN browser.
EXPOSE 7777/udp 8777/udp 5777/udp 10777/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
