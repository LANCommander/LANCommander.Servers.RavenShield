#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Raven Shield is retail software with no public download. Use an existing install in
# /config/Server, or set RVS_ARCHIVE_URL to a zip of the game folder, e.g. a LANCommander
# archive. The folder holding system/R6Game.u and system/UCC.exe is used, so the game may sit in a
# subfolder of the zip. The retail install's folder is a lowercase system/; System/ works too.

Invoke-Hook "PreInstallRavenShield"

function Find-System([string] $Root) {
    foreach ($name in @('system', 'System')) {
        $dir = Join-Path $Root $name
        if (Test-Path -Path (Join-Path $dir 'UCC.exe')) { return $dir }
    }
    return $null
}

if (Find-System $Env:SERVER_DIR) {
    Write-Log "Raven Shield found in $Env:SERVER_DIR"
} elseif ($Env:RVS_ARCHIVE_URL) {
    Write-Log "Downloading Raven Shield from $Env:RVS_ARCHIVE_URL"

    $zip     = '/tmp/ravenshield.zip'
    $extract = '/tmp/ravenshield'

    curl -fL --retry 3 --output $zip "$Env:RVS_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:RVS_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    $root = Get-ChildItem -Path $extract -Filter 'R6Game.u' -Recurse -File -Depth 3 |
        Where-Object { $_.Directory.Name -ieq 'system' -and (Test-Path (Join-Path $_.DirectoryName 'UCC.exe')) } |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "system/R6Game.u and system/UCC.exe not found in $Env:RVS_ARCHIVE_URL" }

    # The server doesn't need the videos or the uninstaller
    foreach ($skip in @('Videos', 'Uninstall', '_manifest.yml')) {
        Remove-Item -Recurse -Force -Path (Join-Path $root.Parent.FullName $skip) -ErrorAction SilentlyContinue
    }
    Get-ChildItem -Path (Join-Path $root.Parent.FullName 'Mods') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -Recurse -Force -Path (Join-Path $_.FullName 'Videos') -ErrorAction SilentlyContinue }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root.Parent.FullName '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Raven Shield installed"
} else {
    Write-Log -Level Error "system/UCC.exe not found in $Env:SERVER_DIR. Copy a Raven Shield install there or set RVS_ARCHIVE_URL."
}

Invoke-Hook "PostInstallRavenShield"

Set-Location $Env:SERVER_ROOT
