# Builds the package (build.ps1) and copies dist\Win64 into the game. Same as
# copying the contents of dist\Win64 into  <game>\ParadiseKiller\Binaries\Win64
# by hand. Your in-game settings (ue4ss\Mods\PKMods\settings.txt) are kept.
param(
    [string]$GameDir = "D:\games\steamapps\common\Paradise Killer",
    [switch]$NoBuild
)
$ErrorActionPreference = "Stop"

$dst = Join-Path $GameDir "ParadiseKiller\Binaries\Win64"
$src = Join-Path $PSScriptRoot "dist\Win64"

if (-not $NoBuild) { & (Join-Path $PSScriptRoot "build.ps1") }

if (-not (Test-Path (Join-Path $dst "ParadiseKiller-Win64-Shipping.exe"))) {
    throw "Game exe not found in $dst (pass -GameDir)"
}

# UE4SS 3.0.1 kept everything next to the exe; newer UE4SS uses a ue4ss\ subfolder.
# Carry the settings over before the old layout is removed.
$oldSettings = Join-Path $dst "Mods\PKMods\settings.txt"
$newSettings = Join-Path $dst "ue4ss\Mods\PKMods\settings.txt"
if ((Test-Path $oldSettings) -and -not (Test-Path $newSettings)) {
    New-Item -ItemType Directory -Force (Split-Path $newSettings) | Out-Null
    Copy-Item $oldSettings $newSettings
    Write-Host "moved settings.txt to the ue4ss folder"
}

# Leftovers of older installs: the 3.0.1 layout and the separate
# AirControl / BloodCrystalRadar mods.
$old = @(
    "UE4SS.dll", "UE4SS-settings.ini", "Mods",
    "CustomGameConfigs", "MapGenBP", "MemberVarLayoutTemplates", "VTableLayoutTemplates", "UE4SS_Signatures"
)
foreach ($p in $old) {
    $full = Join-Path $dst $p
    if (Test-Path $full) { Remove-Item -Recurse -Force $full; Write-Host "removed old $p" }
}

# Copy only changed files: unchanged DLLs are locked while the game runs, and
# skipping them lets Lua updates go in for a Ctrl+R hot reload.
$copied = 0
Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
    $rel    = $_.FullName.Substring($src.Length + 1)
    $target = Join-Path $dst $rel
    if ((Test-Path $target) -and
        (Get-FileHash $target).Hash -eq (Get-FileHash $_.FullName).Hash) { return }
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item -Path $_.FullName -Destination $target -Force
    Write-Host "  $rel"
    $copied++
}
# Our Scripts folder is mirrored exactly: scripts removed from the package are
# removed from the game too (settings.txt and logs live one level up, untouched).
$scriptsSrc = Join-Path $src "ue4ss\Mods\PKMods\Scripts"
$scriptsDst = Join-Path $dst "ue4ss\Mods\PKMods\Scripts"
Get-ChildItem -Path $scriptsDst -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($scriptsDst.Length + 1)
    if (-not (Test-Path (Join-Path $scriptsSrc $rel))) {
        Remove-Item $_.FullName
        Write-Host "  removed stale Scripts\$rel"
    }
}

Write-Host "Installed to $dst ($copied file(s) updated)"
