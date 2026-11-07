#Requires -Modules Logging

# Create the server ini (RVS_SERVER_INI, default system/LANCommander-<RVS_MOD>.ini) from the mod's
# own server ini on first start, then write the RVS_* settings and the map rotation into it. It's
# created through the merged view, so it lands in Overlay/ and can be edited there; keys without
# an RVS_* setting are never touched.
#
# Each mod names its server ini in Mods/<mod>.mod: m_szServerIni (file name without .ini) in
# m_szIniFilesDir (system/ when unset). Stock: system/Server.ini,
# Mods/AthenaSword/System/ServerAthenaSword.ini, Mods/IronWrath/System/ServerIronWrath.ini.

$root = $Env:SERVER_ROOT
$mod  = if ($Env:RVS_MOD) { $Env:RVS_MOD } else { 'RavenShield' }

# Resolve a relative path case-insensitively (the retail install mixes system/ and System/)
function Resolve-Path-CI([string] $Base, [string] $Relative) {
    $current = $Base
    foreach ($part in ($Relative -split '[\\/]+' | Where-Object { $_ })) {
        if (-not (Test-Path -Path $current -PathType Container)) { return $null }
        $match = Get-ChildItem -Path $current -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $part } | Select-Object -First 1
        if (-not $match) { return $null }
        $current = $match.FullName
    }
    return $current
}

$system = Resolve-Path-CI $root 'system'
if (-not $system) {
    Write-Log -Level Error "system/ not found in $root; skipping server configuration"
    return
}

# The mod's template server ini
$modFile = Resolve-Path-CI $root "Mods/$mod.mod"
if (-not $modFile) {
    $known = (Get-ChildItem -Path (Resolve-Path-CI $root 'Mods') -Filter '*.mod' -File -ErrorAction SilentlyContinue).BaseName -join ', '
    Write-Log -Level Error "Mod $mod not found (Mods/$mod.mod). Installed: $known"
    return
}

$serverIniName = 'Server'
$iniFilesDir   = $null
foreach ($line in [System.IO.File]::ReadAllLines($modFile)) {
    if ($line -match '^\s*m_szServerIni\s*=\s*(.+?)\s*$') { $serverIniName = $Matches[1] }
    if ($line -match '^\s*m_szIniFilesDir\s*=\s*(.+?)\s*$') { $iniFilesDir = $Matches[1] }
}
$template = if ($iniFilesDir) { Resolve-Path-CI $root "$iniFilesDir/$serverIniName.ini" } else { Resolve-Path-CI $system "$serverIniName.ini" }
if (-not $template) { $template = Resolve-Path-CI $system 'Server.ini' }

$iniName = if ($Env:RVS_SERVER_INI) { $Env:RVS_SERVER_INI } else { "LANCommander-$mod.ini" }
$ini     = Join-Path $system $iniName

if (-not (Test-Path -Path $ini)) {
    if (-not $template) {
        Write-Log -Level Error "No server ini template found for mod $mod; skipping server configuration"
        return
    }

    Copy-Item -Path $template -Destination $ini
    Write-Log "Created $ini from $template"
}

$text    = [System.IO.File]::ReadAllText($ini)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split "\r?\n"))

function Get-SectionRange([string] $Section) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ieq "[$Section]") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }

    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('[')) { $end++ }
    return @($start, $end)
}

