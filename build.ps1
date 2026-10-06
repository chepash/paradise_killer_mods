# Builds the drop-in package:
#   dist\Win64\                 copy its contents into <game>\ParadiseKiller\Binaries\Win64
#   dist\PKMods-<version>.zip   the same, zipped for a GitHub release
#
# UE4SS isn't kept in git: it's downloaded once (cached in .cache\), checked
# against a pinned SHA-256, and only the parts we ship are extracted. Our own
# files come from package\ and are laid over it.
param(
    [string]$Version = (Get-Content (Join-Path $PSScriptRoot "VERSION")).Trim()
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

# UE4SS experimental build (changelog: v4.0.0-rc1). "experimental-latest" is a
# rolling tag: if this asset disappears or changes, the hash check fails, so
# pick the new asset, test it in the game, then update both lines.
$UE4SS_URL    = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/zDEV-UE4SS_v3.0.1-1152-ge3ba1016.zip"
$UE4SS_SHA256 = "7D2DC6163C92714C15CB7DF7179D8333581FDF655275FE10EC0B5B7687C77D00"

$cache   = Join-Path $PSScriptRoot ".cache"
$zipPath = Join-Path $cache ([IO.Path]::GetFileName($UE4SS_URL))
$dist    = Join-Path $PSScriptRoot "dist"
$out     = Join-Path $dist "Win64"
$utf8    = New-Object Text.UTF8Encoding $false

# 1. UE4SS archive (cached)
New-Item -ItemType Directory -Force $cache | Out-Null
if (-not (Test-Path $zipPath)) {
    Write-Host "Downloading $([IO.Path]::GetFileName($UE4SS_URL))..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $UE4SS_URL -OutFile $zipPath -UseBasicParsing
}
$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
if ($hash -ne $UE4SS_SHA256) {
    Remove-Item $zipPath
    throw "UE4SS archive hash mismatch ($hash). The release has changed; see the comment at the top of build.ps1."
}

# 2. Clean output
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null

# 3. The parts of UE4SS we ship (no PDB, no demo mods, no configs for other games)
function Shipped([string]$name) {
    return $name -eq "dwmapi.dll" -or
        $name -in @("ue4ss/UE4SS.dll", "ue4ss/UE4SS-settings.ini", "ue4ss/LICENSE") -or
        $name.StartsWith("ue4ss/Mods/shared/") -or
        $name.StartsWith("ue4ss/Mods/Keybinds/")
}
$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    foreach ($e in $zip.Entries) {
        if ($e.Name -eq "" -or -not (Shipped $e.FullName)) { continue }
        $target = Join-Path $out ($e.FullName -replace "/", "\")
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $target, $true)
    }
} finally {
    $zip.Dispose()
}

# 4. Our changes to UE4SS files
function Patch([string]$rel, [string]$pattern, [string]$replacement) {
    $p = Join-Path $out $rel
    $text = [IO.File]::ReadAllText($p)
    $new = [regex]::Replace($text, $pattern, $replacement)
    if ($new -eq $text) { throw "Patch didn't apply to $rel ($pattern)" }
    [IO.File]::WriteAllText($p, $new, $utf8)
}
# Hot reload (Ctrl+R) stays OFF, as UE4SS ships it: with this game it hung the game
# four times right after "All mods re-installed". Mods load fresh at game start.
# ObjectDumper sat on Ctrl+J, which is our Air Control toggle; Num5 is taken by DumpJMAP
Patch "ue4ss\Mods\Keybinds\Scripts\main.lua" '(\["ObjectDumper"\][^\n]*?)Key\.J, ' '${1}Key.NUM_FOUR,'

# 5. Our files: mods list + the PKMods mod
Copy-Item -Path (Join-Path $PSScriptRoot "package\*") -Destination $out -Recurse -Force

# 6. Release archive
$zipOut = Join-Path $dist "PKMods-$Version.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut }
[IO.Compression.ZipFile]::CreateFromDirectory($out, $zipOut)

$size = "{0:N1} MB" -f ((Get-Item $zipOut).Length / 1MB)
Write-Host "Built PKMods $Version -> $out"
Write-Host "Release archive: $zipOut ($size)"