# Insert a line after the section's last non-blank line, creating the section if needed
function Add-IniLine([string] $Section, [string] $Line) {
    $range = Get-SectionRange $Section
    if (-not $range) {
        if ($lines.Count -and $lines[$lines.Count - 1] -ne '') { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add($Line)
        return
    }

    $start, $end = $range
    $at = $end
    while ($at -gt $start + 1 -and [string]::IsNullOrWhiteSpace($lines[$at - 1])) { $at-- }
    $lines.Insert($at, $Line)
}

# Set Key=Value in [Section], replacing the first existing Key= line or appending to the section.
# StartsWith, not -like: keys such as Maps[0] contain wildcard characters.
function Set-IniValue([string] $Section, [string] $Key, [string] $Value) {
    $range = Get-SectionRange $Section
    if ($range) {
        for ($i = $range[0] + 1; $i -lt $range[1]; $i++) {
            if ($lines[$i].StartsWith("$Key=", [System.StringComparison]::OrdinalIgnoreCase)) {
                $lines[$i] = "$Key=$Value"
                return
            }
        }
    }
    Add-IniLine $Section "$Key=$Value"
}

function ConvertTo-IniBool([string] $Value) {
    if (-not $Value) { return $null }
    if ($Value -in @('true', '1', 'yes', 'on')) { return 'True' }
    return 'False'
}

$difficulty = switch -Regex ($Env:RVS_DIFFICULTY) {
    '^(1|recruit)$'  { '1' }
    '^(2|veteran)$'  { '2' }
    '^(3|elite)$'    { '3' }
    '^$'             { $null }
    default          { Write-Log -Level Warning "RVS_DIFFICULTY=$($Env:RVS_DIFFICULTY) is not 1-3/recruit/veteran/elite; ignored"; $null }
}

$section  = 'Engine.R6ServerInfo'
$settings = @(
    @('ServerName',        $Env:RVS_SERVER_NAME),
    @('MOTD',              $Env:RVS_MOTD),
    @('MaxPlayers',        $Env:RVS_MAX_PLAYERS),
    @('RoundTime',         $Env:RVS_ROUND_TIME),
    @('RoundsPerMatch',    $Env:RVS_ROUNDS_PER_MATCH),
    @('BetweenRoundTime',  $Env:RVS_BETWEEN_ROUND_TIME),
    @('BombTime',          $Env:RVS_BOMB_TIME),
    @('NbTerro',           $Env:RVS_TERRORISTS),
    @('DiffLevel',         $difficulty),
    @('FriendlyFire',      (ConvertTo-IniBool $Env:RVS_FRIENDLY_FIRE)),
    @('Autobalance',       (ConvertTo-IniBool $Env:RVS_AUTOBALANCE)),
    @('TeamKillerPenalty', (ConvertTo-IniBool $Env:RVS_TEAM_KILLER_PENALTY)),
    @('AllowRadar',        (ConvertTo-IniBool $Env:RVS_ALLOW_RADAR)),
    @('ShowNames',         (ConvertTo-IniBool $Env:RVS_SHOW_NAMES)),
    @('AIBkp',             (ConvertTo-IniBool $Env:RVS_AI_BACKUP)),
    @('InternetServer',    (ConvertTo-IniBool $Env:RVS_INTERNET_SERVER)),
    @('DedicatedServer',   'True')
)

# A password only applies with its Use* flag
if ($Env:RVS_GAME_PASSWORD) {
    $settings += , @('GamePassword', $Env:RVS_GAME_PASSWORD)
    $settings += , @('UsePassword', 'True')
}
if ($Env:RVS_ADMIN_PASSWORD) {
    $settings += , @('AdminPassword', $Env:RVS_ADMIN_PASSWORD)
    $settings += , @('UseAdminPassword', 'True')
}

foreach ($s in $settings) {
    if ($s[1]) { Set-IniValue $section $s[0] $s[1] }
}

# Game types: short names -> classes. Athena Sword (ASGame) and Iron Wrath (MP2Game) types need
# their mod.
$gameTypes = [ordered]@{
    'survival'         = 'R6Game.R6DeathMatch'
    'dm'               = 'R6Game.R6DeathMatch'
    'teamsurvival'     = 'R6Game.R6TeamDeathMatchGame'
    'tdm'              = 'R6Game.R6TeamDeathMatchGame'
    'bomb'             = 'R6Game.R6TeamBomb'
    'hostage'          = 'R6Game.R6HostageRescueAdvGame'
    'pilot'            = 'R6Game.R6EscortPilotGame'
    'escort'           = 'R6Game.R6EscortPilotGame'
    'mission'          = 'R6Game.R6MissionGame'
    'terroristhunt'    = 'R6Game.R6TerroristHuntCoopGame'
    'th'               = 'R6Game.R6TerroristHuntCoopGame'
    'hostagerescue'    = 'R6Game.R6HostageRescueCoopGame'
    'capturetheenemy'  = 'ASGame.R6CaptureTheEnemyAdvGame'
    'cte'              = 'ASGame.R6CaptureTheEnemyAdvGame'
    'kamikaze'         = 'ASGame.R6KamikazeGame'
    'scatteredhunt'    = 'ASGame.R6ScatteredHuntAdvGame'
    'terroristhuntadv' = 'ASGame.R6TerroristHuntAdvGame'
    'countdown'        = 'ASGame.R6CountDownGame'
    'limitseats'       = 'MP2Game.MP2LimitSeatsAdvGame'
    'freebackup'       = 'MP2Game.MP2FreeBackupAdvGame'
    'gasalert'         = 'MP2Game.MP2GazAlertAdvGame'
    'virusupload'      = 'MP2Game.MP2VirusUploadAdvGame'
    'intruder'         = 'MP2Game.MP2IntruderAdvGame'
}

function Resolve-GameType([string] $Name) {
    if (-not $Name) { return 'R6Game.R6TeamDeathMatchGame' }
    $key = $Name.ToLowerInvariant() -replace '[\s_-]', ''
    if ($gameTypes.Contains($key)) { return $gameTypes[$key] }
    return $Name
}

$defaultType = Resolve-GameType $Env:RVS_GAME_TYPE

# Map rotation: [Engine.R6MapList] Maps[0..31] and GameType[0..31]. The server starts on Maps[0].
$entries = @($Env:RVS_MAPS -split '[,;\s]+' | Where-Object { $_ })
if ($entries) {
    # Installed maps: maps/*.rsm and Mods/*/Maps/*.rsm
    $available = @{}
    $mapDirs = @(Resolve-Path-CI $root 'maps')
    $modsDir = Resolve-Path-CI $root 'Mods'
    if ($modsDir) {
        Get-ChildItem -Path $modsDir -Directory | ForEach-Object { $mapDirs += Resolve-Path-CI $_.FullName 'Maps' }
    }
    foreach ($dir in ($mapDirs | Where-Object { $_ })) {
        Get-ChildItem -Path $dir -Filter '*.rsm' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $available[$_.BaseName.ToLowerInvariant()] = $_.BaseName }
    }

    $rotation = @()
    foreach ($entry in $entries) {
        $map, $type = $entry -split ':', 2
        $map = $map -replace '\.rsm$', ''

        if ($available.Count -and -not $available.ContainsKey($map.ToLowerInvariant())) {
            Write-Log -Level Warning "Map $map is not installed; left out of the rotation"
            continue
        }
        if ($available.Count) { $map = $available[$map.ToLowerInvariant()] }

        $class = if ($type) { Resolve-GameType $type } else { $defaultType }
        if ($class -like 'ASGame.*' -and $mod -ine 'AthenaSword') {
            Write-Log -Level Warning "$class is an Athena Sword game type; it needs RVS_MOD=AthenaSword"
        }
        if ($class -like 'MP2Game.*' -and $mod -ine 'IronWrath') {
            Write-Log -Level Warning "$class is an Iron Wrath game type; it needs RVS_MOD=IronWrath"
        }

        if ($rotation.Count -ge 32) {
            Write-Log -Level Warning "The rotation holds 32 maps; left out $map"
            continue
        }
        $rotation += , @($map, $class)
    }

    if ($rotation.Count) {
        for ($i = 0; $i -lt 32; $i++) {
            $m = if ($i -lt $rotation.Count) { $rotation[$i][0] } else { '' }
            $c = if ($i -lt $rotation.Count) { $rotation[$i][1] } else { '' }
            Set-IniValue 'Engine.R6MapList' "GameType[$i]" $c
            Set-IniValue 'Engine.R6MapList' "Maps[$i]" $m
        }
        Write-Log "Map rotation: $(($rotation | ForEach-Object { "$($_[0]) ($($_[1]))" }) -join ', ')"
    } else {
        Write-Log -Level Warning "None of RVS_MAPS is installed; [Engine.R6MapList] in $iniName is left as it is"
    }
}

[System.IO.File]::WriteAllText($ini, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $ini

Write-Log "Applied RVS_* settings to $ini"
